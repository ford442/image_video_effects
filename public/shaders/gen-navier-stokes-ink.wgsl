// ═══════════════════════════════════════════════════════════════════
//  Navier-Stokes Ink - 2D fluid simulation with ink injection
//  Category: generative
//  Features: upgraded-rgba, aces-tone-map, depth-aware, audio-reactive, temporal, mouse-driven, jacobi-pressure, curl-noise, anisotropic-diffusion, dye-sdf, hue-preserve-clamp, ign-dither
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-07-13
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

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hue-preserve-clamp ═══
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return c * min(1.0, maxLum / max(l, 1e-4));
}

// ═══ CHUNK: ign-dither ═══
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// ═══ Hash and FBM for curl-noise perturbation ═══
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + a * noise(p * f);
    f = f * 2.0;
    a = a * 0.5;
  }
  return v;
}

fn curlNoise(p: vec2<f32>) -> vec2<f32> {
  let eps = 0.01;
  let n0 = fbm(p);
  let nx = fbm(p + vec2<f32>(eps, 0.0));
  let ny = fbm(p + vec2<f32>(0.0, eps));
  let ddx = (nx - n0) / eps;
  let ddy = (ny - n0) / eps;
  return vec2<f32>(ddy, -ddx);
}

// ═══ Procedural SDF dye primitives ═══
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

