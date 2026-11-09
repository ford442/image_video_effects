// ═══════════════════════════════════════════════════════════════════
//  PP Vignette
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06, 2026-09-21, 2026-11-09
//  A packing: pre-tonemap linear RGB + semantic alpha (C history)
//  Motion: mobile anamorphic vignette aperture + exposure ripple blooms
//  Ideas (2026-09-21): cos^4 natural falloff; grain rides the emulsion
//         (midtone response, applied under the vignette)
//  Ideas (2026-11-09): corner cast (blue falls off first -> warm corners);
//         highlight burn-through (bright sources punch through the falloff)
//  Rescues (2026-11-09): (SDR shoulder replaces ACES re-grade; dead
//         extraBuffer spring removed)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=VignetteIntensity, y=GrainIntensity, z=ColorStyle, w=BlendMode

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// HEAD ran the full ACES fit over an SDR photo: whites landed at 0.80 and
// mids were lifted (0.18 -> 0.27), a re-grade on a utility filter. Keep
// SDR identity below 0.8 and roll only overshoot into a soft shoulder.
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let v = max(x, vec3<f32>(0.0));
  let over = max(v - vec3<f32>(0.8), vec3<f32>(0.0));
  return min(v, vec3<f32>(0.8)) + 0.2 * over / (over + vec3<f32>(0.2));
}

