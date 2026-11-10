// ═══════════════════════════════════════════════════════════════════
//  Interactive Kuwahara
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-04, 2026-11-09
//  Ideas: generalised variance-weighted sector blend; impasto ridges lit from the sector-mean gradient; canvas weave through thin paint;
//         structure-tensor sector alignment (§12.2A: sectors follow the edge, coherence-gated);
//         stroke-edge pigment pooling (paint-patch boundaries darken, from the sector weight spread)
//  A packing: ACES display RGBA (C read back as colour for the wet trail)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"



fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, coord, 0);

  let radiusParam = (u.zoom_params.x * 8.0 + 2.0) * (1.0 + bass * 0.4);
  let satBoost = u.zoom_params.y * 2.0 * (1.0 + mids * 0.3);
  let focusRadius = mix(0.08, 0.6, u.zoom_params.z);
  let hardness = mix(0.02, 0.22, u.zoom_params.w);

  let mouse = u.zoom_config.yz;
  let heldStroke = step(0.5, u.zoom_config.w);
  let aspect = resolution.x / max(resolution.y, 1.0);
  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

  let mouseFactor = smoothstep(max(0.0, focusRadius - hardness), focusRadius + hardness, dist);
  let strokeDir = normalize(vec2<f32>(1.0, 0.42));
  let wetRunner = pow(max(0.0, sin(dot(uv * vec2<f32>(aspect, 1.0), strokeDir) * 52.0 - u.config.x * 13.0)), 12.0) * (1.0 - mouseFactor) * mix(0.25, 1.0, heldStroke);
  let packets = pow(max(0.0, sin(uv.x * aspect * 18.0 + uv.y * 22.0 - u.config.x * (6.0 + treble * 4.0))), 10.0) * (1.0 - mouseFactor);

  var clickClarity = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var rippleIndex = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
    let ripple = u.ripples[rippleIndex];
    let age = u.config.x - ripple.z;
    if (age >= 0.0 && age < 1.8) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      clickClarity += smoothstep(0.025, 0.0, abs(length(delta) - age * 0.42)) * exp(-age * 1.5);
    }
  }
  let detailLift = clamp((1.0 - mouseFactor) * mix(0.35, 0.75, heldStroke) + wetRunner * 0.25 + clickClarity * 0.8, 0.0, 0.9);
  let effectiveRadius = mix(radiusParam, max(1.0, radiusParam * 0.25), detailLift);

  let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let radius = min(i32(max(effectiveRadius, 1.0)), 10);
  let pixelSize = vec2<f32>(1.0 / max(resolution.x, 1.0), 1.0 / max(resolution.y, 1.0));

  // ── Idea 4: structure-tensor sector alignment (§12.2A) ───────────────────
  // The four Kuwahara sectors were axis-aligned squares for every pixel, which leaves blocky
  // mosaic seams on diagonal edges. A 3x3 luma grid (1.5 px apart) gives four 2x2 gradients;
  // the mean of their outer products is the structure tensor J, whose dominant angle is the
  // local edge orientation and whose coherence says how trustworthy it is. The sector frame is
  // rotated by that angle, weighted by coherence x gradient energy, so flat and noisy regions
  // keep HEAD's axis-aligned sectors and only real edges steer the paint.
  let tapStep = pixelSize * 1.5;
  var gridLuma: array<f32, 9>;
  for (var gj = 0; gj < 3; gj++) {
    for (var gi = 0; gi < 3; gi++) {
      let go = vec2<f32>(f32(gi - 1), f32(gj - 1)) * tapStep;
      gridLuma[gj * 3 + gi] = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + go, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    }
  }
  var jxx = 0.0;
  var jyy = 0.0;
  var jxy = 0.0;
  for (var cb = 0; cb < 2; cb++) {
    for (var ca = 0; ca < 2; ca++) {
      let g00 = gridLuma[cb * 3 + ca];
      let g10 = gridLuma[cb * 3 + ca + 1];
      let g01 = gridLuma[(cb + 1) * 3 + ca];
      let g11 = gridLuma[(cb + 1) * 3 + ca + 1];
      let cellGx = ((g10 + g11) - (g00 + g01)) * 0.5;
      let cellGy = ((g01 + g11) - (g00 + g10)) * 0.5;
      jxx += cellGx * cellGx;
      jyy += cellGy * cellGy;
      jxy += cellGx * cellGy;
    }
  }
  jxx *= 0.25;
  jyy *= 0.25;
  jxy *= 0.25;
  let tensorTrace = jxx + jyy;
  let tensorDisc = sqrt(max((jxx - jyy) * (jxx - jyy) * 0.25 + jxy * jxy, 0.0));
  let coherence = 2.0 * tensorDisc / max(tensorTrace, 1e-6);
  let orientEnergy = smoothstep(1e-4, 5e-3, tensorTrace);
  let sectorAngle = 0.5 * atan2(2.0 * jxy, (jxx - jyy) + 1e-9) * smoothstep(0.25, 0.75, coherence) * orientEnergy;
  let sectorCos = cos(sectorAngle);
  let sectorSin = sin(sectorAngle);

  var mean: array<vec3<f32>, 4>;
  var sigma: array<vec3<f32>, 4>;
  for (var i = 0; i < 4; i++) {
    mean[i] = vec3<f32>(0.0);
    sigma[i] = vec3<f32>(0.0);
  }
  let offsets = array<vec2<i32>, 4>(
    vec2<i32>(-radius, -radius),
    vec2<i32>(0, -radius),
    vec2<i32>(-radius, 0),
    vec2<i32>(0, 0)
  );
  for (var k = 0; k < 4; k++) {
    var count = 0.0;
    let start = offsets[k];
    for (var j = 0; j <= radius; j++) {
      for (var i = 0; i <= radius; i++) {
        let sectorOff = vec2<f32>(f32(start.x + i), f32(start.y + j));
        let alignedOff = vec2<f32>(sectorCos * sectorOff.x - sectorSin * sectorOff.y, sectorSin * sectorOff.x + sectorCos * sectorOff.y);
        let sampleUV = clamp(uv + alignedOff * pixelSize, vec2<f32>(0.0), vec2<f32>(1.0));
        let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        mean[k] += col;
        sigma[k] += col * col;
        count += 1.0;
      }
    }
    let safeCount = max(count, 0.001);
    mean[k] = mean[k] / safeCount;
    sigma[k] = abs(sigma[k] / safeCount - mean[k] * mean[k]);
  }

  // Idea 1: generalised Kuwahara. Instead of snapping to the single
  // lowest-variance sector (which leaves hard block seams where two sectors
  // tie), every sector contributes with weight 1 / (1 + sigma^q); q = 8 keeps
  // the classic edge-preserving choice but blends near-ties smoothly.
  var weightSum = 0.0;
  var weighted = vec3<f32>(0.0);
  var varSum = 0.0;
  var weightMax = 0.0;
  var weightMin = 1e9;
  var sectorLuma: array<f32, 4>;
  for (var k = 0; k < 4; k++) {
    let v = sigma[k].r + sigma[k].g + sigma[k].b;
    let w = 1.0 / (1.0 + pow(sqrt(v) * 25.5, 8.0));
    weighted += mean[k] * w;
    weightSum += w;
    weightMax = max(weightMax, w);
    weightMin = min(weightMin, w);
    varSum += v;
    sectorLuma[k] = dot(mean[k], vec3<f32>(0.2126, 0.7152, 0.0722));
  }
  let kuwaColor = weighted / max(weightSum, 1e-6);

  let smallRadiusMix = clamp(1.0 - effectiveRadius, 0.0, 1.0);
  let blendedRGB = mix(kuwaColor, baseSample.rgb, smallRadiusMix);
  let lum = dot(blendedRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
  let satColor = mix(vec3<f32>(lum), blendedRGB, 1.0 + satBoost);
  let slick = hsv2rgb(vec3<f32>(fract(0.08 + lum * 0.3 + mids * 0.2 + u.config.x * 0.07), 0.65, 1.0));
  let shimmer = sin(uv.x * 200.0 + u.config.x * 12.0) * treble * 0.05;
  let wetTint = vec3<f32>(0.08, 0.16, 0.22) * wetRunner * (0.3 + treble * 0.3);
  var finalRGB = clamp(satColor + vec3<f32>(shimmer) + wetTint, vec3<f32>(0.0), vec3<f32>(4.0));

  // Idea 2: impasto. The four sector means already sample left/right and
  // up/down of this pixel, so their luma difference is the slope of the
  // painted surface. Busy (high-variance) regions carry thick paint; a fixed
  // studio light from the upper left catches the ridges.
  let stylization = clamp(effectiveRadius / 12.0, 0.0, 1.0);
  // The sector means now live in the rotated frame of Idea 4; rotate the slope back to screen
  // space so the studio light still comes from the upper left.
  let paintSlopeSector = vec2<f32>(
    (sectorLuma[1] + sectorLuma[3]) - (sectorLuma[0] + sectorLuma[2]),
    (sectorLuma[2] + sectorLuma[3]) - (sectorLuma[0] + sectorLuma[1])
  );
  let paintSlope = vec2<f32>(
    sectorCos * paintSlopeSector.x - sectorSin * paintSlopeSector.y,
    sectorSin * paintSlopeSector.x + sectorCos * paintSlopeSector.y
  );
  let thickness = clamp(sqrt(varSum * 0.25) * 6.0, 0.0, 1.0) * stylization;
  let ridge = dot(paintSlope, vec2<f32>(-0.6, -0.8)) * 2.2;
  finalRGB = finalRGB * (1.0 + clamp(ridge, -0.6, 0.6) * thickness * 0.55);

  // Idea 3: canvas weave. Where the paint is thin (stylised but flat), the
  // over/under texture of the linen shows through the film.
  let gp = vec2<f32>(global_id.xy);
  let warp = abs(sin(gp.x * 1.2566));
  let weft = abs(sin(gp.y * 1.2566));
  let over = step(0.5, fract((floor(gp.x / 2.5) + floor(gp.y / 2.5)) * 0.5));
  let weave = mix(warp, weft, over);
  let thinPaint = (1.0 - thickness) * stylization;
  finalRGB = finalRGB * (1.0 - (1.0 - weave) * 0.10 * thinPaint);
  // ── Idea 5: stroke-edge pigment pooling ───────────────────────────────────
  // Wet paint settles and darkens where one patch ends and the next begins. The sector weights
  // already say how decisively one sector won: (wmax - wmin) / wmax is 0 in flat or uniformly
  // busy areas and 1 where a patch boundary splits the sectors. Scaled by stylisation, so the
  // photo-real region around the pointer is untouched.
  // A single speck of noise also makes one sector "decisive", so the weight spread alone is gated
  // by the tonal spread of the sector means: a speck barely moves a mean, a real boundary does.
  let sectorSpread = max(max(sectorLuma[0], sectorLuma[1]), max(sectorLuma[2], sectorLuma[3]))
                   - min(min(sectorLuma[0], sectorLuma[1]), min(sectorLuma[2], sectorLuma[3]));
  let strokeEdge = smoothstep(0.5, 1.0, (weightMax - weightMin) / max(weightMax, 1e-4)) * smoothstep(0.05, 0.18, sectorSpread);
  finalRGB = finalRGB * (1.0 - 0.2 * strokeEdge * stylization);
  finalRGB = mix(finalRGB, finalRGB * slick * 1.18, 0.14 + wetRunner * 0.2);
  finalRGB += slick * (packets * 0.12 + clickClarity * 0.22);
  finalRGB = aces(max(finalRGB, vec3<f32>(0.0)) * 0.8);
  finalRGB = mix(finalRGB, prev.rgb, 0.14 * (0.4 + wetRunner));

  let alpha = clamp(baseSample.a * 0.5 + stylization * 0.4 + (1.0 - mouseFactor) * 0.2 + bass * 0.1, 0.0, 1.0);
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let outCol = vec4<f32>(finalRGB, alpha);
  textureStore(writeTexture, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, outCol);
}
