// ═══════════════════════════════════════════════════════════════════
//  Signal Noise
//  Category: retro-glitch
//  Features: temporal
//  Complexity: High
//  Created: 2026-04-25
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
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}
fn hash11(p: f32) -> f32 {
  return fract(sin(p * 12.9898) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
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

// ── Color Utilities ──────────────────────────────────────────
fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
  let y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
  let u = -0.14713 * rgb.r - 0.28886 * rgb.g + 0.436 * rgb.b;
  let v = 0.615 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b;
  return vec3<f32>(y, u, v);
}
fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
  let r = yuv.x + 1.13983 * yuv.z;
  let g = yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z;
  let b = yuv.x + 2.03211 * yuv.y;
  return vec3<f32>(r, g, b);
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let c = hsv.z * hsv.y;
  let h = hsv.x * 6.0;
  let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else              { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(hsv.z - c);
}

// ── VHS & Artifact Functions ─────────────────────────────────
fn vhsHeadSwitch(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
  let bandPos = 0.92 + 0.02 * sin(time * 2.5);
  let inBand = smoothstep(bandPos - 0.03, bandPos, uv.y) *
               smoothstep(bandPos + 0.08, bandPos + 0.03, uv.y);
  let lineNoise = hash11(floor(uv.x * 80.0) + time * 25.0) * 2.0 - 1.0;
  return lineNoise * intensity * inBand;
}
fn dctBlockArtifact(uv: vec2<f32>, blockSize: f32, intensity: f32, time: f32) -> vec3<f32> {
  let blockId = floor(uv / blockSize);
  let localUV = fract(uv / blockSize);
  let checker = fract(blockId.x + blockId.y) * 2.0 - 1.0;
  let ring = sin(localUV.x * 3.14159 * 8.0) * sin(localUV.y * 3.14159 * 8.0);
  let rnd = hash21(blockId + vec2<f32>(time * 0.2, 5.91));
  let artifact = (ring * 0.7 + checker * 0.3) * rnd * intensity;
  return vec3<f32>(artifact);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let uv = vec2<f32>(global_id.xy) / vec2<f32>(u.config.z, u.config.w);
  let time = u.config.x;

  let vhsIntensity = u.zoom_params.x;
  let artifactStrength = u.zoom_params.y;
  let smearAmount = u.zoom_params.z;
  let chromaStrength = u.zoom_params.w;

  let noise = fbm(uv * 8.0 + time * 1.5, 4);
  let vhsNoise = vhsHeadSwitch(uv, time, vhsIntensity);
  let blockArtifact = dctBlockArtifact(uv, 0.06, artifactStrength, time);

  let noiseDir = fbm(uv * 4.0 + time * 0.7, 3) * 6.28318;
  let offR = vec2<f32>(cos(noiseDir), sin(noiseDir)) * chromaStrength * 0.02;
  let offG = vec2<f32>(cos(noiseDir + 2.094), sin(noiseDir + 2.094)) * chromaStrength * 0.02;
  let offB = vec2<f32>(cos(noiseDir + 4.189), sin(noiseDir + 4.189)) * chromaStrength * 0.02;

  let cR = textureSampleLevel(readTexture, u_sampler, uv + offR, 0.0);
  let cG = textureSampleLevel(readTexture, u_sampler, uv + offG, 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, uv + offB, 0.0);

  var col = vec3<f32>(cR.r, cG.g, cB.b);

  let smearVec = vec2<f32>(
    fbm(uv * 6.0 + vec2<f32>(time, 0.0), 3),
    fbm(uv * 6.0 + vec2<f32>(0.0, time), 3)
  ) * 2.0 - 1.0;
  let smearUV = uv + smearVec * smearAmount * 0.03;
  let smearCol = textureSampleLevel(readTexture, u_sampler,
    clamp(smearUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  col = mix(col, smearCol.rgb, smearAmount * 0.5);

  var yuv = rgbToYuv(col);
  yuv.y = yuv.y + (noise - 0.5) * vhsIntensity * 0.3 + blockArtifact.r;
  yuv.z = yuv.z + (vhsNoise - 0.5) * vhsIntensity * 0.3 + blockArtifact.g;
  col = yuvToRgb(yuv);

  let noiseIntensity = clamp(noise + abs(vhsNoise) + length(blockArtifact), 0.0, 1.0);
  let alpha = cG.a * (1.0 - noiseIntensity * 0.4);

  textureStore(writeTexture, global_id.xy, vec4<f32>(col, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
