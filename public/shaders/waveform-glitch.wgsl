// ═══════════════════════════════════════════════════════════════════
//  Waveform Glitch
//  Category: retro-glitch
//  Features: temporal, audio-reactive, depth-aware
//  Complexity: Very High
//  Chunks From: waveform-glitch (original)
//  Created: 2026-04-25
//  Upgraded: 2026-05-02
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

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
  return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

// ── Domain-warped FBM ────────────────────────────────────────
fn dwfBm(p: vec2<f32>, time: f32) -> f32 {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, 0.0), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
  let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2) + time * 0.15, 3),
                    fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8) + time * 0.126, 3));
  return fbm(p + 4.0 * r, 4);
}

// ── Curl Noise (divergence-free) ─────────────────────────────
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
  let eps = 0.01;
  let n = valueNoise(p + time * 0.1);
  let nx = valueNoise(p + vec2<f32>(eps, 0.0) + time * 0.1);
  let ny = valueNoise(p + vec2<f32>(0.0, eps) + time * 0.1);
  let dy = (ny - n) / eps;
  let dx = (nx - n) / eps;
  return vec2<f32>(dy, -dx);
}

// ── Worley Noise (cellular) ──────────────────────────────────
fn worleyNoise(p: vec2<f32>, time: f32) -> f32 {
  let n = floor(p);
  let f = fract(p);
  var dist = 1.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let g = vec2<f32>(f32(x), f32(y));
      let o = hash22(n + g);
      let anim = sin(time * 0.5 + o * 6.2831) * 0.3 + 0.5;
      let r = g + o * anim - f;
      dist = min(dist, dot(r, r));
    }
  }
  return sqrt(dist);
}

// ── VHS Tracking with domain warping ─────────────────────────
fn vhsTracking(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
  let warp = dwfBm(vec2<f32>(uv.y * 8.0, time * 0.3), time);
  let jitter = sin(time * 30.0 + uv.y * 1000.0 + warp * 6.28) * intensity * 0.02;
  let roll = sin(time * 0.2 + warp * 3.14) * intensity * 0.005;
  return uv + vec2<f32>(jitter, roll);
}

// ── Block Corruption with Worley cells ───────────────────────
fn blockCorruption(uv: vec2<f32>, blockSize: f32, intensity: f32, time: f32) -> vec2<f32> {
  let blockId = floor(uv / blockSize);
  let cell = worleyNoise(blockId * 3.0 + vec2<f32>(time * 0.1, 7.31), time);
  let rnd = hash21(blockId + vec2<f32>(time * 0.05, 7.31));
  let sdf = smoothstep(0.0, 0.3, cell);
  let offset = (rnd - 0.5) * intensity * blockSize * (1.0 + sdf * 2.0);
  return uv + vec2<f32>(offset, 0.0);
}

// ── Datamoshing with curl noise ──────────────────────────────
fn datamoshDisp(uv: vec2<f32>, time: f32, smearScale: f32) -> vec2<f32> {
  let n = dwfBm(uv * 6.0 + time * 0.5, time);
  let curl = curlNoise(uv * 4.0 + time * 0.3, time);
  return uv + curl * n * smearScale * 0.08;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let uv = vec2<f32>(global_id.xy) / vec2<f32>(u.config.z, u.config.w);
  let time = u.config.x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let vhsJitter = u.zoom_params.x;
  let intensity = u.zoom_params.y;
  let smearScale = u.zoom_params.z;
  let flickerSpeed = 2.0 + u.zoom_params.w * 20.0;

  // Audio reactivity from plasmaBuffer
  let bass = plasmaBuffer[0].x;

  // Depth-aware scaling: more glitch in foreground
  let depthScale = mix(1.0, 0.3, depth);

  var warped = vhsTracking(uv, time, vhsJitter * depthScale);
  warped = blockCorruption(warped, 0.08, intensity * depthScale * (1.0 + bass), time);
  warped = datamoshDisp(warped, time, smearScale * depthScale);
  warped = clamp(warped, vec2<f32>(0.0), vec2<f32>(1.0));

  let glitchStrength = clamp(length(warped - uv) * 10.0, 0.0, 1.0);

  // Quantized scanline artifact
  let scanQ = floor(uv.y * 240.0) / 240.0;
  let quant = step(0.5, hash21(vec2<f32>(scanQ, floor(time * 8.0)))) * 0.06 * intensity;

  let cR = textureSampleLevel(readTexture, u_sampler, warped + vec2<f32>(0.003 * intensity + quant, 0.0), 0.0);
  let cG = textureSampleLevel(readTexture, u_sampler, warped, 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, warped - vec2<f32>(0.003 * intensity + quant, 0.0), 0.0);

  let flicker = 0.8 + 0.2 * fract(time * flickerSpeed);
  var col = vec3<f32>(cR.r, cG.g, cB.b) * flicker;

  // Digital bit-crush on luma
  let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
  let crush = floor(luma * 16.0 * (1.0 + intensity * 2.0)) / (16.0 * (1.0 + intensity * 2.0));
  col = mix(col, col * (crush / max(luma, 0.001)), glitchStrength * 0.4);

  let alpha = cG.a * (1.0 - glitchStrength * 0.5);

  textureStore(writeTexture, global_id.xy, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
