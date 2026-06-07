// ═══════════════════════════════════════════════════════════════════
//  Waveform Glitch
//  Category: retro-glitch
//  Features: glitch, waveform, retro, audio-sweep, rgb-tear, scanline, depth-jitter
//  Complexity: Medium
//  Updated: 2026-05-31
//  By: Grok (visual flourish — richer scanline motion, audio-reactive tearing, atmospheric jitter)
// ═══════════════════════════════════════════════════════════════════
//  Upgraded: 2026-05-30
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < octaves; i = i + 1) { s = s + a * valueNoise(p * f); f = f * 2.0; a = a * 0.5; }
  return s;
}

fn dwfBm(p: vec2<f32>, time: f32) -> f32 {
  let q = vec2(fbm(p + vec2(0.0, 0.0), 3), fbm(p + vec2(5.2, 1.3), 3));
  let r = vec2(fbm(p + 4.0 * q + vec2(1.7, 9.2) + time * 0.15, 3), fbm(p + 4.0 * q + vec2(8.3, 2.8) + time * 0.126, 3));
  return fbm(p + 4.0 * r, 4);
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
  let e = 0.01;
  let n = valueNoise(p + time * 0.1);
  let nx = valueNoise(p + vec2(e, 0.0) + time * 0.1);
  let ny = valueNoise(p + vec2(0.0, e) + time * 0.1);
  return vec2((ny - n) / e, -(nx - n) / e);
}

fn worleyNoise(p: vec2<f32>, time: f32) -> f32 {
  let n = floor(p);
  let f = fract(p);
  var d = 1.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let g = vec2(f32(x), f32(y));
      let o = hash22(n + g);
      d = min(d, dot(g + o * (sin(time * 0.5 + o * 6.2831) * 0.3 + 0.5) - f, g + o * (sin(time * 0.5 + o * 6.2831) * 0.3 + 0.5) - f));
    }
  }
  return sqrt(d);
}

// ── Structure Tensor / Optical Flow ──────────────────────────
fn sampleLuma(uv: vec2<f32>) -> f32 {
  return dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, vec3(0.2126, 0.7152, 0.0722));
}

fn opticalFlow(uv: vec2<f32>, dt: f32, res: vec2<f32>) -> vec2<f32> {
  let px = 1.0 / res;
  let l = sampleLuma(uv);
  let lx = sampleLuma(uv + vec2(px.x, 0.0)) - l;
  let ly = sampleLuma(uv + vec2(0.0, px.y)) - l;
  let lt = l - sampleLuma(uv - dt * 0.01);
  return -vec2(lx * lt, ly * lt) / (lx * lx + ly * ly + 0.0001);
}

