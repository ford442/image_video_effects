// ═══════════════════════════════════════════════════════════════════
//  Chromatic Focus — Visualist Enhanced Edition
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba,
//            chromatic-aberration, oklab-mixing, split-tone,
//            aces-tone-map, volumetric-haze, iridescent-halo
//  Complexity: High
//  Chunks From: chromatic-focus
//  Created: 2026-05-31
//  Upgraded: 2026-10-05
//  Ideas: highlight bokeh discs with rim ring; cat's-eye vignetting; bokeh fringing (longitudinal CA)
//  A packing: mask (focusMask, blurMask, spectralSpread*40, alpha) — no reader
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=ApertureSize, y=FocusRadius, z=SpectralSpread, w=AnimationSpeed

// ── Color Science ─────────────────────────────────────────────────

// Inigo Quilez cosine palette
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

// OkLab color space
fn srgbToLinear(c: vec3<f32>) -> vec3<f32> {
  return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn linearToSrgb(c: vec3<f32>) -> vec3<f32> {
  return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

fn linearToOkLab(c: vec3<f32>) -> vec3<f32> {
  let lms = mat3x3<f32>(
    0.8189330101, 0.3618667424, -0.1288597137,
    0.0329845436, 0.9293118715, 0.0361456387,
    0.0482003018, 0.2643662691, 0.6338517070
  ) * c;
  let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0 / 3.0));
  return mat3x3<f32>(
    0.2104542553, 0.7936177850, -0.0040720468,
    1.9779984951, -2.4285922050, 0.4505937099,
    0.0259040371, 0.7827717662, -0.8086757660
  ) * lms_;
}

fn okLabToLinear(c: vec3<f32>) -> vec3<f32> {
  let lms_ = mat3x3<f32>(
    1.0, 0.3963377774, 0.2158037573,
    1.0, -0.1055613458, -0.0638541728,
    1.0, -0.0894841775, -1.2914855480
  ) * c;
  let lms = lms_ * lms_ * lms_;
  return mat3x3<f32>(
    4.0767416621, -3.3077115913, 0.2309699292,
    -1.2684380046, 2.6097574011, -0.3413193965,
    -0.0041960863, -0.7034186147, 1.7076147010
  ) * lms;
}

fn okLabMix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  let la = linearToOkLab(srgbToLinear(a));
  let lb = linearToOkLab(srgbToLinear(b));
  return linearToSrgb(okLabToLinear(mix(la, lb, t)));
}

// ACES filmic tone mapping
fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return (x * (a * x + b)) / (x * (c * x + d) + e);
}

// Hue-preserving clamp
fn huePreserveClamp(c: vec3<f32>) -> vec3<f32> {
  let maxc = max(max(c.r, c.g), c.b);
  if (maxc > 1.0) {
    return c / maxc;
  }
  return c;
}

// IGN blue-noise dither
fn ignDither(p: vec2<f32>, t: f32) -> f32 {
  let fp = fract(p + t * 0.07);
  return fract(52.9829189 * fract(0.06711056 * fp.x + 0.00583715 * fp.y));
}

// ── Atmosphere ────────────────────────────────────────────────────

// Mie scattering for haze
fn mieScattering(cosTheta: f32, g: f32) -> f32 {
  let g2 = g * g;
  return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
}

// Iridescent thin-film
fn iridescent(dist: f32, freq: f32, hueOffset: f32, fresnel: f32) -> vec3<f32> {
  let phase = dist * freq + hueOffset;
  return vec3<f32>(
    0.5 + 0.5 * sin(phase),
    0.5 + 0.5 * sin(phase + 2.094),
    0.5 + 0.5 * sin(phase + 4.188)
  ) * fresnel;
}

