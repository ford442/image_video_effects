// ═══════════════════════════════════════════════════════════════════
//  Glitch Reveal
//  Category: image
//  Features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: datamosh block hold from C along the block vector; horizontal tear bands; block-snapped window edge
//  A packing: ACES display RGB + .a = 10 + alpha validity sentinel (C read as colour for the block hold / ghost)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn blockEdge(cellUV: vec2<f32>) -> f32 {
  let edge = min(min(cellUV.x, 1.0 - cellUV.x), min(cellUV.y, 1.0 - cellUV.y));
  return 1.0 - smoothstep(0.0, 0.12, edge);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let held = u.zoom_config.w > 0.5;
  // Raw pointer: the old extraBuffer[133..138] spring was re-zeroed by the CPU upload every
  // frame and raced across workgroups, tearing the window toward the top-left corner.
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let blockSize = u.zoom_params.x * 0.2 + 0.01;
  let scatter = u.zoom_params.y * (1.0 + bass * 2.0);
  let revealRadius = (u.zoom_params.z * 0.5 + 0.05) * select(1.0, 1.35, held);
  let speed = u.zoom_params.w * 10.0;

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let effectiveRadius = revealRadius * mix(0.6, 1.4, depth);
  let tick = floor(time * speed * (1.0 + mids));

  // Idea 2: horizontal tear bands — a slower hash over row strips shears whole rows of blocks
  // sideways (sync-tear axis on top of the per-block scatter); bass makes tears more frequent.
  let bandH = max(blockSize * 0.45, 0.004);
  let bandId = floor(uv.y / bandH);
  let bandRand = hash22(vec2<f32>(bandId * 1.37 + 11.0, floor(tick * 0.5) + 3.0));
  let tearOn = step(0.86 - bass * 0.15, bandRand.x);
  let tearShift = tearOn * (bandRand.y - 0.5) * 0.3 * scatter;
  let tornUV = vec2<f32>(uv.x + tearShift, uv.y);

  let gridUV = floor(tornUV / blockSize);
  let cellUV = fract(tornUV / blockSize);
  let seed = gridUV + tick;
  let rand = hash22(seed);
  var blockOffset = (rand - 0.5) * scatter;

  let dVec = uv - mouse;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
  let smoothMask = select(1.0, smoothstep(effectiveRadius * 0.75, effectiveRadius, dist), dist < effectiveRadius);

  // Idea 3: block-snapped window edge — the window is also judged at each block's centre, with a
  // per-block/per-tick dither in the edge band, so whole blocks lock clean (or drop out) at the rim.
  let blockCenter = (gridUV + 0.5) * blockSize - vec2<f32>(tearShift, 0.0);
  let centerCoord = clamp(vec2<i32>(blockCenter * resolution), vec2<i32>(0), maxCoord);
  let centerDepth = textureLoad(readDepthTexture, centerCoord, 0).r;
  let centerRadius = revealRadius * mix(0.6, 1.4, centerDepth);
  let dCenter = length((blockCenter - mouse) * vec2<f32>(aspect, 1.0));
  let edgeDither = (hash22(gridUV * 1.7 + vec2<f32>(tick, 5.0)).x - 0.5) * blockSize * 0.9;
  let blockMask = smoothstep(centerRadius * 0.85, centerRadius, dCenter + edgeDither);
  var mask = min(smoothMask, blockMask);

  var rippleReveal = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      rippleReveal += smoothstep(0.14, 0.0, rDist) * (1.0 - age * 0.85);
    }
  }
  mask = clamp(mask - rippleReveal * 0.8, 0.0, 1.0);
  blockOffset = blockOffset * mask;

  let sampleUV = clamp(uv + blockOffset + vec2<f32>(tearShift * mask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let caDir = (uv - 0.5) * 0.035 * mask * scatter * (1.0 + depth);
  let colorSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + caDir, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    colorSample.g,
    textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - caDir, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  if (mask > 0.01 && scatter > 0.0) {
    if (rand.x > 0.78) {
      let shiftSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.012 * mask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
      color = vec3<f32>(shiftSample.r, colorSample.g, colorSample.b);
    } else if (rand.x < 0.18) {
      color = 1.0 - colorSample.rgb;
    }
  }

  let border = smoothstep(effectiveRadius, effectiveRadius + 0.012, dist)
             - smoothstep(effectiveRadius + 0.012, effectiveRadius + 0.024, dist);
  let edgeGlow = blockEdge(cellUV) * mask;
  if (border > 0.0 || edgeGlow > 0.3) {
    let borderColor = vec3<f32>(0.0, 1.0, 0.55) + vec3<f32>(treble * 0.2);
    color = mix(color, borderColor, (border + edgeGlow * 0.4) * 0.45);
  }

  var display = acesToneMap(max(color, vec3<f32>(0.0)) * (0.96 + bass * 0.06));

  // C holds last frame's display RGB, so it is blended in display space (no re-tonemapping).
  // A.a carries 10 + alpha: a C texel outside that band (never written, or another shader's
  // output right after a switch) is ignored instead of washing its picture into the glitch.
  let prev = textureLoad(dataTextureC, coord, 0);
  let prevRGB = select(display, prev.rgb, prev.a > 9.5 && prev.a < 11.5);
  // Capped below 1: with Scatter maxed and bass boosting it, a weight of 1 froze the frame for good.
  display = mix(display, prevRGB, clamp(mask * scatter * 0.65, 0.0, 0.85));

  // Idea 1: datamosh block hold — blocks that drew rand.y > 0.72 this tick skip their "I-frame" and
  // re-use the previous frame from exact C, fetched along the block's own motion vector, so stale
  // blocks slide and smear (P-frame drag) until the next jitter tick re-keys them.
  if (rand.y > 0.72 && mask > 0.01 && scatter > 0.0) {
    let motion = (rand - 0.5) * 0.02 * scatter;
    let holdCoord = clamp(vec2<i32>((uv - motion) * resolution), vec2<i32>(0), maxCoord);
    let heldTexel = textureLoad(dataTextureC, holdCoord, 0);
    let held_rgb = select(display, heldTexel.rgb, heldTexel.a > 9.5 && heldTexel.a < 11.5);
    let holdW = mask * clamp(scatter * 1.8, 0.0, 0.9);
    display = mix(display, held_rgb, holdW);
  }

  var alpha = mix(mix(0.5, 1.0, depth), 1.0, 1.0 - clamp(mask * scatter, 0.0, 1.0));
  alpha = clamp(alpha + rippleReveal * 0.1 + border * 0.3, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(display, 10.0 + alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
