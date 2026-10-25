// ═══════════════════════════════════════════════════════════════════
//  Crystalline Veins
//  Category: generative
//  Features: audio-reactive, temporal-feedback, chromatic-dispersion,
//            fbm-veins, worley-cracks, iq-palette, mineral-growth,
//            mouse-attraction, aces-tonemap
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-07-26 (Batch 17) — HDR tamed with hue-preserving
//            clamp + ACES after accumulation; Worley F2-F1 crack layer
//            shimmering across per-bin FFT; IQ cosine mineral palette
//            driven by the Mineral Shift slider.
//            2026-10-25
//  Ideas: Cauchy dispersion (§12.2F) — R/G/B fringe split by n(λ)=A+B/λ² with a
//         per-mineral index; Airy-disc diffraction sparkles (§12.2F) — treble
//         glints are point sources with rings; Worley grain facets (§12.1 t3) —
//         the F1/nearest-cell the crack pass discarded now shades the host stone
//  A packing: display RGBA (ACES colour, semantic alpha) — C read as colour
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn hash31(p: vec3<f32>) -> f32 {
  let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(h) * 43758.5453123);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pos = p;
  let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * noise2(pos);
    pos = rot * pos * 2.0 + vec2<f32>(100.0);
    a = a * 0.5;
  }
  return v;
}

fn fbmDomainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
  let q = vec2<f32>(
    fbm2(p + vec2<f32>(0.0, 0.0), 3),
    fbm2(p + vec2<f32>(5.2, 1.3), 3)
  );
  let r = vec2<f32>(
    fbm2(p + 3.0 * q + vec2<f32>(1.7 + time * 0.05, 9.2), 3),
    fbm2(p + 3.0 * q + vec2<f32>(8.3, 2.8 + time * 0.03), 3)
  );
  return p + 1.5 * r;
}

// Crack/vein generation using FBM ridges — DO NOT ALTER the ridge formula.
fn veinNoise(p: vec2<f32>, time: f32, density: f32) -> f32 {
  let warped = fbmDomainWarp(p * density, time);
  let n1 = fbm2(warped + vec2<f32>(time * 0.02, 0.0), 5);
  let n2 = fbm2(warped * 1.5 + vec2<f32>(0.0, time * 0.015), 4);
  let ridge1 = 1.0 - abs(n1 - 0.5) * 2.0;
  let ridge2 = 1.0 - abs(n2 - 0.5) * 2.0;
  let combined = max(ridge1 * 0.7, ridge2 * 0.5);
  return pow(combined, 2.5);
}

// Worley (Voronoi) F2-F1: cheap secondary crack generator. Returns
// x = raw F2-F1 distance (thin cell borders map to dark fracture lines),
// y = F1, z = hash of the nearest cell, w = Lambert shade of that grain's facet.
fn worleyCrack(p: vec2<f32>, time: f32) -> vec4<f32> {
  let ip = floor(p);
  let fp = fract(p);
  var f1 = 8.0;
  var f2 = 8.0;
  var id = vec2<f32>(0.0);
  var toFeat = vec2<f32>(0.0);
  for (var j: i32 = -1; j <= 1; j = j + 1) {
    for (var i: i32 = -1; i <= 1; i = i + 1) {
      let g = vec2<f32>(f32(i), f32(j));
      let o = hash22(ip + g);
      // Slow drift of feature points so cracks creep like cooling stone.
      let wob = 0.5 + 0.35 * sin(time * 0.4 + 6.2831 * o);
      let dv = g + wob - fp;
      let d = length(dv);
      if (d < f1) {
        f2 = f1;
        f1 = d;
        id = ip + g;
        toFeat = dv;
      } else if (d < f2) {
        f2 = d;
      }
    }
  }
  // Idea 3 (facet): each grain is a tilted crystal face leaning toward its own
  // feature point; shade it against a fixed raking light.
  let nrm = normalize(vec3<f32>(-toFeat * 0.9, 1.0));
  let facet = dot(nrm, normalize(vec3<f32>(-0.5, 0.6, 0.62)));
  return vec4<f32>(f2 - f1, f1, hash21(id), facet);
}

// Cauchy n(λ) = 1 + B/λ² at 650/550/450 nm (λ in µm), relative to green.
fn cauchyScale(b: f32) -> vec3<f32> {
  let lam = vec3<f32>(0.650, 0.550, 0.450);
  let n = vec3<f32>(1.0) + b / (lam * lam);
  return n / n.y;
}

// Airy pattern (2·J1(x)/x)². The small-x series alone is only good to x≈3, so
// blend into the large-x asymptotic form to carry the first diffraction rings.
fn airyDisc(x: f32) -> f32 {
  let xs = max(abs(x), 1e-3);
  let x2 = xs * xs;
  let jSeries = xs * (0.5 - x2 * (0.0625 - x2 * (0.0026042 - x2 * 0.0000543)));
  let chi = xs - 2.35619449;
  let jAsym = sqrt(0.63661977 / xs) * (cos(chi) - 0.375 / xs * sin(chi));
  let j1 = mix(jSeries, jAsym, smoothstep(2.4, 3.4, xs));
  let v = 2.0 * j1 / xs;
  return v * v;
}

