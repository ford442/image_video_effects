// ═══════════════════════════════════════════════════════════════════
//  Datamosh Brush Diffusion — Batch 60
//  Category: advanced-hybrid
//  Features: datamosh, anisotropic-diffusion, mouse-driven, temporal, audio-reactive, aces-tone-map
//  Upgraded: 2026-11-09
//  Ideas: motion-carry smear (macroblock motion carry, §12.2B); luma/chroma split bleed (chroma delay variant, §12.2B)
//  A packing: raw diffused colour state (pre oil-tint, pre-ACES) + alpha, read back as C colour; texels (0,0)/(1,0) hold the brush glide [pos, fract(time), 0.7371]/[vel, 0, 0.7371]
//  Perona-Malik anisotropic diffusion + datamosh brush: gliding cursor,
//  held heat source, capped ripples, exact C loads, ACES (display only) + audio.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Idea 2 (luma/chroma split bleed). Share of a mosh block's LUMA that stays the held/diffused frame; the rest of
// the luma and ALL the chroma come from the carried/displaced sample. 0 = idea off (pure displaced sample);
// the visible split (changed pixels vs off) plateaus over 0.6-0.85 and falls on both sides, so LOWERING it
// toward 0.35 weakens the effect. No chroma gain > 1: the carried sample is last frame's state, so any gain
// compounds every frame and runs away to neon.
const CHROMA_LUMA_KEEP: f32 = 0.6;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
  return fract(n * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// History read. Texels (0,0)/(1,0) of A carry the brush-glide state, not colour, so colour reads never touch them.
fn loadC(c: vec2<i32>) -> vec4<f32> {
  let isState = (c.y == 0 && c.x < 2);
  return textureLoad(dataTextureC, select(c, vec2<i32>(c.x, 1), isState), 0);
}

// Exact bilinear from four clamped loads (no filtering sampler on rgba32float history). p in pixel units.
fn bilerpC(p: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  let pc = p - vec2<f32>(0.5);
  let fl = floor(pc);
  let f = pc - fl;
  let i0 = vec2<i32>(fl);
  let hi = dims - vec2<i32>(1);
  let c00 = loadC(clamp(i0, vec2<i32>(0), hi));
  let c10 = loadC(clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), hi));
  let c01 = loadC(clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), hi));
  let c11 = loadC(clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), hi));
  return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
  return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
  let coord = vec2<i32>(global_id.xy);
  let aspect = resolution.x / resolution.y;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let brushSize = mix(0.02, 0.22, u.zoom_params.x) * (1.0 + bass * 0.3);
  let kappa = mix(0.01, 0.22, u.zoom_params.y) * (1.0 - mids * 0.15);
  let dt = mix(0.05, 0.28, u.zoom_params.z) * (1.0 + treble * 0.2);
  let alphaGhost = mix(0.3, 1.0, u.zoom_params.w);

  // Rescue R1: HEAD's spring lived in extraBuffer[133..138], which the host re-uploads as ZERO every frame,
  // so `smoothMouse` was (0,0) for every pixel and the brush/heat sat pinned in the top-left corner. The glide
  // (ω = 9.5, as HEAD) now rides texels (0,0)/(1,0) of A (read back as C): (0,0) = [pos.xy, fract(time),
  // 0.7371], (1,0) = [vel.xy, 0, 0.7371]. Every thread integrates the same step. Those two corner pixels of
  // colour history are not used (loadC redirects colour reads).
  let stA = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let stB = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stOk = abs(stA.w - 0.7371) < 0.001 && abs(stB.w - 0.7371) < 0.001;
  let stDt = fract(time - stA.z);
  let stLive = stOk && stDt > 0.0005 && stDt < 0.25;
  let springDt = clamp(stDt, 0.001, 0.05);
  let omega = 9.5;
  var springPos = select(mouse, stA.xy, stLive);
  var springVel = select(vec2<f32>(0.0), stB.xy, stLive);
  let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
  springVel = springVel + accel * springDt;
  springPos = springPos + springVel * springDt;
  springVel = select(vec2<f32>(0.0), springVel, stLive);
  springPos = select(mouse, springPos, stLive);
  let smoothMouse = springPos;

  let dims = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let prevSample = loadC(coord);
  var prevColor = prevSample.rgb;
  var prevAlpha = prevSample.a;
  if (prevAlpha < 0.01) {
    let currSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    prevColor = currSample.rgb;
    prevAlpha = currSample.a;
  }

  let inputSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var blendedColor = mix(prevColor, inputSample.rgb, 0.05);
  var blendedAlpha = mix(prevAlpha, inputSample.a, 0.05);
  blendedAlpha = blendedAlpha * 0.98;

  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouseAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let dist = distance(uvAspect, mouseAspect);

  var rippleHeat = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.1) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      // max(…, 0): HEAD's (1 - age) went negative for age 1.0–1.1 (heat dipped below 0, mouseBoost to 0.8) and then
      // snapped back at the 1.1 s cutoff. Now exactly 0 from age 1.0 on.
      rippleHeat += smoothstep(0.12, 0.0, distance(uvAspect, rAspect)) * max(1.0 - age, 0.0);
    }
  }

  if ((held && dist < brushSize) || rippleHeat > 0.05) {
    let blockID = floor(uv * 24.0);
    let noiseVal = hash12(blockID + vec2<f32>(time));
    if (noiseVal > 0.28 || rippleHeat > 0.25) {
      let hashOff = hash22(blockID) * 0.06;
      let offsetUV = clamp(uv + hashOff, vec2<f32>(0.0), vec2<f32>(1.0));
      let glitchSample = textureSampleLevel(readTexture, u_sampler, offsetUV, 0.0);

      // ── Idea 1: motion-carry smear (§12.2B macroblock motion carry) ──
      // Datamosh is a P-frame decoded with the WRONG reference: the old picture is dragged along the motion
      // vector. Here the brush's own glide velocity is that vector — the block samples the PREVIOUS frame
      // (exact C) displaced against the stroke, so the mosh drags content along with the cursor. At rest the
      // weight is 0 and the block is HEAD's displaced input sample.
      let brushSpeed = length(springVel);
      let carryVec = springVel * 0.035;
      let carryLen = min(length(carryVec), 0.08);
      let carry = carryVec * (carryLen / max(length(carryVec), 1e-5));
      let carriedUV = uv - carry + hashOff * 0.15;
      let carried = bilerpC(clamp(carriedUV, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution, dims);
      let carryW = smoothstep(0.05, 0.6, brushSpeed);
      let moshRgb = mix(glitchSample.rgb, carried.rgb, carryW);
      let moshA = mix(glitchSample.a, carried.a, carryW);

      // ── Idea 2: luma/chroma split bleed (§12.2B chroma delay variant) ──
      // A wrong reference carries the old COLOURS, not the old structure: luma stays mostly the held /
      // diffused frame (CHROMA_LUMA_KEEP of it kept, the rest follows the carried sample), chroma comes from the
      // displaced / carried sample, so colour bleeds across intact edges inside mosh blocks.
      let lw = vec3<f32>(0.299, 0.587, 0.114);
      let moshLuma = dot(moshRgb, lw);
      let keepLuma = mix(moshLuma, dot(blendedColor, lw), CHROMA_LUMA_KEEP);
      blendedColor = max(vec3<f32>(keepLuma) + (moshRgb - vec3<f32>(moshLuma)), vec3<f32>(0.0));
      blendedAlpha = moshA * 0.8 + 0.1;
    } else {
      blendedColor = prevColor;
      blendedAlpha = prevAlpha * alphaGhost;
    }
    blendedAlpha = max(blendedAlpha, 0.1);
  }

  let center = blendedColor;
  let nCoord = clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1));
  let sCoord = clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), dims - vec2<i32>(1));
  let eCoord = clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1));
  let wCoord = clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), dims - vec2<i32>(1));
  let n = loadC(nCoord).rgb;
  let s = loadC(sCoord).rgb;
  let e = loadC(eCoord).rgb;
  let w = loadC(wCoord).rgb;

  let gradN = length(n - center);
  let gradS = length(s - center);
  let gradE = length(e - center);
  let gradW = length(w - center);

  let cN = diffusionCoefficient(gradN, kappa);
  let cS = diffusionCoefficient(gradS, kappa);
  let cE = diffusionCoefficient(gradE, kappa);
  let cW = diffusionCoefficient(gradW, kappa);

  let mouseDist = length(uv - smoothMouse);
  let mouseFactor = exp(-mouseDist * mouseDist * 10.0) * select(0.0, 1.0, held);
  let mouseBoost = 1.0 + mouseFactor * 6.0 + rippleHeat * 2.0;

  let fluxN = cN * (n - center);
  let fluxS = cS * (s - center);
  let fluxE = cE * (e - center);
  let fluxW = cW * (w - center);

  let diffused = center + dt * mouseBoost * (fluxN + fluxS + fluxE + fluxW);
  let avgCoeff = (cN + cS + cE + cW) * 0.25;
  let stateColor = max(mix(blendedColor, diffused, 0.45 + avgCoeff * 0.55), vec3<f32>(0.0));
  blendedAlpha = clamp(blendedAlpha, 0.0, 1.0);

  // Rescue R2: HEAD stored ACES(oil-tinted colour) in A and read it back as the next frame's prevColor
  // (95 % weight), so the tint (1.05, 0.95, 1.15) and the ACES curve compounded every frame. A now keeps
  // the raw diffused state; tint, exposure and ACES are display-only.
  let oilTint = vec3<f32>(1.05, 0.95, 1.15) * (0.9 + mids * 0.15);
  let displayRgb = acesToneMap(stateColor * oilTint * (0.95 + bass * 0.08));

  var aOut = vec4<f32>(stateColor, blendedAlpha);
  if (coord.y == 0 && coord.x == 0) { aOut = vec4<f32>(springPos, fract(time), 0.7371); }
  if (coord.y == 0 && coord.x == 1) { aOut = vec4<f32>(springVel, 0.0, 0.7371); }
  textureStore(dataTextureA, coord, aOut);
  textureStore(writeTexture, coord, vec4<f32>(displayRgb, blendedAlpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
