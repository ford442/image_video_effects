// ═══════════════════════════════════════════════════════════════════
//  Quantum Cursor
//  Category: interactive-mouse
//  Features: mouse-driven, distortion, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  Upgraded: 2026-07-31 (spring-damper field center, click decoherence
//            bursts, per-block FFT voices)
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=BlockSize, z=Aberration, w=Chaos
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3  = fract(vec3<f32>(p.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// extraBuffer persistent state map ([0..4] reserved, [5..132] engine FFT):
//   [133] = spring center X   [134] = spring center Y
//   [135] = spring velocity X [136] = spring velocity Y
//   [137] = previous frame time (for dt)
//   [138] = initialized flag (0.0 -> snap to mouse on first frame)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 0.001);
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // ── Priority 1: critically-damped spring for the field center ──
  // The quantized zone trails the cursor instead of snapping to it.
  if (global_id.x == 0u && global_id.y == 0u) {
    let now = u.config.x;
    let dt = clamp(now - extraBuffer[137], 0.0, 0.1);
    var px = extraBuffer[133];
    var py = extraBuffer[134];
    var vx = extraBuffer[135];
    var vy = extraBuffer[136];
    if (extraBuffer[138] < 0.5) {
      px = rawMouse.x;
      py = rawMouse.y;
      vx = 0.0;
      vy = 0.0;
      extraBuffer[138] = 1.0;
    }
    let omega = 14.0;  // spring stiffness: snappy but visibly trailing
    let accelX = omega * omega * (rawMouse.x - px) - 2.0 * omega * vx;
    let accelY = omega * omega * (rawMouse.y - py) - 2.0 * omega * vy;
    vx = vx + accelX * dt;
    vy = vy + accelY * dt;
    px = px + vx * dt;
    py = py + vy * dt;
    extraBuffer[133] = px;
    extraBuffer[134] = py;
    extraBuffer[135] = vx;
    extraBuffer[136] = vy;
    extraBuffer[137] = now;
  }
  let mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params with guards and audio reactivity
  let radius = max(mix(0.05, 0.5, u.zoom_params.x) * (1.0 + bass * 0.3 + held * 0.15), 0.001);
  let mosaic_scale = mix(50.0, 5.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let aberration = clamp(u.zoom_params.z, 0.0, 1.0) * 0.05;
  var chaos = clamp(u.zoom_params.w * (1.0 + bass * 0.5 + mids * 0.2), 0.0, 1.0);

  let dist_vec = (uv - mouse);
  let dist = length(dist_vec * vec2(aspect, 1.0));

  // Soft edge for the effect
  let mask = smoothstep(radius, radius * 0.8, dist);

  // ── Priority 2: click decoherence bursts ──
  // Each live ripple spikes chaos locally at its click point: a decaying
  // +0.5 chaos bump in a ~0.3 radius smoothstep falloff with a ~1.2s fade,
  // plus an expanding decoherence ring for visual feedback.
  var clickChaos = 0.0;
  var ringGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = u.config.x - ripple.z;
    if (age > 0.0 && age < 1.2) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let fade = 1.0 - age / 1.2;
      clickChaos = clickChaos + 0.5 * smoothstep(0.3, 0.0, rDist) * fade;
      let ringRadius = age * 0.35;
      let ringBand = smoothstep(0.04, 0.0, abs(rDist - ringRadius));
      ringGlow = ringGlow + ringBand * fade;
    }
  }
  chaos = clamp(chaos + clickChaos, 0.0, 1.0);

  // Sample Original
  let colOrig = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Sample Effect
  let blocks = resolution / max(mosaic_scale, 0.1);
  let blockUV = floor(uv * blocks) / blocks + (0.5 / blocks);

  // Random jitter per block based on chaos
  let blockHash = hash12(blockUV + u.config.x * 0.01 * max(chaos, 0.001));
  // Priority 3: per-block FFT voice - each block vibrates to its own bin
  let blockVoice = plasmaBuffer[(u32(blockHash * 8.0) % 8u) + 1u].x * 0.5;
  let jitter = (blockHash - 0.5) * 0.1 * chaos * (1.0 + blockVoice);
  var activeBlockUV = clamp(blockUV + jitter, vec2<f32>(0.0), vec2<f32>(1.0));

  // Aberration on Block UV with clamped sample coordinates
  let rUV = clamp(activeBlockUV + vec2(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(activeBlockUV - vec2(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, activeBlockUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var colEffect = vec4<f32>(r, g, b, mask);

  // Branchless color channel shuffle and inversion based on chaos
  let activeChaos = step(0.2, chaos);
  let shuffle1 = step(0.6, blockHash);
  let shuffle2 = step(blockHash, 0.3);
  let doInvert = step(0.7, chaos) * step(0.8, blockHash);

  let shuffled1 = vec4<f32>(colEffect.g, colEffect.b, colEffect.r, mask);
  let shuffled2 = vec4<f32>(colEffect.b, colEffect.r, colEffect.g, mask);
  let anyShuffle = max(shuffle1, shuffle2);
  let chosenShuffle = select(shuffled2, shuffled1, shuffle1 > 0.5);
  let afterShuffle = mix(colEffect, chosenShuffle, activeChaos * anyShuffle);

  let inverted = vec4<f32>(1.0 - afterShuffle.rgb, mask);
  colEffect = mix(afterShuffle, inverted, activeChaos * doInvert);

  // Spring-lag rim shimmer: the field edge glows while the center is moving
  let springSpeed = length(vec2<f32>(extraBuffer[135], extraBuffer[136]));
  let rim = mask * (1.0 - mask) * 4.0;  // peaks at the field boundary
  let rimGlow = rim * clamp(springSpeed * 2.0, 0.0, 1.0);

  let finalRGB = mix(colOrig.rgb, colEffect.rgb, mask);
  let holoTint = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + blockHash * 6.0 + u.config.x * 0.2 + mids);
  let decoTint = mix(vec3<f32>(0.35, 0.85, 1.0), holoTint, 0.45);
  let rgbRing = finalRGB + ringGlow * mask * decoTint * 0.4;
  let rgbOut = rgbRing + rimGlow * decoTint * 0.25;
  let effectStrength = mask * (0.5 + chaos * 0.3 + treble * 0.1);
  let alpha = clamp(effectStrength + dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114)) * 0.3, 0.0, 1.0);
  let finalColor = vec4<f32>(rgbOut, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
