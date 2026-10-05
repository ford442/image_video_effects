// ═══════════════════════════════════════════════════════════════════
//  Pixel Reveal v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: reveal memory with per-block dropout; progressive-decode resolution ladder; colour-depth ladder with block Bayer dither
//  A packing: display RGB + reveal memory in .a as 10 + level (only C.a is read back; <9.5 = empty)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash3(p: vec3<f32>) -> vec3<f32> {
  var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yxz + 33.33);
  return fract((p3.xxy + p3.yzz) * p3.zyx);
}

fn aces_tone_map(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 4x4 ordered-dither threshold in [0,1): bits (x0^y0, y0, x1^y1, y1) from MSB.
fn bayer4(p: vec2<u32>) -> f32 {
  let x = p.x & 3u;
  let y = p.y & 3u;
  let v = (((x ^ y) & 1u) << 3u) | ((y & 1u) << 2u) | ((((x >> 1u) ^ (y >> 1u)) & 1u) << 1u) | ((y >> 1u) & 1u);
  return (f32(v) + 0.5) / 16.0;
}

// Reveal memory sentinel: A.a = 10 + level (level in 0..1). Anything outside [9.5, 11.5] — stale
// alpha from another shader, an unwritten C, NaN — is treated as an empty memory.
fn memRead(a: f32) -> f32 {
  let valid = a > 9.5 && a < 11.5;
  return select(0.0, clamp(a - 10.0, 0.0, 1.0), valid);
}

// Live pointer reveal (1 = revealed), held inverts it exactly as before.
fn liveReveal(p: vec2<f32>, mousePos: vec2<f32>, aspect: f32, radius: f32, softness: f32, mouseDown: bool) -> f32 {
  let dist = length((p - mousePos) * vec2<f32>(aspect, 1.0));
  let revealMask = smoothstep(radius, radius + softness, dist);
  return 1.0 - select(revealMask, 1.0 - revealMask, mouseDown);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / resolution;

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let pixelSizeParam = u.zoom_params.x;
  let radius = u.zoom_params.y * 0.5;
  let softness = max(u.zoom_params.z * 0.2, 0.001);
  let decayRate = u.zoom_params.w;

  // Depth-driven pixel size perspective
  let depthBlock = mix(0.5, 1.5, depth);
  let stepBase = max(0.002, pixelSizeParam * 0.08 * depthBlock);
  let stepX = stepBase;
  let stepY = stepBase * (resolution.x / resolution.y);
  let coarseStep = vec2<f32>(stepX, stepY);
  let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
  let aspect = resolution.x / max(resolution.y, 1.0);

  // Idea 1: reveal memory with per-block dropout — the reveal persists in A.a and fades at the
  // Temporal Decay rate; each coarse pixel block gets its own fade speed and is read back at its
  // centre, so remembered areas drop out as whole pixels rather than a smooth gradient.
  let coarseId = floor(uv / coarseStep);
  let coarseUV = (coarseId + 0.5) * coarseStep;
  let blockFade = max(decayRate * 0.025, 0.0015) * mix(0.4, 1.6, hash3(vec3<f32>(coarseId, 7.0)).x);
  // Memory is stored as 10 + level so a previous shader's C.a (commonly 1.0), a never-written C (0)
  // or a NaN all read as "nothing remembered" instead of "fully revealed".
  let memPixel = memRead(textureLoad(dataTextureC, coord, 0).a);
  let centerCoord = clamp(vec2<i32>(coarseUV * resolution), vec2<i32>(0), maxCoord);
  let memBlock = clamp(memRead(textureLoad(dataTextureC, centerCoord, 0).a) - blockFade, 0.0, 1.0);
  let liveCenter = liveReveal(coarseUV, mousePos, aspect, radius, softness, mouseDown);

  // Idea 2: progressive-decode ladder — the coarse block's remembered reveal picks a power-of-two
  // subdivision (1, 1/2, 1/4), so sub-blocks nest and refine toward the heart of the reveal.
  let revealCenter = max(liveCenter, memBlock);
  let ladder = select(select(0.0, 1.0, revealCenter > 0.34), 2.0, revealCenter > 0.67);
  let fineStep = coarseStep / exp2(ladder);
  let fineId = floor(uv / fineStep);

  // Bass-driven threshold oscillation
  let threshold = 0.3 + bass * 0.25 + sin(time * 3.0) * 0.1;

  // Pixelate UV with glitch jitter
  let jitter = vec2<f32>(
    (treble * 0.015) * sin(uv.y * 60.0 + time * 12.0),
    (treble * 0.015) * cos(uv.x * 60.0 + time * 12.0)
  );
  let pixelatedUV = clamp(fineId * fineStep + fineStep * 0.5 + jitter, vec2<f32>(0.001), vec2<f32>(0.999));

  // Mouse reveal mask (painted radius), now max'd with the remembered block reveal
  let live = liveReveal(uv, mousePos, aspect, radius, softness, mouseDown);
  let reveal = max(live, memBlock);
  let memNext = clamp(max(live, memPixel - blockFade), 0.0, 1.0);

  // Temporal noise accumulation for decay
  let noise = hash3(vec3<f32>(uv * 30.0, fract(time * 0.5))).x;
  let temporalDecay = fract(noise + time * decayRate * 0.5) * reveal;

  // Pixel sorting threshold: only reveal pixels above luminance threshold
  let pxColor = textureSampleLevel(readTexture, u_sampler, pixelatedUV, 0.0);
  let pxLuma = dot(pxColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let sortReveal = smoothstep(threshold - 0.1, threshold + 0.1, pxLuma);

  // Combined reveal: mouse-painted area OR sorted bright pixels, minus decay
  let combinedReveal = clamp(reveal + sortReveal * 0.6 - temporalDecay * 0.5, 0.0, 1.0);

  // Chromatic separation on reveal edges
  let edgeWidth = 0.02 + softness * 0.5;
  let edgeGradient = abs(combinedReveal - 0.5) * 2.0;
  let edgeMask = 1.0 - smoothstep(0.0, edgeWidth, abs(edgeGradient - 1.0));
  let chromaShift = 0.004 * (1.0 + mids * 0.8) * edgeMask;

  let r = textureSampleLevel(readTexture, non_filtering_sampler, pixelatedUV + vec2<f32>(chromaShift, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, non_filtering_sampler, pixelatedUV, 0.0).g;
  let b = textureSampleLevel(readTexture, non_filtering_sampler, pixelatedUV - vec2<f32>(chromaShift, 0.0), 0.0).b;
  // Idea 3: colour-depth ladder — 4 / 8 / 16 levels per channel following the same decode ladder,
  // ordered-dithered with a Bayer 4x4 indexed by BLOCK so every big pixel is one flat palette colour.
  let levels = exp2(ladder + 2.0) - 1.0;
  let dither = bayer4(vec2<u32>(max(fineId, vec2<f32>(0.0))));
  let chromaColor = floor(clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0)) * levels + dither) / levels;

  let clearColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Scanline bands on hidden regions
  let scanline = sin(uv.y * resolution.y * 0.7) * 0.5 + 0.5;
  let scanDark = mix(vec3<f32>(0.02, 0.02, 0.03), vec3<f32>(0.08, 0.08, 0.10), scanline);
  let hiddenColor = mix(scanDark, chromaColor * 0.3, temporalDecay * 0.4);

  var finalColor = mix(hiddenColor, chromaColor, combinedReveal);
  finalColor = mix(finalColor, clearColor, reveal * 0.3);

  // Film grain
  let grain = hash3(vec3<f32>(uv * 500.0, time)).x;
  finalColor += (grain - 0.5) * 0.03;

  // ACES tone mapping
  finalColor = aces_tone_map(max(finalColor, vec3<f32>(0.0)));

  // Alpha: Reveal_mask * (1.0 - temporal_decay) * depth
  let alpha = clamp(reveal * (1.0 - temporalDecay * 0.7) * depth + combinedReveal * 0.2, 0.05, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, 10.0 + memNext));
}