// ── Bayer Dither ─────────────────────────────────────────────
fn bayer4x4(p: vec2<i32>) -> f32 {
  let m = array<i32, 16>(0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
  return f32(m[(p.x & 3) + ((p.y & 3) << 2)]) / 16.0 - 0.5;
}

// ── Harmonic Oscillators ─────────────────────────────────────
fn coupledHarmonics(uv: vec2<f32>, time: f32, p1: f32, p2: f32) -> f32 {
  let w1 = sin(uv.x * 12.0 + time * 2.1 + p1 * 6.28) * cos(uv.y * 8.0 - time * 1.3);
  let w2 = sin(uv.x * 7.0 - time * 1.7 + p2 * 6.28) * cos(uv.y * 15.0 + time * 2.5);
  return w1 * w2 * 0.5 + 0.5;
}

// ── VHS & Glitch ─────────────────────────────────────────────
fn vhsTracking(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
  let warp = dwfBm(vec2(uv.y * 8.0, time * 0.3), time);
  return uv + vec2(sin(time * 30.0 + uv.y * 1000.0 + warp * 6.28) * intensity * 0.02,
                   sin(time * 0.2 + warp * 3.14) * intensity * 0.005);
}

fn blockCorruption(uv: vec2<f32>, blockSize: f32, intensity: f32, time: f32) -> vec2<f32> {
  let blockId = floor(uv / blockSize);
  let cell = worleyNoise(blockId * 3.0 + vec2(time * 0.1, 7.31), time);
  let rnd = hash21(blockId + vec2(time * 0.05, 7.31));
  return uv + vec2((rnd - 0.5) * intensity * blockSize * (1.0 + smoothstep(0.0, 0.3, cell) * 2.0), 0.0);
}

fn datamoshDisp(uv: vec2<f32>, time: f32, smearScale: f32, flow: vec2<f32>) -> vec2<f32> {
  return uv + curlNoise(uv * 4.0 + time * 0.3, time) * dwfBm(uv * 6.0 + time * 0.5, time) * smearScale * 0.08 + flow * smearScale * 0.5;
}

// ── Spectral & Grain ─────────────────────────────────────────
fn wavelengthToRGB(w: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(vec3(w, w + 2.09, w + 4.18));
}

fn filmGrain(uv: vec2<f32>, time: f32) -> f32 {
  return (hash21(uv * 137.0 + floor(time * 24.0)) - 0.5) * 0.06;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let uv = vec2<f32>(global_id.xy) / u.config.zw;
  let time = u.config.x;
  let res = u.config.zw;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let waveIntensity = u.zoom_params.x * (1.0 + bass * 0.8);
  let vhsIntensity = u.zoom_params.y * (1.0 + mids * 0.5);
  let blockGlitchSize = mix(0.02, 0.16, u.zoom_params.z);
  let shadowMaskAmount = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let mouseVel = vec2(u.zoom_config.x - fract(u.zoom_config.x * 0.97), 0.0);
  let mouseZone = exp(-length(uv - mousePos) * 6.0) * (1.0 + u.zoom_config.w);

  let frameIdx = u32(floor(time * 60.0)) % 4u;
  extraBuffer[frameIdx] = bass;
  let transient = max(bass - extraBuffer[(frameIdx + 3u) % 4u], 0.0) * 4.0;

  let depthScale = mix(1.0, 0.3, depth);
  let glitchAmt = vhsIntensity * depthScale * (1.0 + mouseZone * 2.0 + transient * 3.0);

  let flow = opticalFlow(uv, 0.016, res);
  let flowMag = length(flow);

  if (glitchAmt < 0.02 && flowMag < 0.005 && transient < 0.05) {
    let pristine = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    textureStore(writeTexture, global_id.xy, vec4(pristine, 0.0));
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
    return;
  }

  var warped = vhsTracking(uv, time, glitchAmt);
  warped = blockCorruption(warped, blockGlitchSize, glitchAmt, time);
  warped = datamoshDisp(warped, time, waveIntensity * depthScale, flow + mouseVel);
  warped = clamp(warped, vec2(0.0), vec2(1.0));

  let glitchMag = length(warped - uv);
  let blockCorrup = smoothstep(0.0, blockGlitchSize, glitchMag);

  let prevFrame = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let persist = mix(prevFrame.rgb * vec3(exp(-0.016 * 12.0), exp(-0.016 * 8.0), exp(-0.016 * 5.0)), vec3(0.0), 0.85);

  let scanQ = floor(uv.y * 240.0) / 240.0;
  let quant = step(0.5, hash21(vec2(scanQ, floor(time * 8.0)))) * 0.06 * vhsIntensity;

  let displacedUV = clamp(warped + vec2(quant, 0.0), vec2(0.0), vec2(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  let edge = abs(flow.x) + abs(flow.y);
  let bleedR = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2(edge * 0.008, 0.0), 0.0).r;
  let bleedB = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2(edge * 0.008, 0.0), 0.0).b;
  var col = vec3(mix(baseColor.r, bleedR, glitchMag * 0.5), baseColor.g, mix(baseColor.b, bleedB, glitchMag * 0.5));

  let inBand = step(0.92, uv.y);
  let bandNoise = hash21(vec2(uv.x * 100.0, time * 30.0)) * inBand * vhsIntensity * (0.3 + treble * 0.4);
  let flicker = 0.8 + 0.2 * fract(time * 2.0 + bandNoise * 10.0);
  col = col * flicker;

  let luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
  let crush = floor(luma * 16.0 * (1.0 + vhsIntensity * 2.0)) / (16.0 * (1.0 + vhsIntensity * 2.0));
  col = mix(col, col * (crush / max(luma, 0.001)), glitchMag * 1.6);

  let shadowMask = 0.85 + 0.15 * step(0.33, fract(uv.x * res.x / 3.0));
  col = col * mix(1.0, shadowMask, shadowMaskAmount);
  col = col + vec3(bandNoise * 0.5, bandNoise * 0.3, bandNoise * 0.1);

  let harm = coupledHarmonics(uv, time, u.zoom_params.x, u.zoom_params.y);
  col = mix(col, col * wavelengthToRGB(time * 0.4 + harm * 3.14), glitchMag * 0.3);
  col = mix(col, persist, 0.12);

  let bloom = max(luma - 0.6, 0.0) * 0.4;
  col = col + vec3(bloom * 1.1, bloom * 0.7, bloom * 0.5);
  col = col + filmGrain(uv, time);
  col = col + bayer4x4(vec2<i32>(global_id.xy)) * 0.015;

  let spectralTint = wavelengthToRGB(time * 0.4 + glitchMag * 20.0);
  col = mix(col, col * spectralTint, glitchMag * 2.0);

  let alpha = clamp(glitchMag * 5.0 * blockCorrup * (1.0 + transient) * (1.0 + mouseZone), 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4(col, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