fn getLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[2].x;

  // HEAD kept a spring cursor in extraBuffer[133..138]; that range is
  // re-uploaded (zeroed) every frame so it never persisted. Use the cursor.
  let spring = mouse;

  // Four saved controls preserved
  let vignetteIntensity = u.zoom_params.x;
  let grainIntensity = u.zoom_params.y;
  let colorStyle = u.zoom_params.z;
  let blendMode = u.zoom_params.w;

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFade = mix(0.7, 1.3, depth);

  // Optical center blend between screen center (0.5, 0.5) and interactive spring cursor
  let apertureCenter = mix(vec2<f32>(0.5), spring, 0.45);
  let relCoord = (uv - apertureCenter) * aspectVec;
  let dist = length(relCoord);

  // Click ripple exposure blooms
  var rippleBloom = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.4) {
      let d = length((uv - r.xy) * aspectVec);
      let ring = exp(-abs(d - age * 0.44) * 26.0) * exp(-age * 1.4);
      rippleBloom += ring;
    }
  }

  // Falloff calculation with audio breathing
  let breathe = 1.0 - bass * 0.15 + select(0.0, 0.12, held);
  let effectiveFalloff = mix(0.3, 1.8, vignetteIntensity) * breathe;
  // ── Idea 1: cos^4 natural falloff ─────────────────────────────────
  // Real lens vignetting follows the cos^4 law (inverse square x obliquity
  // x pupil foreshortening), not a smoothstep: gentle across most of the
  // frame, accelerating only into the corners. The off-axis angle comes
  // from an effective focal length that shortens as intensity rises — a
  // wide lens vignettes harder — and the law is blended with HEAD's shaped
  // mask so the saved intensity range still lands where presets expect.
  let cosFocal = 1.12 / effectiveFalloff;
  let tanTheta = dist / cosFocal;
  let obliquity = 1.0 + tanTheta * tanTheta;
  let cos4 = 1.0 / (obliquity * obliquity);
  let vigMask = mix(1.0 - smoothstep(0.35 / effectiveFalloff, 0.95 / effectiveFalloff, dist), cos4, 0.55);

  // Sample source texture
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let srcLuma = getLuma(source);

  // Natural triangular film grain
  let g1 = hash12(uv * dims + vec2<f32>(time * 12.0, time * 7.0));
  let g2 = hash12(uv * dims + vec2<f32>(time * 5.0 + 19.3, time * 13.0 + 47.1));
  let triGrain = (g1 + g2 - 1.0) * mix(0.0, 0.14, grainIntensity) * (1.0 + treble * 0.5);

  // Color grading styles
  let sepia = vec3<f32>(
    dot(source, vec3<f32>(0.393, 0.769, 0.189)),
    dot(source, vec3<f32>(0.349, 0.686, 0.168)),
    dot(source, vec3<f32>(0.272, 0.534, 0.131))
  );
  let warmGrade = source * vec3<f32>(1.12, 1.02, 0.86) + vec3<f32>(0.04, 0.02, 0.0);
  let coolGrade = vec3<f32>(source.r * 0.85, source.g * 1.05, source.b * 1.25) + vec3<f32>(0.0, 0.03, 0.06);

  var graded = source;
  if (colorStyle < 0.33) {
    let tStyle = colorStyle / 0.33;
    graded = mix(source, sepia, tStyle);
  } else if (colorStyle < 0.66) {
    let tStyle = (colorStyle - 0.33) / 0.33;
    graded = mix(sepia, warmGrade, tStyle);
  } else {
    let tStyle = (colorStyle - 0.66) / 0.34;
    graded = mix(warmGrade, coolGrade, tStyle);
  }
  graded = mix(graded, graded * (1.0 + mids * 0.25), 0.5);

  // ── Idea 2: grain rides the emulsion ──────────────────────────────
  // Film grain is densest in the lower midtones, thin in deep shadow and
  // nearly absent in the highlights, and it lives IN the emulsion, so the
  // vignette darkens it along with the image. HEAD added a flat grain on
  // top of the finished vignette, which made corners look noisier than the
  // centre. Weighted by a midtone response and applied before the blend.
  let grainResponse = smoothstep(0.0, 0.22, srcLuma) * (1.0 - smoothstep(0.55, 0.98, srcLuma));
  graded = graded + vec3<f32>(triGrain * mix(0.35, 1.25, grainResponse));

  // Blend modes for the vignette
  var vignetted = graded;
  if (blendMode < 0.5) {
    // Standard photographic falloff
    let tBlend = blendMode / 0.5;
    let standardVig = graded * vigMask;
    let darkFog = mix(graded * vigMask, vec3<f32>(0.02, 0.02, 0.03), (1.0 - vigMask) * 0.85);
    vignetted = mix(standardVig, darkFog, tBlend);
  } else {
    // Bleach bypass / high-contrast edge crush
    let tBlend = (blendMode - 0.5) / 0.5;
    let darkFog = mix(graded * vigMask, vec3<f32>(0.02, 0.02, 0.03), (1.0 - vigMask) * 0.85);
    let bleach = mix(graded, vec3<f32>(srcLuma), 0.4) * (vigMask * 1.2 + 0.1);
    vignetted = mix(darkFog, bleach, tBlend);
  }

  // ── Idea 3: corner cast ───────────────────────────────────────────
  // Real glass loses short wavelengths faster off-axis, so a vignette is
  // never neutral: the falloff warms slightly toward the corners. The
  // darkening is applied per channel with blue falling hardest.
  let fall = 1.0 - vigMask;
  vignetted = vignetted * (vec3<f32>(1.0) - fall * vec3<f32>(-0.02, 0.04, 0.12) * vignetteIntensity);

  // ── Idea 4: highlight burn-through ────────────────────────────────
  // A strong light source in the corner of a frame still exposes through
  // the falloff — a lamp in a vignetted corner stays a lamp. Bright source
  // pixels recover part of what the vignette took.
  let burn = smoothstep(0.7, 1.0, srcLuma) * fall * 0.6;
  vignetted = mix(vignetted, graded, burn);

  // Inject grain and ripple flash bloom
  let bloomTint = vec3<f32>(1.0, 0.92, 0.82) * rippleBloom * 0.45;
  var hdr = vignetted + bloomTint;

  // Exact previous frame history load from dataTextureC for temporal anti-strobe
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.04, 0.18, vigMask);
  hdr = mix(hdr, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp(vigMask * depthFade + rippleBloom * 0.2 + 0.2, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, vec4<f32>(hdr, semanticAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * vigMask, 0.0, 1.0), 0.0, 0.0, 0.0));
}
