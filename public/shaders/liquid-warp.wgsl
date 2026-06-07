// ═══════════════════════════════════════════════════════════════════
//  Liquid Warp
//  Category: interactive-mouse
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: Very High
//  Scientific: Semi-Lagrangian Navier-Stokes warp with RK4 backtracing, divergence-free curl-noise forcing, strain-driven vortex stretching, and depth-weighted drag
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
  let e = 0.04;
  let dx = valueNoise(p + vec2<f32>(e, 0.0)) - valueNoise(p - vec2<f32>(e, 0.0));
  let dy = valueNoise(p + vec2<f32>(0.0, e)) - valueNoise(p - vec2<f32>(0.0, e));
  return safeNormalize(vec2<f32>(dy, -dx));
}

fn stateAt(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(dataTextureC, u_sampler, clampUV(uv), 0.0);
}

fn depthGradient(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
  let left = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv - vec2<f32>(texel.x, 0.0)), 0.0).r;
  let right = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv + vec2<f32>(texel.x, 0.0)), 0.0).r;
  let up = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv - vec2<f32>(0.0, texel.y)), 0.0).r;
  let down = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampUV(uv + vec2<f32>(0.0, texel.y)), 0.0).r;
  return vec2<f32>((right - left) / (2.0 * texel.x), (down - up) / (2.0 * texel.y));
}

fn velocityField(
  uv: vec2<f32>,
  texel: vec2<f32>,
  time: f32,
  warpScale: f32,
  turbulence: f32,
  mouse: vec2<f32>,
  mouseDown: f32,
  bass: f32,
  treble: f32,
  aspect: f32
) -> vec2<f32> {
  let previous = stateAt(uv).rg;
  let dragGradient = depthGradient(uv, texel);
  let density = clamp(length(dragGradient) * 0.02, 0.0, 0.85);

  var flow = previous * 0.965;
  flow += curlNoise(uv * 3.0 + vec2<f32>(time * 0.09, -time * 0.05)) * (0.0010 + 0.0045 * turbulence + 0.0040 * bass);
  flow += curlNoise(uv * 9.0 + vec2<f32>(-time * 0.17, time * 0.11)) * (0.0006 + 0.0025 * turbulence + 0.0025 * treble);
  flow += curlNoise(uv * 21.0 + vec2<f32>(time * 0.29, time * 0.23)) * (0.00025 + 0.0016 * treble);

  let delta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(delta);
  let envelope = exp(-dist * (8.0 + 12.0 * warpScale)) * mouseDown;
  let swirl = safeNormalize(vec2<f32>(-delta.y, delta.x)) * envelope * (0.0015 + 0.0100 * warpScale);
  let pull = -safeNormalize(delta) * envelope * (0.0008 + 0.0040 * turbulence);

  let centered = (uv - vec2<f32>(0.5, 0.5)) * vec2<f32>(aspect, 1.0);
  let rmsRotation = safeNormalize(vec2<f32>(-centered.y, centered.x)) * bass * (0.0007 + 0.0035 * warpScale);

  return (flow + swirl + pull + rmsRotation) * (1.0 - density);
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

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let warpScale = 0.35 + 1.45 * clamp(u.zoom_params.x, 0.0, 1.0);
  let turbulence = clamp(u.zoom_params.y, 0.0, 1.0);
  let stretchParam = clamp(u.zoom_params.z, 0.0, 1.0);
  let chroma = 0.2 + 1.4 * clamp(u.zoom_params.w, 0.0, 1.0);
  let mouse = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
  let dt = 0.7;

  let k1 = velocityField(uv, texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect);
  let k2 = velocityField(clampUV(uv - 0.5 * dt * k1), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect);
  let k3 = velocityField(clampUV(uv - 0.5 * dt * k2), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect);
  let k4 = velocityField(clampUV(uv - dt * k3), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect);
  let departure = clampUV(uv - (dt / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4));

  let advectedState = stateAt(departure);
  var velocity = mix(advectedState.rg, k1, 0.45 + 0.25 * bass);

  let leftVel = velocityField(uv - vec2<f32>(texel.x, 0.0), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect);
  let rightVel = velocityField(uv + vec2<f32>(texel.x, 0.0), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect);
  let upVel = velocityField(uv - vec2<f32>(0.0, texel.y), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect);
  let downVel = velocityField(uv + vec2<f32>(0.0, texel.y), texel, time, warpScale, turbulence, mouse, mouseDown, bass, treble, aspect);

  let du_dx = (rightVel.x - leftVel.x) / (2.0 * texel.x);
  let dv_dy = (downVel.y - upVel.y) / (2.0 * texel.y);
  let du_dy = (downVel.x - upVel.x) / (2.0 * texel.y);
  let dv_dx = (rightVel.y - leftVel.y) / (2.0 * texel.x);
  let shear = du_dy + dv_dx;
  let vorticity = dv_dx - du_dy;
  let stretch = 1.0 + stretchParam * clamp(abs(shear) * 0.01, 0.0, 2.0);
  velocity *= stretch * (0.95 + 0.05 * mids);

  let displaced = uv - departure;
  let displacementMag = length(displaced);
  let omegaVisual = clamp(abs(vorticity) * 0.015, 0.0, 1.0);

  let aberration = safeNormalize(displaced + velocity * 0.5) * displacementMag * chroma * (1.6 + 1.4 * treble);
  let sampleR = textureSampleLevel(readTexture, u_sampler, clampUV(departure - aberration), 0.0).r;
  let sampleG = textureSampleLevel(readTexture, u_sampler, departure, 0.0).g;
  let sampleB = textureSampleLevel(readTexture, u_sampler, clampUV(departure + aberration), 0.0).b;
  let warpedColor = vec3<f32>(sampleR, sampleG, sampleB);

  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, departure, 0.0).r;
  let highlight = vec3<f32>(0.10, 0.18, 0.30) * omegaVisual + vec3<f32>(0.06, 0.02, 0.14) * displacementMag * 3.5;
  let finalColor = clamp(warpedColor + highlight, vec3<f32>(0.0), vec3<f32>(1.0));
  let alpha = clamp(0.82 + 0.10 * omegaVisual + 0.05 * displacementMag * resolution.x, 0.0, 1.0);
  let depthProxy = clamp(depthSample * 0.55 + displacementMag * 6.0 + omegaVisual * 0.35, 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(velocity, clamp(displacementMag * 6.0, 0.0, 1.0), omegaVisual));
  textureStore(dataTextureB, global_id.xy, vec4<f32>(clamp(abs(shear) * 0.01, 0.0, 1.0), clamp(stretch * 0.25, 0.0, 1.0), clamp(length(velocity) * 80.0, 0.0, 1.0), 1.0));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthProxy, 0.0, 0.0, 1.0));
}
