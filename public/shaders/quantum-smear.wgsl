// ═══════════════════════════════════════════════════════════════════
//  Quantum Smear
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: High
//  Upgraded: 2026-08-23, 2026-11-01
//  Ideas: still-lock; void rim
//  A packing: clamped pre-ACES smear RGB (motion history). ACES on writeTexture only.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
  // ── Idea 1: still-lock ─────────────────────────────────────────
  // Scatter collapses where this frame matches the last smear, so
  // quiet pixels stop boiling. Intensity still sets the radius.
  let still = smoothstep(0.02, 0.18, motion);
  let lockedUV = mix(uv, advectedUV, still);
  let advectedSample = textureSampleLevel(readTexture, u_sampler, clamp(lockedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

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
  // ── Idea 2: void rim ───────────────────────────────────────────
  // The hole still subtracts. A thin lip around a weak void piles
  // the photo back up. Detail still scales density above.
  let lip = smoothstep(0.0, 0.04, voidPotential) * (1.0 - smoothstep(0.04, 0.10, voidPotential));
  result = result + videoSample.rgb * lip * 0.35;

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

  let alpha = clamp(0.35 + luminance * 0.45 + motion * 0.2 + mouseWell * 0.1 + lip * 0.12 + still * 0.08, 0.1, 1.0);
  let stored = vec4<f32>(clamp(result, vec3<f32>(0.0), vec3<f32>(4.0)), alpha);
  let display = vec4<f32>(acesToneMap(max(result, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, pixel, display);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, stored);
}
