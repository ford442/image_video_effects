// ═══════════════════════════════════════════════════════════════════
//  Quantum Cursor
//  Category: interactive-mouse
//  Features: mouse-driven, distortion, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  Upgraded: 2026-07-31, 2026-10-27
//  Ideas: stair boundary on the block pitch; bright pixels collapse toward the photo
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Radius, y=BlockSize, z=Aberration, w=Chaos

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0));
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3  = fract(vec3<f32>(p.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 0.001);
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // extraBuffer is cleared every frame, so the old spring sat at the origin.
  let mouse = rawMouse;

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

  // ── Idea 1: stair boundary. The field edge sits on the block pitch.
  let blockStep = max(mosaic_scale / max(resolution.y, 1.0), 0.004);
  let qDist = floor(dist / blockStep) * blockStep;
  let mask = smoothstep(radius, radius * 0.8, qDist);

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
  // plasmaBuffer[1..] is never uploaded. Blocks share the live treble band.
  let blockVoice = treble * fract(blockHash * 7.13);
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

  let rim = mask * (1.0 - mask) * 4.0;
  let rimGlow = rim * clamp(treble * 0.8 + chaos, 0.0, 1.0);

  // ── Idea 2: bright collapse. Highlights inside the field stay sharp
  // as Chaos falls. Dark blocks keep the mosaic.
  let blockLuma = dot(colEffect.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let sharp = smoothstep(0.55, 0.9, blockLuma) * (1.0 - chaos);
  let collapsed = mix(colEffect.rgb, colOrig.rgb, sharp);
  let finalRGB = mix(colOrig.rgb, collapsed, mask);
  let holoTint = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + blockHash * 6.0 + u.config.x * 0.2 + mids);
  let decoTint = mix(vec3<f32>(0.35, 0.85, 1.0), holoTint, 0.45);
  let rgbRing = finalRGB + ringGlow * mask * decoTint * 0.4;
  let rgbOut = rgbRing + rimGlow * decoTint * 0.25;
  let effectStrength = mask * (0.5 + chaos * 0.3 + treble * 0.1);
  let alpha = clamp(effectStrength + dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114)) * 0.3, 0.0, 1.0);
  let finalColor = vec4<f32>(acesFilm(rgbOut), alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