// IQ cosine palette: a + b*cos(2π(c·t + d)). The Mineral Shift slider
// sweeps t; constants are tuned so t≈0 lands on the legacy gold look.
fn mineralPalette(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.62, 0.48, 0.32);
  let b = vec3<f32>(0.42, 0.36, 0.30);
  let c = vec3<f32>(1.00, 1.00, 1.00);
  let d = vec3<f32>(0.00, 0.10, 0.22);
  return a + b * cos(6.28318 * (c * t + d));
}

// Hue-preserving highlight clamp: scales the whole RGB triplet down when
// the brightest channel exceeds maxV, keeping mineral hues intact.
fn huePreserveClamp(col: vec3<f32>, maxV: f32) -> vec3<f32> {
  let peak = max(col.r, max(col.g, col.b));
  if (peak > maxV) {
    return col * (maxV / peak);
  }
  return col;
}

// ACES fitted tonemap (Narkowicz). Applied AFTER accumulation/feedback.
fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
  let num = x * (2.51 * x + vec3<f32>(0.03, 0.03, 0.03));
  let den = x * (2.43 * x + vec3<f32>(0.59, 0.59, 0.59)) + vec3<f32>(0.14, 0.14, 0.14);
  return clamp(num / den, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);

  // Slider wiring (zoom_params contract: x=density, y=glow, z=growth, w=mineral)
  let veinDensity = mix(1.5, 5.0, u.zoom_params.x);
  let glowIntensity = u.zoom_params.y;
  let growthSpeed = u.zoom_params.z;
  let mineralShift = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = uv * vec2<f32>(aspect, 1.0);

  // Mouse attracts vein growth
  let mouseUV = mouse * 0.5 + 0.5;
  let mouseUVAspect = mouseUV * vec2<f32>(aspect, 1.0);
  let mouseDist = length(p - mouseUVAspect);
  let mouseAttraction = exp(-mouseDist * mouseDist * 4.0) * 0.6;

  // Growth phase evolves over time, modulated by growthSpeed
  let growthPhase = fract(time * 0.03 * (0.5 + growthSpeed * 1.5));
  // HEAD fix: ease the cycle out as well as in so the veins retract instead of popping at the wrap.
  let growthMask = smoothstep(0.0, 0.4, growthPhase) * (1.0 - smoothstep(0.9, 1.0, growthPhase));

  // Base vein pattern
  let veins = veinNoise(p, time, veinDensity);
  // HEAD fix: the radial pull used normalize(), a direction singularity at the pointer
  // (starburst at the idle 0.5,0.5 cursor); the pull now fades to zero at the pointer.
  let attractedVeins = veinNoise(p + (p - mouseUVAspect) * (0.5 * mouseAttraction / (mouseDist + 0.15)), time, veinDensity);
  let mixedVeins = mix(veins, attractedVeins, mouseAttraction * 2.0);

  // Worley crack complement: fine fracture web between the main veins.
  // Per-bin FFT (plasmaBuffer[1..8]) shimmers the crack width per cell.
  // HEAD fix: the per-cell id was a square grid (blocky mosaic of flat colours);
  // the nearest Worley grain gives the same "one mineral per cell" with organic borders.
  let crackScale = veinDensity * 2.5;
  let grain = worleyCrack(p * crackScale + vec2<f32>(time * 0.01, 0.0), time);
  let crackRaw = grain.x;
  let binIndex = 1u + u32(fract(grain.z * 7.31) * 7.999) % 8u;
  let binFFT = plasmaBuffer[binIndex].x;
  let crackWidth = 0.04 + binFFT * 0.10;
  let crackLine = 1.0 - smoothstep(0.0, crackWidth, crackRaw);
  let crackVein = pow(crackLine, 2.0) * (0.4 + binFFT * 0.8);

  // Growth threshold: veins "grow" over time
  // HEAD fix: veinNoise peaks (~0.4) ON the ridges, but the mask selected the low
  // plateaus, flooding the frame. Veins now live on the ridges and widen as the
  // threshold falls over the growth cycle.
  let growthThreshold = 0.38 - growthMask * 0.07;
  let veinMask = smoothstep(growthThreshold, growthThreshold + 0.04, mixedVeins);
  let thinVeins = smoothstep(growthThreshold - 0.05, growthThreshold, mixedVeins) * (1.0 - veinMask);
  let crackMask = crackVein * (1.0 - veinMask) * growthMask;

  // Bass drives vein pulse
  let pulse = 1.0 + bass * sin(time * 4.0 + mixedVeins * 20.0) * 0.4;

  // Mids control growth density via secondary pattern
  let densityPattern = fbm2(p * 3.0 + vec2<f32>(time * 0.01), 4);
  let densityMod = 1.0 + mids * densityPattern;

  // Mineral palette: IQ cosine palette swept by the Mineral Shift slider.
  // t≈cellHash alone stays close to the legacy gold; the slider rotates
  // the hue through copper, silver and rarer mineral bands.
  let mineralT = fract(grain.z * 0.65 + mineralShift);
  let mineralColor = mineralPalette(mineralT);
  let crackColor = mineralPalette(fract(mineralT + 0.13));

  // Chromatic dispersion: R/G/B offsets for each mineral type
  // Idea 1 (Cauchy dispersion, §12.2F): the fringe axis is still set by the
  // mineral, but R/G/B now separate by the non-linear n(λ) = A + B/λ² instead of
  // three arbitrary offsets; denser mineral bands (higher B) split more.
  // Green is the reference ray, so it sits on the un-shifted vein field.
  let caStrength = 0.012 * (1.0 + treble);
  let dispDir = vec2<f32>(sin(mineralT * 6.28), cos(mineralT * 6.28));
  let disp = (cauchyScale(0.02 + 0.04 * mineralT) - vec3<f32>(1.0)) * 20.0;
  let rOffset = dispDir * (caStrength * disp.x);
  let bOffset = dispDir * (caStrength * disp.z);

  let veinR = veinNoise(p + rOffset, time, veinDensity);
  let veinG = veins;
  let veinB = veinNoise(p + bOffset, time, veinDensity);

  let maskR = smoothstep(growthThreshold, growthThreshold + 0.04, veinR) * densityMod;
  let maskG = smoothstep(growthThreshold, growthThreshold + 0.04, veinG) * densityMod;
  let maskB = smoothstep(growthThreshold, growthThreshold + 0.04, veinB) * densityMod;

  let chromaVein = vec3<f32>(maskR, maskG, maskB) * mineralColor * pulse;

  // Dark stone background
  let stoneNoise = fbm2(p * 6.0, 5);
  // Idea 3: host-rock grains (nearest Worley cell) get a facet shade and a
  // per-grain tone; grain rims (large F1) fall darker, like interlocking crystals.
  let grainTone = (0.85 + 0.3 * grain.z) * (0.75 + 0.5 * clamp(grain.w, 0.0, 1.0)) * (1.0 - 0.25 * smoothstep(0.35, 0.8, grain.y));
  let stoneColor = vec3<f32>(0.06, 0.055, 0.05) * (0.8 + stoneNoise * 0.4) * grainTone;

  // Vein glow halo
  let glow = smoothstep(growthThreshold - 0.09, growthThreshold + 0.02, mixedVeins) * glowIntensity * (0.3 + bass * 0.4);
  let glowColor = mineralColor * glow;

  // Treble adds crystalline sparkles
  // Idea 2 (Airy disc, §12.2F): each glint is a point source seen through a
  // circular aperture — bright core plus a faint first diffraction ring —
  // instead of a square cell flash. Same cell hash, same treble gating.
  let sparkCell = p * veinDensity * 4.0;
  let sparkleNoise = hash31(vec3<f32>(floor(sparkCell), fract(time * 12.0)));
  let sparkPt = (hash22(floor(sparkCell) + vec2<f32>(7.0, 3.0)) - vec2<f32>(0.5)) * 0.4;
  let airyCore = airyDisc(length(fract(sparkCell) - vec2<f32>(0.5) - sparkPt) * 14.0);
  let airyShape = mix(airyCore, sqrt(airyCore), 0.5);
  let sparkle = step(1.0 - 0.08 * treble, sparkleNoise) * airyShape * veinMask * treble * 2.5;
  let sparkleColor = vec3<f32>(1.0, 0.98, 0.95) * sparkle;

  // Thin vein filaments + Worley crack ore seams
  let filamentColor = mineralColor * thinVeins * 0.4 * pulse;
  let crackOreColor = crackColor * crackMask * 0.55 * (0.6 + bass * 0.4);

  var color = stoneColor + chromaVein + glowColor + sparkleColor + filamentColor + crackOreColor;

  // Temporal feedback: trailing glow from previous frame
  let feedbackColor = prev.rgb * 0.85;
  let feedbackMask = smoothstep(0.1, 0.5, prev.a) * 0.3;
  color = mix(color, feedbackColor + glowColor * 0.5, feedbackMask);

  // ── HDR taming (AFTER accumulation/feedback, never inside it) ──
  // 1) Hue-preserving clamp at ~1.2 stops stacked sparkle/pulse blowout.
  // 2) ACES tonemap rolls highlights off smoothly instead of clipping.
  color = huePreserveClamp(color, 1.2);
  color = acesTonemap(color);

  // Semantic alpha: based on vein presence + glow + sparkles + cracks
  let alpha = clamp(veinMask * 0.9 + glow * 0.5 + sparkle * 0.4 + thinVeins * 0.3 + crackMask * 0.25, 0.0, 1.0);

  let depthVal = veinMask * 0.6 + glow * 0.3 + sparkle * 0.2 + crackMask * 0.15;

  // Click = nucleation front: a ring of fresh ore light in the mineral's own colour.
  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  let screenUV = vec2<f32>(vec2<i32>(global_id.xy)) / res;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = max(time - event.z, 0.0);
    clickFront += exp(-age * 1.8) * exp(-abs(length((screenUV - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
  }

  let finalRGB = color + crackColor * (clickFront * 0.25);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalRGB, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
