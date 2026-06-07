// ═══════════════════════════════════════════════════════════════════
//  Stable Fluids (Jos Stam)
//  Category: generative
//  Features: generative, simulation, audio-reactive, mouse-driven, temporal,
//            upgraded-rgba, aces-tone-map, chromatic-aberration, depth-aware
//  Complexity: Very High
//  Description: Classic stable fluids solver with pressure projection.
//  Velocity advection, force application, divergence estimation,
//  Jacobi pressure solve (warm-started), gradient subtraction,
//  dye advection, and audio-reactive color mapping.
//  Created: 2026-06-06
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const DT: f32 = 0.7;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn curlNoise(p: vec2<f32>) -> vec2<f32> {
  let eps = 0.01;
  let n1 = hash12(p + vec2<f32>(eps, 0.0));
  let n2 = hash12(p - vec2<f32>(eps, 0.0));
  let n3 = hash12(p + vec2<f32>(0.0, eps));
  let n4 = hash12(p - vec2<f32>(0.0, eps));
  return vec2<f32>((n4 - n3) / (2.0 * eps), (n1 - n2) / (2.0 * eps));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let texel = 1.0 / resolution;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouseUV = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Parameters
  let viscosity = mix(0.92, 0.65, u.zoom_params.x);
  let curlStrength = u.zoom_params.y * 3.0 * (1.0 + bass * 0.5);
  let dyeRate = mix(0.3, 1.5, u.zoom_params.z) * (1.0 + mids * 0.4);
  let colorIntensity = u.zoom_params.w;

  // ── Read previous state (RG=velocity, B=pressure, A=dye) ──
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var vel = prev.rg;
  let prevPressure = prev.b;
  var dye = prev.a;

  // ── Velocity advection (semi-Lagrangian backtrace) ──
  let backUV = uv - vel * texel * DT;
  let advected = textureSampleLevel(dataTextureC, u_sampler, backUV, 0.0);
  vel = advected.rg;
  dye = advected.a;

  // ── Apply forces ──
  // Curl noise for turbulent stirring
  let curl = curlNoise(uv * 4.0 + time * 0.15);
  vel = vel + curl * curlStrength * 0.05;

  // Mouse impulse (radial push + tangential swirl)
  let toMouse = uv - mouseUV;
  let dM2 = dot(toMouse, toMouse);
  let mouseGate = exp(-dM2 * 500.0) * (mouseDown * 2.0 + 0.5);
  let mouseDir = toMouse / max(length(toMouse), 1e-4);
  let tangent = vec2<f32>(-mouseDir.y, mouseDir.x);
  vel = vel + (mouseDir + tangent * 0.5) * mouseGate * 3.0;

  // Ripple forces
  for (var i = 0; i < 8; i++) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    let alive = f32(rip.z > 0.0 && age > 0.0 && age < 2.0);
    let toR = uv - rip.xy;
    let dr = length(toR);
    let force = exp(-dr * dr * 1200.0) * (1.0 - age * 0.5) * alive;
    vel = vel + (toR / max(dr, 1e-4)) * force * 2.0;
  }

  // Audio-driven global stirring
  vel = vel + vec2<f32>(sin(time * 2.0 + bass * PI) * bass * 0.02,
                         cos(time * 1.7 + treble * PI) * treble * 0.02);

  // ── Diffusion via neighbour averaging ──
  let vN = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rg;
  let vS = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).rg;
  let vE = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rg;
  let vW = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rg;
  let avgVel = (vN + vS + vE + vW) * 0.25;
  vel = mix(vel, avgVel, 1.0 - viscosity);

  // ── Divergence ──
  let div = (vE.x - vW.x + vN.y - vS.y) * 0.5;

  // ── Pressure solve (1 Jacobi step, warm-started) ──
  let pN = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).b;
  let pS = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).b;
  let pE = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).b;
  let pW = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).b;
  let pressure = (div + pN + pS + pE + pW) * 0.25;

  // ── Project velocity (subtract pressure gradient) ──
  let gradP = vec2<f32>(pE - pW, pN - pS) * 0.5;
  vel = vel - gradP;

  // ── Dye advection through projected velocity ──
  let dyeBackUV = uv - vel * texel * DT;
  dye = textureSampleLevel(dataTextureC, u_sampler, dyeBackUV, 0.0).a;

  // ── Dye sources ──
  let hue = fract(time * 0.08 + colorIntensity * 0.2 + bass * 0.1);
  let sourceColor = vec3<f32>(
    0.5 + 0.5 * cos(hue * 6.283),
    0.5 + 0.5 * cos(hue * 6.283 + 2.094),
    0.5 + 0.5 * cos(hue * 6.283 + 4.189)
  );

  // Mouse dye injection
  let mouseDye = exp(-dM2 * 600.0) * (mouseDown * 2.0 + 0.3) * dyeRate;
  dye = dye + mouseDye * DT;

  // Ripple dye injection
  for (var i = 0; i < 8; i++) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    let alive = f32(rip.z > 0.0 && age > 0.0 && age < 2.0);
    let dr = length(uv - rip.xy);
    let inject = exp(-dr * dr * 1500.0) * (1.0 - age * 0.5) * alive * dyeRate;
    dye = dye + inject * 0.5;
  }

  // Audio-driven background dye injection
  let audioDye = bass * 0.01 * (0.5 + 0.5 * sin(uv.x * 10.0 + time));
  dye = dye + audioDye;

  // Fade
  dye = dye * (0.992 - u.zoom_params.z * 0.005);

  // ── Color mapping ──
  let velMag = length(vel);
  let dyeColor = sourceColor * dye * 3.0;

  // Velocity-based temperature color
  let hotColor = vec3<f32>(1.0, 0.6, 0.2);
  let coolColor = vec3<f32>(0.1, 0.3, 0.8);
  let temp = clamp(velMag * 2.0, 0.0, 1.0);
  let flowColor = mix(coolColor, hotColor, temp);

  var color = mix(flowColor * 0.15, dyeColor, clamp(dye * 2.0, 0.0, 1.0));
  color = color + flowColor * velMag * dye * 2.0;

  // Audio reactivity boost
  color = color * (0.9 + bass * 0.2 + treble * 0.1);

  // ── Depth-aware compositing ──
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  // Semantic alpha
  let presence = clamp(length(color) * 1.5, 0.0, 1.0);
  let alpha = clamp(presence * (0.6 + depth * 0.3) + dye * 0.3, 0.15, 0.92);

  // ── Chromatic aberration ──
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001 + velMag * 0.002;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  // ── ACES tone mapping ──
  color = acesToneMap(color * 1.1);

  // Composite with input
  let finalColor = mix(inputColor.rgb, color, alpha);
  let finalAlpha = max(inputColor.a, alpha);

  // ── Output ──
  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(dye * depth, 0.0, 0.0, 0.0));
  // State: RG=velocity, B=pressure, A=dye
  textureStore(dataTextureA, coord, vec4<f32>(vel, pressure, dye));
}