fn sampleColor(uv: vec2<f32>) -> vec3<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let time = u.config.x;

  let aperture = mix(0.002, 0.028, u.zoom_params.x);
  let focusRadius = mix(0.05, 0.42, u.zoom_params.y) + bass * 0.035;
  let spectralSpread = mix(0.001, 0.022, u.zoom_params.z);
  let animSpeed = 0.1 + u.zoom_params.w * 2.8;

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let focusMask = 1.0 - smoothstep(focusRadius, focusRadius + 0.12, dist);
  let blurMask = 1.0 - focusMask;
  let t = time * animSpeed;

  // Idea 2: Cat's-eye vignetting — off-axis the aperture is clipped by a second
  // circle displaced toward the frame centre in proportion to the pixel's
  // distance from it; taps outside that circle are rejected, so bokeh near the
  // frame edges turns into cat's-eye lenses (on-axis every tap survives).
  let catShift = (vec2<f32>(0.5) - uv) * 0.8;

  // Rotating blur samples — HEAD's 6-tap ring (aperture coord 0.667, same
  // radius as HEAD) plus
  // Idea 1: Highlight bokeh discs — every tap is weighted by luma^4 so bright
  // highlights dominate and bloom into discs, and a second rim ring of 6 taps
  // sits at the aperture edge (coord 1.0) with rim brightening (soap-bubble).
  let blurRadius = aperture * (1.0 + blurMask * 2.0);
  let angleStep = 6.28318 / 6.0;
  var coreAccum = vec3<f32>(0.0);
  var coreWeight = 0.0;
  var rimAccum = vec3<f32>(0.0);
  var rimWeight = 0.0;
  for (var i = 0; i < 12; i = i + 1) {
    let isRim = i >= 6;
    let ringCoord = select(0.667, 1.0, isRim);
    let angle = f32(i % 6) * angleStep + t * 0.7 + select(0.0, angleStep * 0.5, isRim);
    let dir = vec2<f32>(cos(angle), sin(angle));
    let c = sampleColor(uv + dir * blurRadius * ringCoord * 1.5);
    let tapLuma = dot(c, vec3<f32>(0.299, 0.587, 0.114));
    // Idea 1: highlight weighting (~1 for mid-tones, up to 7 for highlights)
    var w = 1.0 + 6.0 * pow(clamp(tapLuma, 0.0, 1.0), 4.0) * blurMask;
    // Idea 2: cat's-eye clip (soft edge so the rotating taps do not pop)
    w = w * (1.0 - smoothstep(1.0, 1.2, length(dir * ringCoord - catShift)));
    if (isRim) {
      // Idea 1: rim brightening — the aperture edge carries more energy
      w = w * (1.0 + 0.35 * blurMask);
      rimAccum = rimAccum + c * w;
      rimWeight = rimWeight + w;
    } else {
      coreAccum = coreAccum + c * w;
      coreWeight = coreWeight + w;
    }
  }
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let totalWeight = coreWeight + rimWeight;
  var softColor = select(source.rgb, (coreAccum + rimAccum) / max(totalWeight, 1e-4), totalWeight > 1e-3);

  // Idea 3: Bokeh fringing (longitudinal CA) — the focus plane is the depth
  // under the cursor. Where the bokeh rim sees different content than its core
  // (the disc's edge), out-of-focus pixels nearer than the focus plane
  // (depth 1 = near) get a magenta rim, farther ones a green rim. Flat depth
  // reads as "behind the focus plane" (background bokeh) at reduced strength.
  let pixDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let focusDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(mouse, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let defocus = pixDepth - focusDepth;
  let fringeAmt = clamp(0.35 + abs(defocus) * 3.0, 0.0, 1.0) * blurMask;
  let coreAvg = coreAccum / max(coreWeight, 1e-4);
  let rimAvg = rimAccum / max(rimWeight, 1e-4);
  let rimEdge = abs(dot(rimAvg - coreAvg, vec3<f32>(0.299, 0.587, 0.114))) * step(1e-3, min(coreWeight, rimWeight));
  // luminance-neutral fringe directions: magenta (near) / green (far)
  let fringeDir = select(vec3<f32>(-0.4, 0.3, -0.4), vec3<f32>(0.6, -0.4, 0.6), defocus > 0.0);
  softColor = max(softColor + fringeDir * rimEdge * fringeAmt * 3.0, vec3<f32>(0.0));

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Enhanced chromatic aberration via dispersion
  // ═══════════════════════════════════════════════════════════════
  let dispersionDir = normalize(centered + vec2<f32>(0.001, 0.0));
  // Wavelength-dependent offsets (R > G > B for dispersion)
  let rOffset = dispersionDir * spectralSpread * blurMask * (1.0 + treble * 0.7) * 1.2;
  let gOffset = dispersionDir * spectralSpread * blurMask * (1.0 + mids * 0.5) * 0.8;
  let bOffset = dispersionDir * spectralSpread * blurMask * (1.0 + bass * 0.3) * 0.6;

  let chromaColor = vec3<f32>(
    sampleColor(uv + rOffset).r,
    sampleColor(uv + gOffset).g,
    sampleColor(uv - bOffset).b
  );

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Cosine palette for dynamic halo color cycling
  // ═══════════════════════════════════════════════════════════════
  let paletteT = t * 0.2 + dist * 3.0 + bass * 1.5;
  let haloBase = palette(paletteT,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(0.00, 0.33, 0.67)
  );
  // Secondary palette for richer variation
  let haloShift = palette(paletteT + 0.5 + mids,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5 + treble * 0.2, 0.5, 0.5 + bass * 0.2),
    vec3<f32>(1.0, 0.9, 0.7),
    vec3<f32>(0.25, 0.50, 0.75)
  );
  let haloColor = okLabMix(haloBase, haloShift, 0.5 + sin(t) * 0.3);

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Iridescent thin-film on blur edges
  // ═══════════════════════════════════════════════════════════════
  let fresnel = pow(blurMask, 2.0) * (0.3 + treble * 0.4);
  let iridColor = iridescent(dist, 25.0, t * 1.5, fresnel);

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Mie scattering haze
  // ═══════════════════════════════════════════════════════════════
  let viewDir = centered / max(dist, 1e-4);
  let lightDir = normalize(vec2<f32>(cos(t * 0.3), sin(t * 0.3)));
  let cosTheta = dot(viewDir, lightDir);
  let haze = mieScattering(cosTheta, 0.7) * blurMask * 0.08 * (1.0 + mids * 0.5);
  let hazeColor = vec3<f32>(0.85, 0.80, 0.75) * haze;

  // Compose
  var finalColor = mix(softColor, source.rgb, focusMask);
  finalColor = mix(finalColor, chromaColor, blurMask * 0.55);
  finalColor = finalColor + haloColor * blurMask * (0.05 + mids * 0.16);
  finalColor = finalColor + iridColor * blurMask * 0.4;
  finalColor = finalColor + hazeColor;

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Split-tone — shadows cool, highlights warm
  // ═══════════════════════════════════════════════════════════════
  let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let shadowTint = vec3<f32>(0.12, 0.22, 0.42); // cool indigo shadows
  let highlightTint = vec3<f32>(0.95, 0.70, 0.35); // warm amber highlights
  finalColor = okLabMix(finalColor, shadowTint, (1.0 - luma) * 0.2 * blurMask);
  finalColor = okLabMix(finalColor, highlightTint, smoothstep(0.4, 0.9, luma) * 0.15 * blurMask);

  // HDR workflow
  finalColor = finalColor * (1.0 + treble * 0.3);

  // Hue-preserving clamp before ACES
  finalColor = huePreserveClamp(max(finalColor, vec3<f32>(0.0)));

  // ACES filmic tone mapping
  finalColor = aces(finalColor);

  // IGN dither
  let dither = ignDither(vec2<f32>(gid.xy), time) * 0.0039;
  finalColor = finalColor + vec3<f32>(dither);

  // Bloom-based alpha
  let bloomAlpha = pow(max(0.0, luma - 0.6), 2.0) * 3.0;
  let finalAlpha = clamp(mix(source.a, 0.72 + blurMask * 0.18, blurMask) + bloomAlpha * 0.1, 0.06, 0.98);

  let outDepth = clamp(mix(pixDepth, 0.20 + blurMask * 0.65, 0.24), 0.0, 1.0);

  // Premultiplied alpha writeback
  let out = vec4<f32>(finalColor * finalAlpha, finalAlpha);

  textureStore(writeTexture, vec2<i32>(gid.xy), out);
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(focusMask, blurMask, spectralSpread * 40.0, finalAlpha));
}
