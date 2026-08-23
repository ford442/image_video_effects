// ═══════════════════════════════════════════════════════════════════
//  Quantum Smear — Batch 58C
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: High
//  Upgraded: 2026-08-23
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

fn hash2(p: vec2<f32>) -> vec2<f32> {
  var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  p2 = fract(sin(p2) * 43758.5453);
  return p2 * 2.0 - 1.0;
}

fn hash1(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn calculateMotion(current: vec3<f32>, previous: vec3<f32>) -> f32 {
  return length(current - previous) * 2.0;
}

fn stochasticAdvect(uv: vec2<f32>, entropy: f32, depth: f32, baseRadius: f32, entropyScale: f32, time: f32) -> vec2<f32> {
  let radius = mix(0.005, baseRadius, depth);
  let noise = hash2(uv * 100.0 + vec2<f32>(time * 0.3, time * 0.7));
  let scale = 1.0 + entropy * entropyScale;
  return uv + noise * radius * scale;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  let scatterRadius = u.zoom_params.x * 0.15 + 0.01;
  let entropyScale = u.zoom_params.y * 8.0 + 2.0;
  let coherenceStr = u.zoom_params.z * 0.15 + 0.03;
  let densityBoost = u.zoom_params.w * 3.0 + 1.0;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let band = plasmaBuffer[(u32(hash1(uv) * 8.0) % 8u) + 1u].x;

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseWell = (1.0 - smoothstep(0.0, 0.35, mouseDist)) * (0.35 + held * 0.45);
  let voidStrength = 0.15 + treble * 0.15 + (1.0 - mouseWell) * 0.1;
  let foamIntensity = 0.2 + bass * 0.2;
  let shimmerAmt = 0.02 + mids * 0.03;
  let depthMod = 0.5 + mouseWell * 0.35;

  let videoSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let prevFeedback = textureLoad(dataTextureC, pixel, 0).rgb;

  let motion = calculateMotion(videoSample.rgb, prevFeedback);
  let packet = sin(time * (2.0 + band * 4.0) + depth * 12.0) * 0.5 + 0.5;

  let advectedUV = stochasticAdvect(uv, motion + packet * 0.15, depth * depthMod, scatterRadius, entropyScale, time);
  let advectedSample = textureSampleLevel(readTexture, u_sampler, clamp(advectedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

  let coherence = coherenceStr + depth * 0.1 + mouseWell * 0.25;
  var result = mix(advectedSample, videoSample.rgb, coherence);
  result = result + vec3<f32>(motion * 0.3);

  let foamNoise = hash2(uv * 50.0 + vec2<f32>(time, time * 1.3));
  let foamScale = (1.0 - depth) * foamIntensity;
  result = result + vec3<f32>(foamNoise.x, foamNoise.y, (foamNoise.x + foamNoise.y) * 0.5) * foamScale;

  let density = 1.0 + motion * densityBoost;
  result = result * density;

  let voidPotential = max(0.0, 0.1 - motion) * voidStrength;
  let voidNoise = hash1(uv * 20.0 + vec2<f32>(time * 0.5, 0.0));
  let voidHit = select(0.0, 1.0, voidPotential > 0.01 && voidNoise > (0.95 - voidStrength * 0.3));
  result = result - vec3<f32>(voidPotential * 2.0) * voidHit;

  let shimmer = sin(time * 10.0 + uv.x * 20.0) * cos(time * 7.0 + uv.y * 15.0) * shimmerAmt;
  result = result * (1.0 + shimmer);

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = max(time - ripple.z, 0.0);
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    clickBurst += exp(-age * 2.2) * smoothstep(0.25, 0.0, rDist);
  }
  result = mix(result, videoSample.rgb, clickBurst * 0.35);

  let blurAmount = depth * depthMod * 0.3;
  let luminance = dot(result, vec3<f32>(0.299, 0.587, 0.114));
  result = mix(result, vec3<f32>(luminance), blurAmount);

  let alpha = clamp(0.35 + luminance * 0.45 + motion * 0.2 + mouseWell * 0.1, 0.1, 1.0);
  let finalPixel = vec4<f32>(result, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalPixel);
}
