// ═══════════════════════════════════════════════════════════════════
//  digital-lens-prismatic — Digital Prismatic Lens & Hex Quantization
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba,
//            cauchy-dispersion, hex-grid, iridescent-rim, semantic-alpha, ACES
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: natural cos⁴ lens vignetting (§12.2A: the disc gets a lens-body falloff, 69 % at the aperture); lens-flare ghost chain (§12.2F: two minified secondary images (upright ×0.62, inverted ×0.5) of the scene's bright parts sampled at block centres through the optical axis = the cursor, coating-tinted, strongest toward the aperture, stretched horizontally by the held squeeze like an anamorphic lens); dispersive aperture edge (each colour channel's blend radius follows its own Cauchy index, so the lens silhouette itself carries a rainbow fringe that widens with the CauchyB slider). Rescued: the 6-band spectral rebuild was not colour-neutral (red gain 3.2 vs green 0.6: teal turned salmon) → exact inverse of the file's own band matrix; the cursor spring lived in the zeroed extraBuffer (lens centre raw / (0,0) / racy) → A-texel spring; the 7 % C ghost was tone-mapped twice and flashed white on an inherited C → ACES first, clamped display-space mix.
//  A packing: ACES display RGBA (7 % C ghost mixed in display space). Texels (0,0) = (cursor.xy, cursor vel.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (top-left corner); the C read of those texels is masked.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=BlockSize, y=Radius, z=GridOpacity, w=CauchyB

const SENT: f32 = 0.7371;

// Inverse of M = Σᵢ exp(−0.8·(6−i)·0.12) · wᵢ·wᵢᵀ for the six band weights wᵢ = wavelengthToRGB(λᵢ) below.
// out = SPECTRAL_INV · Σᵢ absorptionᵢ · wᵢ · (wᵢ · sampleᵢ) returns a uniform colour unchanged (HEAD's gain was
// diag≈(3.2, 0.6, 0.9) with strong cross-talk) while still letting per-band offsets show as dispersion fringes.
// Recompute if the wavelength list, wavelengthToRGB or the 0.8 glass thickness change.
const SPECTRAL_INV = mat3x3<f32>(
  vec3<f32>( 0.333840, -0.191648, -0.027340),
  vec3<f32>(-0.191648,  1.804051, -0.209108),
  vec3<f32>(-0.027340, -0.209108,  1.106281)
);

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
  let lambdaUm = wavelengthNm * 0.001;
  return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn refractThroughSurface(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32, squeeze: f32) -> vec2<f32> {
  let toCenter = (uv - center) * vec2<f32>(1.0, 1.0 + squeeze * 0.3);
  let dist = length(toCenter);
  let lensStrength = curvature * 0.45;
  let offset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + dist * 2.2);
  return uv + offset;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hexEdge(uv: vec2<f32>, scale: f32) -> f32 {
  let p = uv * scale;
  let q = vec2<f32>(p.x * 1.7320508 + p.y, p.y * 2.0);
  let pf = fract(q);
  let d1 = length(pf - vec2<f32>(0.5, 0.5));
  let d2 = length(pf - vec2<f32>(0.0, 1.0));
  return 1.0 - smoothstep(0.01, 0.06, min(d1, d2));
}

