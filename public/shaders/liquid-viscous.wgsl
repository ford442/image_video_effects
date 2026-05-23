// ═══════════════════════════════════════════════════════════════════
//  Liquid Viscous
//  Category: image
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: Very High
//  Scientific: 2D incompressible Navier-Stokes with vorticity confinement, turbulence cascade, semi-Lagrangian advection, and dye roll-up
//  Upgraded: 2026-05-23
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn clampUV(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let len2 = dot(v, v);
  if (len2 < 1e-8) {
    return vec2<f32>(0.0, 0.0);
  }
  return v * inverseSqrt(len2);
}

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123;
  return fract(h);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);

  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));

  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn curlNoise(p: vec2<f32>) -> vec2<f32> {
  let e = 0.05;
  let dx = valueNoise(p + vec2<f32>(e, 0.0)) - valueNoise(p - vec2<f32>(e, 0.0));
  let dy = valueNoise(p + vec2<f32>(0.0, e)) - valueNoise(p - vec2<f32>(0.0, e));
  return safeNormalize(vec2<f32>(dy, -dx));
}

fn sampleState(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(dataTextureC, u_sampler, clampUV(uv), 0.0);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(vec3<f32>(c.x) + k.xyz) * 6.0 - vec3<f32>(k.www));
  return c.z * mix(vec3<f32>(k.x), clamp(p - vec3<f32>(k.x), vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn vorticityAt(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
  let leftState = sampleState(uv - vec2<f32>(texel.x, 0.0));
  let rightState = sampleState(uv + vec2<f32>(texel.x, 0.0));
  let upState = sampleState(uv - vec2<f32>(0.0, texel.y));
  let downState = sampleState(uv + vec2<f32>(0.0, texel.y));
  let dvdx = (rightState.y - leftState.y) / (2.0 * texel.x);
  let dudy = (downState.x - upState.x) / (2.0 * texel.y);
  return dvdx - dudy;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let texel = 1.0 / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let viscosity = clamp(u.zoom_params.x, 0.001, 1.0);
  let confinement = max(u.zoom_params.y, 0.0);
  let injectionScale = 0.35 + 1.65 * clamp(u.zoom_params.z, 0.0, 1.0);
  let hueShift = u.zoom_params.w;
  let dt = 0.55;

  let centerState = sampleState(uv);
  let leftState = sampleState(uv - vec2<f32>(texel.x, 0.0));
  let rightState = sampleState(uv + vec2<f32>(texel.x, 0.0));
  let upState = sampleState(uv - vec2<f32>(0.0, texel.y));
  let downState = sampleState(uv + vec2<f32>(0.0, texel.y));

  let departure = clampUV(uv - centerState.rg * dt);
  let advectedState = sampleState(departure);
  var velocity = advectedState.rg;
  var dye = advectedState.b * exp(-viscosity * 0.025);

  let omega = vorticityAt(uv, texel);
  let omegaL = abs(vorticityAt(uv - vec2<f32>(texel.x, 0.0), texel));
  let omegaR = abs(vorticityAt(uv + vec2<f32>(texel.x, 0.0), texel));
  let omegaU = abs(vorticityAt(uv - vec2<f32>(0.0, texel.y), texel));
  let omegaD = abs(vorticityAt(uv + vec2<f32>(0.0, texel.y), texel));

  let eta = safeNormalize(vec2<f32>(omegaR - omegaL, omegaD - omegaU));
  let confinementForce = vec2<f32>(eta.y, -eta.x) * clamp(omega, -40.0, 40.0) * confinement * 0.00003;

  var cascadeForce = vec2<f32>(0.0, 0.0);
  cascadeForce += curlNoise(uv * 3.0 + vec2<f32>(time * 0.07, -time * 0.03)) * (0.00025 + 0.0018 * bass);
  cascadeForce += curlNoise(uv * 8.0 + vec2<f32>(-time * 0.11, time * 0.05)) * (0.00018 + 0.0011 * mids);
  cascadeForce += curlNoise(uv * 18.0 + vec2<f32>(time * 0.19, time * 0.13)) * (0.00012 + 0.0010 * treble);
  cascadeForce *= injectionScale * (1.15 - 0.65 * viscosity);

  let mouse = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
  let toMouse = (uv - mouse) * aspectVec;
  let mouseDist = length(toMouse);
  let mouseEnvelope = exp(-mouseDist * 22.0) * mouseDown;
  let mouseCurl = safeNormalize(vec2<f32>(-toMouse.y, toMouse.x)) * mouseEnvelope * (0.0015 + 0.0075 * treble);

  var rippleForce = vec2<f32>(0.0, 0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 4.0) {
      continue;
    }
    let delta = (uv - ripple.xy) * aspectVec;
    let r = length(delta);
    let ring = sin(r * 42.0 - age * 7.0) * exp(-r * 11.0 - age * 0.8);
    rippleForce += safeNormalize(vec2<f32>(-delta.y, delta.x)) * ring * (0.0006 + 0.0030 * bass);
    dye += exp(-r * 18.0 - age * 1.2) * (0.04 + 0.12 * bass);
  }

  var audioVortices = vec2<f32>(0.0, 0.0);
  let audioPhase = floor(time * 0.7);
  for (var j: i32 = 0; j < 3; j = j + 1) {
    let jf = f32(j);
    let seed = audioPhase + jf * 17.0;
    let center = vec2<f32>(hash12(vec2<f32>(seed, 1.37)), hash12(vec2<f32>(seed, 9.19)));
    let delta = (uv - center) * aspectVec;
    let r = length(delta);
    let envelope = exp(-r * (10.0 + jf * 3.0));
    audioVortices += safeNormalize(vec2<f32>(-delta.y, delta.x)) * envelope * bass * (0.0014 + jf * 0.0005);
  }

  velocity += (confinementForce + cascadeForce + mouseCurl + rippleForce + audioVortices) * dt;
  velocity *= 1.0 / (1.0 + 10.0 * viscosity * dt);

  let divergence = ((rightState.x - leftState.x) / (2.0 * texel.x)) + ((downState.y - upState.y) / (2.0 * texel.y));
  let pL = leftState.a;
  let pR = rightState.a;
  let pU = upState.a;
  let pD = downState.a;
  var pressure = centerState.a;
  for (var iter: i32 = 0; iter < 4; iter = iter + 1) {
    pressure = (pL + pR + pU + pD - divergence) * 0.25;
  }
  let gradPressure = vec2<f32>((pR - pL) / (2.0 * texel.x), (pD - pU) / (2.0 * texel.y));
  velocity -= gradPressure * 0.0004;

  let advectedColor = textureSampleLevel(readTexture, u_sampler, clampUV(uv + velocity * 0.35), 0.0);
  let sourceDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv + velocity * 0.2), 0.0).r;
  let luma = dot(advectedColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  dye = clamp(mix(dye, luma, 0.05) + mouseEnvelope * 0.18 + bass * 0.06 + abs(omega) * 0.0004, 0.0, 1.0);

  let vorticityVisual = clamp(abs(omega) * 0.02, 0.0, 1.0);
  let hue = fract(0.58 + hueShift * 0.25 + dye * 0.22 + vorticityVisual * 0.30 + treble * 0.08 + sin(time * 0.13) * 0.04);
  let saturation = clamp(0.55 + 0.25 * dye + 0.35 * vorticityVisual + 0.15 * mids, 0.0, 1.0);
  let value = clamp(0.35 + 0.55 * dye + 0.45 * vorticityVisual + 0.20 * luma, 0.0, 1.0);
  let iridescent = hsv2rgb(vec3<f32>(hue, saturation, value));
  let rollupGlow = vec3<f32>(0.20, 0.10, 0.32) * vorticityVisual + vec3<f32>(0.10, 0.18, 0.28) * dye;
  let blend = clamp(0.32 + 0.45 * dye + 0.28 * vorticityVisual, 0.0, 1.0);
  let finalColor = clamp(mix(advectedColor.rgb, iridescent + rollupGlow, blend), vec3<f32>(0.0), vec3<f32>(1.0));
  let alpha = clamp(0.78 + 0.18 * dye, 0.0, 1.0);
  let depthProxy = clamp(max(sourceDepth * 0.65, vorticityVisual * 0.9 + dye * 0.2), 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(velocity, dye, pressure));
  textureStore(dataTextureB, global_id.xy, vec4<f32>(vorticityVisual, clamp(abs(divergence) * 0.01, 0.0, 1.0), clamp(length(velocity) * 90.0, 0.0, 1.0), 1.0));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthProxy, 0.0, 0.0, 1.0));
}
