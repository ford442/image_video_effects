// ═══════════════════════════════════════════════════════════════════
//  Data Moshing Diffusion
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10, 2026-11-21
//  Ideas: tangent diffusion; packet wake; macroblock motion carry (§12.2B); isotropic 9-point diffusion stencil (§12.2D)
//  A packing: raw sim (offset.xy, unused, alpha)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

struct Fp128Vec2 {
  base: vec2<f32>,
  mant: vec2<f32>,
}

fn fp128v2_add(a: Fp128Vec2, b: Fp128Vec2) -> Fp128Vec2 {
  return Fp128Vec2(a.base + b.base, a.mant + b.mant);
}
fn fp128v2_val(v: Fp128Vec2) -> vec2<f32> { return v.base + v.mant; }

fn diffusionCoefficient(gradientMag: f32, kappa: f32) -> f32 {
  return exp(-(gradientMag * gradientMag) / (kappa * kappa + 0.0001));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stream_packet(uv: vec2<f32>, time: f32, treble: f32) -> f32 {
  return pow(max(0.0, sin(uv.y * 48.0 + uv.x * 17.0 - time * (14.0 + treble * 6.0))), 12.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let coord = vec2<i32>(global_id.xy);
  let maxCoord = vec2<i32>(i32(res.x) - 1, i32(res.y) - 1);
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let aspect = res.x / res.y;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let smearStrength = u.zoom_params.x * (1.0 + bass * 0.3);
  let kappa = mix(0.01, 0.2, u.zoom_params.y) * (1.0 - mids * 0.1);
  let dt = mix(0.05, 0.25, u.zoom_params.z) * (1.0 + treble * 0.1);
  let quantize = u.zoom_params.w;

  let conveyor = vec2<i32>(i32(round(sin(uv.y * 10.0 + time * 1.7) * 2.0)), 2 + i32(round(bass * 2.0)));
  let historyCoord = clamp(coord + conveyor, vec2<i32>(0), maxCoord);
  // ── Idea 1: macroblock motion carry (§12.2B) ─────────────────────────────
  // A P-frame keeps one motion vector per macroblock and re-applies it to old pixels, so a real mosh
  // moves in a block lattice, not per pixel. Pull the exact-C history toward the block-centre vector
  // from last frame's C (same conveyor shift). Weight rides the Quantize role (compression
  // coarseness): 0 at quantize = 0 (HEAD look), ~0.36 at the saved default. Packing unchanged.
  let blockPx = max(8, i32(res.y / 48.0));
  let blockCentre = min((coord / blockPx) * blockPx + vec2<i32>(blockPx / 2), maxCoord);
  let blockHist = clamp(blockCentre + conveyor, vec2<i32>(0), maxCoord);
  let blockMV = textureLoad(dataTextureC, blockHist, 0).xy;
  let pixelHist = textureLoad(dataTextureC, historyCoord, 0).xy;
  let blockCarry = clamp(quantize * 1.2, 0.0, 0.9);
  var offset128 = Fp128Vec2(mix(pixelHist, blockMV, blockCarry), vec2<f32>(0.0));

  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseRadius = mix(0.05, 0.3, smearStrength);
  if (mouseDist < mouseRadius) {
    let angle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
    let swirl = vec2<f32>(cos(angle + time), sin(angle + time));
    let force = (1.0 - mouseDist / mouseRadius) * smearStrength * 0.02 * select(0.35, 1.0, held);
    offset128 = fp128v2_add(offset128, Fp128Vec2(swirl * force, vec2<f32>(0.0)));
  }

  let packet = stream_packet(uv, time, treble);
  offset128 = fp128v2_add(offset128, Fp128Vec2(vec2<f32>(0.012, -0.004) * packet * smearStrength * (1.0 + treble), vec2<f32>(0.0)));

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.8) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let distanceToClick = length(delta);
      let direction = delta / max(distanceToClick, 0.0001);
      let front = smoothstep(0.025, 0.0, abs(distanceToClick - age * 0.44)) * exp(-age * 1.5);
      offset128 = fp128v2_add(offset128, Fp128Vec2(direction * front * 0.025 * smearStrength, vec2<f32>(0.0)));
    }
  }

  var offset = fp128v2_val(offset128) * 0.96;
  offset = clamp(offset, vec2<f32>(-0.5), vec2<f32>(0.5));

  let distortedUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
  // One fetch for all three channels (HEAD fetched the same texel once per channel; output identical).
  let centreRGB = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;
  var currentR = centreRGB.r;
  var currentG = centreRGB.g;
  var currentB = centreRGB.b;

  // The stencil taps do not depend on the iteration, so they are fetched once (HEAD refetched the four
  // axis taps per iteration); that pays for the four diagonal taps of Idea 2.
  let n = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(0.0, pixelSize.y), 0.0);
  let s = textureSampleLevel(readTexture, u_sampler, distortedUV - vec2<f32>(0.0, pixelSize.y), 0.0);
  let e = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(pixelSize.x, 0.0), 0.0);
  let w = textureSampleLevel(readTexture, u_sampler, distortedUV - vec2<f32>(pixelSize.x, 0.0), 0.0);
  // ── Idea 2: isotropic 9-point diffusion stencil (§12.2D) ───────────────────
  // The N/S/E/W cross smears diagonal contours along the pixel grid. Corner taps at weight 0.2 and axis
  // taps at 0.8 give the isotropic 9-point Laplacian while keeping HEAD's total weight 4.0, so the overall
  // diffusion rate (dt, kappa) is unchanged; only its axis bias goes away.
  let ne = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(pixelSize.x, pixelSize.y), 0.0);
  let nw = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(-pixelSize.x, pixelSize.y), 0.0);
  let se = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(pixelSize.x, -pixelSize.y), 0.0);
  let sw = textureSampleLevel(readTexture, u_sampler, distortedUV + vec2<f32>(-pixelSize.x, -pixelSize.y), 0.0);

  var avgCoeff = 0.0;
  for (var iter = 0; iter < 2; iter++) {
    let gradNR = length(vec3<f32>(n.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradSR = length(vec3<f32>(s.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradER = length(vec3<f32>(e.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradWR = length(vec3<f32>(w.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradNE = length(vec3<f32>(ne.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradNW = length(vec3<f32>(nw.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradSE = length(vec3<f32>(se.rgb - vec3<f32>(currentR, currentG, currentB)));
    let gradSW = length(vec3<f32>(sw.rgb - vec3<f32>(currentR, currentG, currentB)));

    var cN = diffusionCoefficient(gradNR, kappa * (1.0 + bass * 0.1));
    var cS = diffusionCoefficient(gradSR, kappa * (1.0 + mids * 0.1));
    var cE = diffusionCoefficient(gradER, kappa * (1.0 + treble * 0.1));
    var cW = diffusionCoefficient(gradWR, kappa);
    // Idea: tangentDiffusion — smear runs along the contour, kappa still sets the base.
    let gradVec = vec2<f32>(gradER - gradWR, gradNR - gradSR);
    let tangentDiffusion = abs(gradVec.y) / max(length(gradVec), 0.001);
    let acrossEdge = 1.0 - tangentDiffusion;
    cE = cE * (1.0 + tangentDiffusion * 1.4);
    cW = cW * (1.0 + tangentDiffusion * 1.4);
    cN = cN * (1.0 + acrossEdge * 1.4);
    cS = cS * (1.0 + acrossEdge * 1.4);
    // Idea 2 (cont.): corner coefficients keep Perona–Malik edge-stopping, and the contour-tangent weight
    // above is extended to the diagonals by |t·d| (t = contour tangent, d = corner direction), so a 45°
    // contour smears along itself instead of along the grid axes.
    let nrm = gradVec / max(length(gradVec), 0.001);
    let tng = vec2<f32>(nrm.y, -nrm.x);
    let cNE = diffusionCoefficient(gradNE, kappa) * (1.0 + abs(tng.x + tng.y) * 0.7071 * 1.4);
    let cNW = diffusionCoefficient(gradNW, kappa) * (1.0 + abs(tng.y - tng.x) * 0.7071 * 1.4);
    let cSE = diffusionCoefficient(gradSE, kappa) * (1.0 + abs(tng.x - tng.y) * 0.7071 * 1.4);
    let cSW = diffusionCoefficient(gradSW, kappa) * (1.0 + abs(-tng.x - tng.y) * 0.7071 * 1.4);
    let mouseBoost = 1.0 + exp(-mouseDist * mouseDist * 10.0) * smearStrength * 5.0;

    let cur = vec3<f32>(currentR, currentG, currentB);
    let axisSum = cN * (n.rgb - cur) + cS * (s.rgb - cur) + cE * (e.rgb - cur) + cW * (w.rgb - cur);
    let cornerSum = cNE * (ne.rgb - cur) + cNW * (nw.rgb - cur) + cSE * (se.rgb - cur) + cSW * (sw.rgb - cur);
    let stencil = 0.8 * axisSum + 0.2 * cornerSum;
    currentR += dt * mouseBoost * stencil.r * (1.0 + bass * 0.1);
    currentG += dt * mouseBoost * stencil.g;
    currentB += dt * mouseBoost * stencil.b * (1.0 + treble * 0.1);
    avgCoeff = (cN + cS + cE + cW) * 0.25;
  }

  var finalColor = vec3<f32>(currentR, currentG, currentB);
  if (quantize > 0.0) {
    // Rescue: HEAD reached 1 level at quantize = 1 (floor(c * 1) = 0 → near-black). Keep ≥ 2 levels.
    let q = max(20.0 * (1.0 - quantize) + 1.0 + bass * 5.0, 2.0);
    finalColor = floor(finalColor * q) / q;
  }

  let trailUV = clamp(uv - offset * 1.65, vec2<f32>(0.0), vec2<f32>(1.0));
  let trailColor = textureSampleLevel(readTexture, u_sampler, trailUV, 0.0).rgb;
  finalColor = mix(finalColor, trailColor, (0.08 + smearStrength * 0.12) * (1.0 - packet * 0.45));
  // Idea: packetWake — pull a sample upstream of the racing packet. C stays the offset field.
  let wakeUv = clamp(distortedUV - vec2<f32>(0.02, -0.008) * (0.35 + packet * 3.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let packetWake = textureSampleLevel(readTexture, u_sampler, wakeUv, 0.0).rgb;
  finalColor = mix(finalColor, packetWake, packet * 0.55);
  finalColor = acesToneMap(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(4.0)));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let alpha = clamp(avgCoeff + length(offset) * 2.0 + bass * 0.05 + packet * 0.1, 0.06, 0.98);

  textureStore(dataTextureA, coord, vec4<f32>(offset, 0.0, alpha));
  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