// One ghost tap: the BRIGHT part of the scene at `g` (a secondary image formed by internal lens reflections).
fn ghostTap(g: vec2<f32>, tint: vec3<f32>) -> vec3<f32> {
  let inFrame = select(0.0, 1.0, all(g > vec2<f32>(0.0)) && all(g < vec2<f32>(1.0)));
  let s = textureSampleLevel(readTexture, u_sampler, clamp(g, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let l = dot(s, vec3<f32>(0.2126, 0.7152, 0.0722));
  return s * tint * smoothstep(0.62, 0.9, l) * inFrame;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let block_size = max(2.0, u.zoom_params.x * 50.0 + 2.0);
  let radius = u.zoom_params.y * 0.42 + 0.05;
  let grid_opacity = u.zoom_params.z;
  let cauchyB = mix(0.01, 0.1, u.zoom_params.w) * (1.0 + treble * 0.35);

  // ── Critically damped spring cursor (HEAD constants: 45 / 13.416), persisted in two A texels ──
  // HEAD kept it in extraBuffer[133..138] — re-uploaded zeroed every frame, written by thread (0,0) only — so the lens
  // centre was raw / (0,0) / racy in the app (minirender's persistent extraBuffer hid it).
  // Texel (0,0) = (cursor.xy, cursor vel.xy), texel (1,0) = (fract(lastTime), 0, 0, SENT).
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  var smoothMouse = select(rawMouse, st0.xy, stateOk);
  var sVel = select(vec2<f32>(0.0), st0.zw, stateOk);
  let springDt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
  sVel = sVel + ((rawMouse - smoothMouse) * 45.0 - sVel * 13.416) * springDt;
  smoothMouse = smoothMouse + sVel * springDt;
  // f16 rest-snap (A is rgba16float on most tiers): settle exactly once near and slow.
  let settled = all(abs(rawMouse - smoothMouse) < vec2<f32>(0.004)) && length(sVel) < 0.06;
  smoothMouse = select(smoothMouse, rawMouse, settled);
  sVel = select(sVel, vec2<f32>(0.0), settled);

  let dist_vec = (uv - smoothMouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dist_vec);
  let squeeze = select(0.0, 0.35, held);
  let mask = 1.0 - smoothstep(radius, radius + 0.06, dist);

  // ── Idea 3: dispersive aperture edge ──
  // Lateral chromatic aberration also sizes the aperture: the red image is a little smaller and the blue a little
  // larger than green, so each channel gets its own blend radius from the file's own Cauchy index (green = HEAD's mask).
  let nG = cauchyIOR(550.0, 1.5, cauchyB);
  let edgeR = radius * (1.0 + 0.8 * (cauchyIOR(650.0, 1.5, cauchyB) - nG));
  let edgeB = radius * (1.0 + 0.8 * (cauchyIOR(450.0, 1.5, cauchyB) - nG));
  let maskRGB = vec3<f32>(
    1.0 - smoothstep(edgeR, edgeR + 0.06, dist),
    mask,
    1.0 - smoothstep(edgeB, edgeB + 0.06, dist));

  var ripplePulse = 0.0;
  let uvAspect = uv * vec2<f32>(aspect, 1.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      let rDist = length(uvAspect - rAspect);
      ripplePulse += smoothstep(0.14, 0.0, rDist) * (1.0 - age);
    }
  }

  var color: vec3<f32>;

  if (dist < max(edgeB, radius) + 0.07 || ripplePulse > 0.05) {
    let blocks = resolution / block_size;
    let uv_quantized = floor(uv * blocks) / blocks + (0.5 / blocks);
    let lensCenter = smoothMouse;
    let glassCurvature = 0.85 + mids * 0.15;
    let glassThickness = 0.8;
    let spectralSat = 0.92 + bass * 0.15;

    let WAVELENGTHS = array<f32, 6>(420.0, 470.0, 520.0, 580.0, 630.0, 680.0);
    var spectral = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 6; i = i + 1) {
      let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
      let refractedUV = refractThroughSurface(uv_quantized, lensCenter, ior, glassCurvature, squeeze);
      let wrappedUV = clamp(refractedUV, vec2<f32>(0.0), vec2<f32>(1.0));
      let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
      let absorption = exp(-glassThickness * (6.0 - f32(i)) * 0.12);
      let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;
      spectral += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
    }

    // R2: colour-neutral spectral rebuild (fringes from per-band offsets remain; clamp their small negative lobes).
    // HEAD's 3.2× red gain was tamed by the roll-off below; the neutral rebuild keeps the roll-off, so a make-up gain of
    // 1.18 restores the mid-tone level (flat 0.6 grey: 0.51 → 0.59 before tint/vignette).
    var finalColor = max(SPECTRAL_INV * spectral, vec3<f32>(0.0)) * 1.18;
    finalColor = finalColor / (1.0 + finalColor * 0.28);

    // ── Idea 1: natural cos⁴ vignetting (§12.2A) ──
    // I = cos⁴(atan(K·r/R)) = 1 / (1 + (K·r/R)²)², K = 0.45 → 69 % at the aperture edge.
    let fr = min(dist / max(radius, 0.001), 1.15);
    let kf = 0.45 * fr;
    let vig = 1.0 / ((1.0 + kf * kf) * (1.0 + kf * kf));
    finalColor = finalColor * vig;

    let uv_pixel = uv * resolution;
    let grid_x = step(block_size - 1.0, uv_pixel.x % block_size);
    let grid_y = step(block_size - 1.0, uv_pixel.y % block_size);
    let grid_line = max(grid_x, grid_y);
    let hex = hexEdge(uv, 18.0 + block_size);

    var lens_color = vec4<f32>(finalColor, 1.0);
    // Digital-green tint, same hue as HEAD. HEAD mixed it at 0.35 against a spectral rebuild whose red gain was 3.2×
    // (the two roughly cancelled into a warm salmon); with the rebuild neutral the same 0.35 turns the lens into a green
    // phosphor, so the mix is 0.10.
    let tint = vec3<f32>(0.15, 1.0, 0.55);
    lens_color = vec4<f32>(mix(lens_color.rgb, lens_color.rgb * tint * 1.4, 0.10), lens_color.a);

    // ── Idea 2: lens-flare ghost chain (§12.2F) ──
    // Internal reflections throw secondary images of the BRIGHT parts of the scene (anywhere in frame) back through the
    // glass along the optical axis (the cursor): a minified upright copy (×0.62) and a minified inverted copy (×0.5),
    // sampled at block centres so they stay in the lens' pixel grid, coating-tinted, strongest toward the aperture;
    // the held squeeze stretches them horizontally (anamorphic).
    let sx = 1.0 + squeeze * 1.2;
    let gA = lensCenter + (lensCenter - uv_quantized) * vec2<f32>(-1.6 / sx, -1.6);
    let gB = lensCenter + (lensCenter - uv_quantized) * vec2<f32>(2.0 / sx, 2.0);
    let ghostW = smoothstep(0.1, 0.85, fr) * 0.85 * (1.0 + treble * 0.5);
    let ghosts = ghostTap(gA, vec3<f32>(1.0, 0.45, 0.9)) + ghostTap(gB, vec3<f32>(0.35, 0.9, 1.0));
    lens_color = vec4<f32>(lens_color.rgb + ghosts * ghostW, lens_color.a);

    lens_color = mix(lens_color, vec4<f32>(0.0, 0.0, 0.0, 1.0), grid_line * grid_opacity);
    lens_color = mix(lens_color, vec4<f32>(wavelengthToRGB(520.0 + sin(time + dist * 8.0) * 80.0), 1.0), hex * 0.25);

    let rim = smoothstep(radius * 0.85, radius, dist) * (1.0 - mask);
    lens_color = vec4<f32>(lens_color.rgb + wavelengthToRGB(580.0 + treble * 60.0) * rim * 0.6, lens_color.a);

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let blendMask = clamp(maskRGB + vec3<f32>(ripplePulse * 0.4), vec3<f32>(0.0), vec3<f32>(1.0));
    color = mix(original.rgb, lens_color.rgb, blendMask);
  } else {
    color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  }

  // Exact dataTextureC persistence. C holds the previous frame's ACES output (and two state texels), so it is mixed in
  // DISPLAY space after tone-mapping, clamped (and skipped while the state sentinel is invalid, i.e. on the first frame or
  // a direct switch from another shader), instead of being tone-mapped a second time (HEAD flashed white on a poisoned C).
  let isStateTexel = coord.y == 0 && coord.x < 2;
  let prevC = clamp(select(textureLoad(dataTextureC, coord, 0).rgb, vec3<f32>(0.0), isStateTexel), vec3<f32>(0.0), vec3<f32>(1.0));
  let finalRGB = mix(acesToneMap(max(color * (0.96 + bass * 0.06), vec3<f32>(0.0))), prevC, select(0.0, 0.07, stateOk));
  let alpha = clamp(0.55 + mask * 0.35 + ripplePulse * 0.1 + select(0.0, 0.1, held), 0.0, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  var aOut = finalPixel;
  if (global_id.y == 0u && global_id.x == 0u) { aOut = vec4<f32>(smoothMouse, sVel); }
  if (global_id.y == 0u && global_id.x == 1u) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }

  textureStore(writeTexture, coord, finalPixel);
  textureStore(dataTextureA, coord, aOut);

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
