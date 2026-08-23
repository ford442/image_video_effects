// ═══════════════════════════════════════════════════════════════════
//  Signal Noise
//  Category: retro-glitch
//  Features: temporal, audio-reactive
//  Complexity: High
//  Upgraded: 2026-08-21 (Batch 42 - Glitch audio & temporal upgrades)
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
  for (var i = 0; i < 6; i = i + 1) {
    if (i >= octaves) { break; }
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

// ── Color Utilities ──────────────────────────────────────────
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

// ── VHS & Artifact Functions ─────────────────────────────────
fn vhsHeadSwitch(uv: vec2<f32>, time: f32, intensity: f32, bass: f32) -> f32 {
  let bandPos = 0.92 + 0.02 * sin(time * 2.5) - bass * 0.1;
  let inBand = smoothstep(bandPos - 0.03, bandPos, uv.y) *
               smoothstep(bandPos + 0.08, bandPos + 0.03, uv.y);
  let lineNoise = hash11(floor(uv.x * 80.0) + time * 25.0) * 2.0 - 1.0;
  return lineNoise * intensity * inBand * (1.0 + bass * 2.0);
}

fn dctBlockArtifact(uv: vec2<f32>, blockSize: f32, intensity: f32, time: f32, mids: f32) -> vec3<f32> {
  let blockId = floor(uv / blockSize);
  let localUV = fract(uv / blockSize);
  let checker = fract(blockId.x + blockId.y) * 2.0 - 1.0;
  let ring = sin(localUV.x * 3.14159 * 8.0) * sin(localUV.y * 3.14159 * 8.0);
  let rnd = hash21(blockId + vec2<f32>(time * 0.2, 5.91));
  let artifact = (ring * 0.7 + checker * 0.3) * rnd * intensity * (1.0 + mids);
  return vec3<f32>(artifact);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = vec2<f32>(u.config.z, u.config.w);
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let vhsIntensity = u.zoom_params.x * (1.0 + bass * 0.5);
  let artifactStrength = u.zoom_params.y * (1.0 + mids * 0.5);
  let smearAmount = u.zoom_params.z;
  let chromaStrength = u.zoom_params.w + treble * 0.1;

  let noise = fbm(uv * 8.0 + time * 1.5, 4);
  let vhsNoise = vhsHeadSwitch(uv, time, vhsIntensity, bass);
  let blockArtifact = dctBlockArtifact(uv, 0.06, artifactStrength, time, mids);

  let noiseDir = fbm(uv * 4.0 + time * 0.7, 3) * 6.28318;
  
  // Audio-reactive glitch displacement based on high treble
  let glitchDisp = step(0.9, hash21(vec2<f32>(uv.y * 10.0, time))) * treble * 0.1;
  let uvGlitch = uv + vec2<f32>(glitchDisp, 0.0);

  let offR = vec2<f32>(cos(noiseDir), sin(noiseDir)) * chromaStrength * 0.02;
  let offG = vec2<f32>(cos(noiseDir + 2.094), sin(noiseDir + 2.094)) * chromaStrength * 0.02;
  let offB = vec2<f32>(cos(noiseDir + 4.189), sin(noiseDir + 4.189)) * chromaStrength * 0.02;

  let cR = textureSampleLevel(readTexture, u_sampler, uvGlitch + offR, 0.0);
  let cG = textureSampleLevel(readTexture, u_sampler, uvGlitch + offG, 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, uvGlitch + offB, 0.0);

  var col = vec3<f32>(cR.r, cG.g, cB.b);

  let smearVec = vec2<f32>(
    fbm(uvGlitch * 6.0 + vec2<f32>(time, 0.0), 3),
    fbm(uvGlitch * 6.0 + vec2<f32>(0.0, time), 3)
  ) * 2.0 - 1.0;
  let smearUV = clamp(uvGlitch + smearVec * smearAmount * 0.03, vec2<f32>(0.0), vec2<f32>(1.0));
  let smearCol = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
  col = mix(col, smearCol.rgb, smearAmount * 0.5);

  var yuv = rgbToYuv(col);
  yuv.y = yuv.y + (noise - 0.5) * vhsIntensity * 0.3 + blockArtifact.r;
  yuv.z = yuv.z + (vhsNoise - 0.5) * vhsIntensity * 0.3 + blockArtifact.g;
  col = yuvToRgb(yuv);

  // Audio-reactive CRT scanlines overlay
  let scanline = sin(uv.y * resolution.y * 3.14159) * 0.05 * mids;
  col = col - scanline;

  // Temporal blending (phosphor decay)
  let prevFrame = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  let temporalDecay = mix(0.1, 0.8, smearAmount);
  col = mix(col, prevFrame, temporalDecay);

  let noiseIntensity = clamp(noise + abs(vhsNoise) + length(blockArtifact) + glitchDisp, 0.0, 1.0);
  let alpha = cG.a * (1.0 - noiseIntensity * 0.4);

  textureStore(writeTexture, global_id.xy, vec4<f32>(col, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(col, alpha)); // Save for temporal next frame

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
