// ═══════════════════════════════════════════════════════════════════
//  Liquid Glitch
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-07-21
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
struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(gid.xy); let uv = vec2<f32>(gid.xy) / resolution; let time = u.config.x;
  let blockPixels = mix(6.0, 42.0, u.zoom_params.x);
  let corruption = u.zoom_params.y; let burstStrength = u.zoom_params.z; let chromaShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let blockSize = vec2<f32>(blockPixels) / resolution;
  let block = floor(uv / blockSize); let blockUV = (block + 0.5) * blockSize;
  let blockRand = hash21(block + floor(time * (5.0 + audio.z * 12.0)));
  let rowRand = hash21(vec2<f32>(block.y, floor(time * 7.0)));
  var offset = vec2<f32>((blockRand - 0.5) * corruption * 0.035, sin(block.x + time * 3.0) * corruption * 0.002);
  let badSignal = step(0.88 - corruption * 0.15 - audio.z * 0.12, rowRand);
  offset.x += (rowRand - 0.5) * badSignal * (0.03 + corruption * 0.12);

  let aspect = resolution.x / max(resolution.y, 1.0);
  var burstMask = 0.0; let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age > 0.0 && age < 1.4) {
      let delta = (blockUV - ripple.xy) * vec2<f32>(aspect, 1.0); let dist = max(length(delta), 0.0001);
      let ring = step(0.55, sin(dist * 70.0 - age * 18.0));
      let envelope = (1.0 - smoothstep(0.0, 1.4, age)) * exp(-dist * 5.0);
      let dir = delta / dist; let shard = (hash21(block + f32(i)) - 0.5) * 2.0;
      offset += vec2<f32>(dir.x / aspect, dir.y) * ring * envelope * shard * burstStrength * 0.055;
      burstMask += ring * envelope;
    }
  }

  let smear = vec2<f32>(offset.x * (1.0 + audio.x * 0.7), offset.y);
  let split = vec2<f32>(0.003 + chromaShift * 0.018 + audio.y * 0.005, 0.0);
  let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(uv + smear + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sampleG = textureSampleLevel(readTexture, u_sampler, clamp(uv + smear, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(uv + smear - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let historyUV = clamp(uv - smear * 0.45, vec2<f32>(0.0), vec2<f32>(1.0));
  let history = textureSampleLevel(dataTextureC, non_filtering_sampler, historyUV, 0.0);
  let scanline = 0.88 + 0.12 * sin(f32(gid.y) * 3.14159 + time * (8.0 + audio.z * 10.0));
  let digitalTint = vec3<f32>(0.08, 0.0, 0.14) * blockRand * (corruption + audio.y);
  let current = vec3<f32>(sampleR.r, sampleG.g, sampleB.b) * scanline + digitalTint;
  let persistence = clamp(0.12 + corruption * 0.4 - burstMask * 0.12, 0.05, 0.55) * history.a;
  let rgb = mix(current, history.rgb, persistence);
  let sourceAlpha = max(sampleR.a, max(sampleG.a, sampleB.a));
  let energy = clamp(length(smear) * 18.0 + burstMask * 0.35 + badSignal * 0.2, 0.0, 1.0);
  let alpha = clamp(sourceAlpha * (0.72 + (1.0 - corruption) * 0.2) + energy * 0.25, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);
  textureStore(writeTexture, coord, outputColor); textureStore(dataTextureA, coord, outputColor);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + smear, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
