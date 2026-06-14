// ═══ Waveform Glitch ═══════════════════════════════════════════════
//  Category: retro-glitch
//  Features: glitch, waveform, retro, rgb-tear, scanline, depth-jitter,
//            clifford-attractor, domain-warped-fbm, curl-flow,
//            voronoi-ridge-corruption, yuv-chroma-noise, aces-tone-map,
//            chromatic-aberration, temporal-feedback
//  Complexity: Medium
//  Updated: 2026-06-14
//  By: Algorithmist — Clifford strange attractor, domain-warped FBM,
//      divergence-free curl flow, Voronoi F2-F1 ridges, YUV chroma noise

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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash & Noise ──────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0; var amp = 0.5; var freq = 1.0;
  for (var i = 0; i < octaves; i++) { sum += amp * valueNoise(p * freq); freq *= 2.0; amp *= 0.5; }
  return sum;
}

fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
  return p + strength * q;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.001;
  let nx = fbm(p + vec2<f32>(0.0, eps), 4) - fbm(p - vec2<f32>(0.0, eps), 4);
  let ny = fbm(p + vec2<f32>(eps, 0.0), 4) - fbm(p - vec2<f32>(eps, 0.0), 4);
  return vec2<f32>(nx, -ny) / (2.0 * eps);
}

fn voronoiRidge(p: vec2<f32>) -> f32 {
  var F1 = 1e9; var F2 = 1e9; let ip = floor(p);
  for (var i = -2; i <= 2; i++) {
    for (var j = -2; j <= 2; j++) {
      let n = ip + vec2<f32>(f32(i), f32(j));
      let d = length(p - n - hash21(n));
      if (d < F1) { F2 = F1; F1 = d; } else if (d < F2) { F2 = d; }
    }
  }
  return F2 - F1;
}

// ── Color & Tone ──────────────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn wavelengthToRGB(w: f32) -> vec3<f32> { return 0.5 + 0.5 * cos(vec3<f32>(w, w + 2.09, w + 4.18)); }

fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b,
                  -0.14713 * rgb.r - 0.28886 * rgb.g + 0.436 * rgb.b,
                   0.615 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b);
}

fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(yuv.x + 1.13983 * yuv.z,
                   yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z,
                   yuv.x + 2.03211 * yuv.y);
}

// ── VHS & Glitch ──────────────────────────────────────────────────
fn vhsTracking(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
  let warp = fbm(vec2<f32>(uv.y * 8.0, time * 0.3), 3);
  return uv + vec2<f32>(sin(time * 30.0 + uv.y * 1000.0 + warp * TAU) * intensity * 0.02,
                        sin(time * 0.2 + warp * PI) * intensity * 0.005);
}

fn blockCorruption(uv: vec2<f32>, blockSize: f32, intensity: f32, time: f32) -> vec2<f32> {
  let blockId = floor(uv / blockSize);
  let ridge = voronoiRidge(blockId * 3.0 + vec2<f32>(time * 0.1, 7.31));
  let rnd = hash21(blockId + vec2<f32>(time * 0.05, 7.31));
  return uv + vec2<f32>((rnd - 0.5) * intensity * blockSize * (1.0 + smoothstep(0.0, 0.3, ridge) * 2.0), 0.0);
}

fn filmGrain(uv: vec2<f32>, time: f32) -> f32 { return (hash21(uv * 137.0 + floor(time * 24.0)) - 0.5) * 0.06; }

fn bayer4x4(p: vec2<i32>) -> f32 {
  let m = array<i32, 16>(0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
  return f32(m[(p.x & 3) + ((p.y & 3) << 2)]) / 16.0 - 0.5;
}

// ── Strange Attractor ─────────────────────────────────────────────
fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
  return vec2<f32>(sin(a * p.y) + c * cos(a * p.x), sin(b * p.x) + d * cos(b * p.y));
}

