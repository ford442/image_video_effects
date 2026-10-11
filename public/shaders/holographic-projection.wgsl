// ═══════════════════════════════════════════════════════════════════
//  Holo Projector — Premium Volumetric Hologram
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal,
//            holographic-scan, laser-speckle, bragg-colour, refresh-persistence, ACES
//  Ideas:    1. object-locked laser speckle — stable grains in image space that boil slowly
//               and slide with depth parallax as the viewer (cursor) moves
//            2. Bragg colour shift — the reconstructed wavelength drifts across the plate
//               with viewing angle, rainbow-hologram style (replaces the cosine palette)
//            3. rolling refresh band — freshly redrawn rows are crisp, older rows persist
//               as display-space ghosts
//  Complexity: High
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Smooth visible-spectrum approximation (400–700 nm), normalised so the
// laser lines read as saturated but not dim.
fn wavelengthRGB(lambda: f32) -> vec3<f32> {
  let x = clamp((lambda - 400.0) / 300.0, 0.0, 1.0);
  let r = smoothstep(0.45, 0.75, x) + smoothstep(0.15, 0.0, x) * 0.35;
  let g = 1.0 - smoothstep(0.0, 0.35, abs(x - 0.5));
  let b = 1.0 - smoothstep(0.1, 0.5, x);
  return vec3<f32>(r, g, b) * 0.85 + vec3<f32>(0.12);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  // Sliders
  let scanSpeed = u.zoom_params.x * 2.0 + 0.5;
  let glitchAmt = u.zoom_params.y;
  let holoHue = u.zoom_params.z;
  let focusStrength = u.zoom_params.w;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Raw pointer: the old extraBuffer[133..138] spring raced (pixel (0,0) wrote
  // while every other pixel read) and the buffer is re-uploaded each frame.
  let mouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Exact previous frame from dataTextureC
  let prev = textureLoad(dataTextureC, pixel, 0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Aspect-corrected mouse distance & focus
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let focusRegion = (1.0 - smoothstep(0.0, 0.45, mouseDist)) * focusStrength * (0.6 + held * 0.4);

  // Scanline raster & Bessel interference fringe
  let scanPhase = fract(uv.y * (160.0 + bass * 30.0) - time * scanSpeed * (1.0 + bass * 0.4));
  let scanLine = smoothstep(0.03, 0.0, abs(scanPhase - 0.5)) * 0.45;
  let refreshWave = sin(uv.y * 35.0 - time * (scanSpeed * 1.5) + mids * 2.0);

  // Glitch displacement & chromatic splitting
  let glitchBlock = hash12(floor(uv * vec2<f32>(30.0, 8.0)) + floor(time * (4.0 + glitchAmt * 12.0)));
  let glitchActive = step(1.0 - glitchAmt * 0.35 * (1.0 - focusRegion * 0.7), glitchBlock);
  let jitterOffset = (hash12(uv + time) - 0.5) * glitchAmt * (0.015 + treble * 0.02) * glitchActive;

  let rUV = clamp(uv + vec2<f32>(jitterOffset + 0.004 * glitchAmt, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + vec2<f32>(jitterOffset * 0.2, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv - vec2<f32>(jitterOffset + 0.004 * glitchAmt, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let srcR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let srcG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let srcB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
  let holoBase = vec3<f32>(srcR, srcG, srcB);

  // Idea 1: object-locked laser speckle. Coherent light gives a grain that is
  // fixed to the object, not fresh noise each frame. Grains are ~2.5 px in
  // image space; near depth slides them against the cursor (view parallax),
  // and the pattern boils slowly by crossfading two seeds. Intensity follows
  // the exponential speckle law, so most grains are dim and a few sparkle.
  let viewOff = (mouse - vec2<f32>(0.5)) * (0.5 + depth) * 6.0;
  let speckleP = vec2<f32>(global_id.xy) / 2.5 + viewOff;
  let boil = time * (0.6 + treble * 0.8);
  let boilA = valueNoise(speckleP + floor(boil) * 17.3);
  let boilB = valueNoise(speckleP + (floor(boil) + 1.0) * 17.3);
  let speckleH = mix(boilA, boilB, smoothstep(0.0, 1.0, fract(boil)));
  let speckleI = -log(max(1.0 - speckleH, 0.02)) * 1.3;
  let speckleAmt = (0.22 + treble * 0.25) * (1.0 - focusRegion * 0.6);

  let fringeAngle = (uv.x * aspect + uv.y) * 90.0 + refreshWave * 2.5 + mids * 3.0;
  let interference = 0.5 + 0.5 * cos(fringeAngle);

  // Idea 2: Bragg colour shift. A rainbow hologram replays a wavelength that
  // depends on viewing angle, so the colour sweeps across the plate and slides
  // as the eye (cursor) moves. Hue picks the central laser line; depth tilts it.
  let viewVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let lambda0 = 400.0 + fract(0.33 + holoHue) * 300.0;
  let lambda = clamp(lambda0 * (1.0 + viewVec.x * 0.16 - viewVec.y * 0.06 + depth * 0.05), 400.0, 700.0);
  let tint = wavelengthRGB(lambda);
  var color = holoBase * (0.65 + interference * 0.4) + tint * (scanLine * 0.8 + 0.15 * refreshWave);
  color = color * mix(1.0, speckleI, speckleAmt);

  // Focus stabilization & color enrichment
  color = mix(color, holoBase * 1.25 + tint * 0.2, focusRegion);

  // Bounded click ripple excitation
  var clickFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let ringRadius = age * 0.6;
    let ringBand = exp(-abs(rDist - ringRadius) * 45.0) * exp(-age * 1.8);
    clickFlash += ringBand;
  }
  color += tint * (clickFlash * 0.85);

  // Idea 3: rolling refresh band. One bright band rolls down the plate; rows
  // it just redrew are crisp and slightly hot, and rows it passed long ago
  // lean on the previous frame (C holds ACES output, so blend in display space).
  let bandPos = fract(time * scanSpeed * 0.22);
  let sinceBand = fract(bandPos - uv.y);
  let bandGlow = exp(-sinceBand * 40.0) * (1.0 - focusRegion * 0.5);
  color += tint * bandGlow * 0.35;

  // ACES Tonemap
  // Clamp first: the refresh wave and speckle can push dark pixels negative,
  // and this ACES fit maps negatives to bright values.
  let toned = aces(max(color, vec3<f32>(0.0)) * (1.0 + bass * 0.2));
  let persistFactor = mix(mix(0.04, 0.3, sinceBand), 0.04, focusRegion);
  let finalRGB = mix(toned, prev.rgb, persistFactor);

  // Semantic alpha: blend source alpha with emission luminance & depth
  let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(mix(srcA, 0.4 + luma * 0.6, 0.75) + focusRegion * 0.15 + clickFlash * 0.1 + bandGlow * 0.1, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