fn smoothStep01(e0: f32, e1: f32, x: f32) -> f32 {
  let t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let time = u.config.x;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let bass = plasmaBuffer[0].x;
  let mouseUV = u.zoom_config.yz;
  let mouseDown = step(0.5, u.zoom_config.w);

  let injectionRate = mix(0.3, 1.2, u.zoom_params.x) * (1.0 + bass * 0.5);
  let viscosity = mix(0.92, 0.65, u.zoom_params.y);
  let dispersion = u.zoom_params.z;
  let vorticityScale = u.zoom_params.w;

  let texel = 1.0 / resolution;
  let dt = 0.7;

  // Previous-frame state (velocity.xy, ink density .z)
  let c = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var vel = c.rg;
  var ink = c.b;

  // Curl-noise velocity perturbation, audio-reactive on bass
  let noiseUV = uv * 3.0 + time * 0.15;
  let curl1 = curlNoise(noiseUV) * 0.02 * (1.0 + bass);
  let curl2 = curlNoise(noiseUV * 2.3 + vec2<f32>(time * 0.07, -time * 0.11)) * 0.01;
  vel = vel + (curl1 + curl2) * vorticityScale;

  // Domain-warped FBM semi-Lagrangian advection
  var backUV = uv - vel * texel * dt;
  backUV = backUV + curlNoise(backUV * 4.0 + time * 0.2) * texel * 0.5 * dispersion;
  let advected = textureSampleLevel(dataTextureC, u_sampler, backUV, 0.0);
  var newVel = advected.rg;
  var newInk = advected.b;

  // Anisotropic density diffusion aligned to local flow direction
  let speed = length(newVel);
  let flow = select(vec2<f32>(1.0, 0.0), newVel / max(speed, 1e-4), speed > 1e-4);
  let perp = vec2<f32>(-flow.y, flow.x);
  let diffScale = texel * mix(1.0, 3.0, speed * 10.0) * (0.5 + dispersion);
  let fInk = textureSampleLevel(dataTextureC, u_sampler, uv + flow * diffScale, 0.0).b;
  let bInk = textureSampleLevel(dataTextureC, u_sampler, uv - flow * diffScale, 0.0).b;
  let lInk = textureSampleLevel(dataTextureC, u_sampler, uv + perp * diffScale * 0.4, 0.0).b;
  let rInk = textureSampleLevel(dataTextureC, u_sampler, uv - perp * diffScale * 0.4, 0.0).b;
  let isoInk = (fInk + bInk + lInk + rInk) * 0.25;
  newInk = mix(newInk, isoInk, 0.12 * (1.0 - viscosity));

  // Mouse attraction force (branchless via mix)
  let mouseForce = (mouseUV - uv) * mouseDown * 4.0;
  newVel = newVel + mouseForce * dt;

  // Cardinal neighbors for diffusion, vorticity, and pressure
  let vn = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0);
  let vs = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0);
  let ve = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0);
  let vw = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0);

  // Isotropic velocity diffusion
  let avgVel = (vn.rg + vs.rg + ve.rg + vw.rg) * 0.25;
  newVel = mix(newVel, avgVel, 1.0 - viscosity);

  // Vorticity confinement
  let curl = (ve.g - vw.g) - (vn.r - vs.r);
  let vorticity = abs(curl) * vorticityScale;
  let eta = vec2<f32>(abs(vs.g) - abs(vn.g), abs(ve.r) - abs(vw.r));
  let etaLen = max(length(eta), 1e-4);
  let vortForce = (eta / etaLen) * curl * vorticityScale * 0.05 * (1.0 + bass);
  newVel = newVel + vortForce * dt;

  // Second Jacobi pressure-projection iteration
  // p^1 = (div + pN^0 + pS^0 + pE^0 + pW^0) / 4, where p^0 = -div * 0.25
  let div = (ve.r - vw.r + vn.g - vs.g) * 0.5;

  let vne = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( texel.x,  texel.y), 0.0);
  let vnw = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x,  texel.y), 0.0);
  let vse = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( texel.x, -texel.y), 0.0);
  let vsw = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0);
  let vnn = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0,  texel.y * 2.0), 0.0);
  let vss = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, -texel.y * 2.0), 0.0);
  let vee = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( texel.x * 2.0, 0.0), 0.0);
  let vww = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x * 2.0, 0.0), 0.0);

  let divN = (vnw.r - vne.r + vnn.g - c.g) * 0.5;
  let divS = (vse.r - vsw.r + c.g - vss.g) * 0.5;
  let divE = (vee.r - c.r + vne.g - vse.g) * 0.5;
  let divW = (c.r - vww.r + vnw.g - vsw.g) * 0.5;

  let pN = -divN * 0.25;
  let pS = -divS * 0.25;
  let pE = -divE * 0.25;
  let pW = -divW * 0.25;

  let pressure = (div + pN + pS + pE + pW) * 0.25;
  let gradP = vec2<f32>((pE - pW) * 0.5, (pN - pS) * 0.5);
  newVel = newVel - gradP * dt;

  // Procedural dye SDF layer: orbiting drops + stretched filament
  let drop1 = mouseUV + vec2<f32>(sin(time * 0.9), cos(time * 0.7)) * 0.08;
  let drop2 = vec2<f32>(0.5 + sin(time * 0.4) * 0.25, 0.5 + cos(time * 0.6) * 0.2);
  let d1 = sdCircle(uv - drop1, 0.035 + bass * 0.02);
  let d2 = sdCircle(uv - drop2, 0.045);
  let drops = smoothStep01(0.0, 0.06, -min(d1, d2));

  let filamentTip = mouseUV + newVel * 0.08;
  let fil = sdSegment(uv, mouseUV, filamentTip) - 0.01;
  let filament = smoothStep01(0.0, 0.04, -fil) * speed * 4.0 * mouseDown;

  let source = exp(-length(uv - mouseUV) * length(uv - mouseUV) * 600.0) * mouseDown * injectionRate;
  newInk = newInk + (source + drops * injectionRate * 0.5 + filament * injectionRate) * dt;
  newInk = newInk * (0.992 - dispersion * 0.02);

  // Color grading: deep ink + eddy highlights + drop tint
  let inkColor = vec3<f32>(0.05, 0.08, 0.2);
  let deepInk = vec3<f32>(0.02, 0.03, 0.12);
  let eddyColor = vec3<f32>(0.3, 0.5, 1.0);
  let dropColor = vec3<f32>(0.5, 0.2, 0.9);

  var col = mix(deepInk, inkColor, newInk * 3.0);
  col = mix(col, dropColor, drops * 0.4);
  col = col + eddyColor * vorticity * newInk * 2.0;
  col = col + vec3<f32>(0.6, 0.7, 1.0) * vorticity * vorticity * 0.3;

  let shear = speed * 2.0;
  let chromaR = newInk * (1.0 + shear * 0.5);
  let chromaB = newInk * (1.0 - shear * 0.3);
  col = col + vec3<f32>(chromaR * 0.15, 0.0, chromaB * 0.2) * shear;

  var outCol = acesToneMapping(huePreserveClamp(col * 1.5, 2.0));
  outCol += (ign(vec2<f32>(coord)) - 0.5) / 255.0;

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  let alpha = clamp(newInk * depth * 1.5 + vorticity * depth * 0.3, 0.0, 0.9);

  let finalColor = mix(inputColor.rgb, outCol, alpha);
  let finalAlpha = max(inputColor.a, alpha);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(newInk * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(newVel.x, newVel.y, newInk, alpha));
  textureStore(dataTextureB, coord, vec4<f32>(pressure, curl * 0.5, div, speed));
}