// ── Main ──────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let p1 = u.zoom_params.x; let p2 = u.zoom_params.y; let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;

  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let waveIntensity = p1 * (1.0 + bass * 0.8);
  let vhsIntensity = p2 * (1.0 + mids * 0.5);
  let blockSize = mix(0.02, 0.16, p3);
  let shadowMaskAmount = p4;

  let mousePos = u.zoom_config.yz;
  let mouseZone = exp(-length(uv - mousePos) * 6.0) * (1.0 + u.zoom_config.w);

  let frameIdx = u32(floor(time * 60.0)) % 4u;
  extraBuffer[frameIdx] = bass;
  let transient = max(bass - extraBuffer[(frameIdx + 3u) % 4u], 0.0) * 4.0;

  let depthScale = mix(1.0, 0.3, depth);
  let glitchAmt = vhsIntensity * depthScale * (1.0 + mouseZone * 2.0 + transient * 3.0);

  let chaotic = clifford(uv * TAU + time * 0.1, 1.7 + bass * 0.3, -0.7, 1.4, 1.6);
  let attractorWarp = chaotic * glitchAmt * 0.015;

  var warped = vhsTracking(uv, time, glitchAmt) + attractorWarp;
  warped = domainWarp(warped, glitchAmt * 0.04, 3);
  warped = blockCorruption(warped, blockSize, glitchAmt, time);
  let flow = curl2D(uv * 4.0 + time * 0.3, time);
  warped = clamp(warped + flow * waveIntensity * depthScale * 0.05, vec2<f32>(0.0), vec2<f32>(1.0));

  let glitchMag = length(warped - uv);
  let blockCorrup = smoothstep(0.0, blockSize, glitchMag);

  let scanQ = floor(uv.y * 240.0) / 240.0;
  let quant = step(0.5, hash21(vec2<f32>(scanQ, floor(time * 8.0)))) * 0.06 * vhsIntensity;
  let displacedUV = clamp(warped + vec2<f32>(quant, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let caAmt = 0.003 * (1.0 + bass) + glitchMag * 0.01;
  let r = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2<f32>(caAmt, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2<f32>(caAmt * 0.6, 0.0), 0.0).b;
  var col = vec3<f32>(r, g, b);

  let yuv = rgbToYuv(col);
  let chromaNoise = hash21(uv * 200.0 + time * 10.0) - 0.5;
  let chromaShift = yuv + vec3<f32>(0.0, chromaNoise * vhsIntensity * 0.2, chromaNoise * vhsIntensity * 0.15);
  col = mix(col, yuvToRgb(chromaShift), glitchMag * 2.0);

  let inBand = step(0.92, uv.y);
  let bandNoise = hash21(vec2<f32>(uv.x * 100.0, time * 30.0)) * inBand * vhsIntensity * (0.3 + treble * 0.4);
  let flicker = 0.8 + 0.2 * fract(time * 2.0 + bandNoise * 10.0);
  col = col * flicker;

  let lum = luma(col);
  let crush = floor(lum * 16.0 * (1.0 + vhsIntensity * 2.0)) / (16.0 * (1.0 + vhsIntensity * 2.0));
  col = mix(col, col * (crush / max(lum, 0.001)), glitchMag * 1.6);

  let shadowMask = 0.85 + 0.15 * step(0.33, fract(uv.x * res.x / 3.0));
  col = col * mix(1.0, shadowMask, shadowMaskAmount);
  col = col + vec3<f32>(bandNoise * 0.5, bandNoise * 0.3, bandNoise * 0.1);

  let spectralTint = wavelengthToRGB(time * 0.4 + glitchMag * 20.0 + clifford(uv * PI, 1.5, -1.8, 1.2, -1.5).x);
  col = mix(col, col * spectralTint, glitchMag * 0.5);

  let decay = 0.94;
  let trail = mix(prev.rgb * decay, col, 0.2 + bass * 0.1);
  textureStore(dataTextureA, pixel, vec4<f32>(trail, prev.a));

  let bloom = max(lum - 0.6, 0.0) * 0.4;
  col = col + vec3<f32>(bloom * 1.1, bloom * 0.7, bloom * 0.5);
  col = col + filmGrain(uv, time);
  col = col + bayer4x4(pixel) * 0.015;

  col = acesToneMap(col * (0.9 + mids * 0.2));

  let alpha = clamp(glitchMag * 5.0 * blockCorrup * (1.0 + transient) * (1.0 + mouseZone), 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
