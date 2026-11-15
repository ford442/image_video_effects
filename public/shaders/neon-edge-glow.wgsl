// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Glow v2
//  Category: visual-effects
//  Features: edge-glow, neon, bloom, gas-discharge, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: neon-edge-glow
//  Upgraded: 2026-09-11, 2026-11-15
//  Ideas: tube core + dark sheath; 60 Hz mains beat; ring-gather spill glow (native); positive-column striations along the tube tangent (native); squared-not-pow line shapes (rescue)
//  A packing: ACES display RGBA
//  By: 4-Agent Shader Upgrade Swarm
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Rescue 1: pow(negative, 2.0) ─────────────────────────────────────
// The emission-line Gaussians used pow((t - centre)/width, 2.0). The base is
// negative for every t below a line's centre and WGSL pow(x<0, y) is undefined
// (NaN on some GPUs), which would black the tube out over much of the hue range.
// A square is the same number where pow was defined, and defined everywhere.
fn sq(x: f32) -> f32 { return x * x; }

fn neonSpectrum(t: f32, flicker: f32) -> vec3<f32> {
  let r = 0.85 * exp(-sq((t - 0.35) / 0.12)) * (1.0 + flicker * 0.3);
  let g = 0.45 * exp(-sq((t - 0.52) / 0.10)) * (1.0 + flicker * 0.15);
  let b = 0.25 * exp(-sq((t - 0.68) / 0.14)) * (1.0 + flicker * 0.1);
  return vec3<f32>(r, g, b);
}

fn mercurySpectrum(t: f32) -> vec3<f32> {
  let r = 0.15 * exp(-sq((t - 0.40) / 0.08));
  let g = 0.55 * exp(-sq((t - 0.55) / 0.06));
  let b = 0.35 * exp(-sq((t - 0.72) / 0.10));
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;

  let edgeStrength = u.zoom_params.x;
  let glowRadius = u.zoom_params.y;
  let neonTint = u.zoom_params.z;
  let intensity = u.zoom_params.w;

  let hasAudio = arrayLength(&plasmaBuffer) > 0u;
  let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
  let mids = select(0.0, plasmaBuffer[0].y, hasAudio);
  let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));

  let texel = 1.0 / dims;
  let l = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let r = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let t = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let b = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0,  texel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

  let edgeMag = length(vec2<f32>(l - r, t - b)) * edgeStrength * (1.0 + bass * 0.5);

  let acFreq = 60.0;
  let mains = pow(abs(sin(time * acFreq * 3.14159265)), 2.0);
  let flicker = mains * (0.82 + 0.18 * sin(time * 7.0 + bass * 5.0)) * (1.0 + bass * 0.25);

  let mouseOffset = (mouse - 0.5) * 0.15;
  let bendUV = uv + vec2<f32>(sin(uv.y * 3.14159) * mouseOffset.x, sin(uv.x * 3.14159) * mouseOffset.y);

  let tubeT = fract(neonTint * 0.8 + bendUV.x * 2.0 + time * 0.08);
  let neonColor = neonSpectrum(tubeT, flicker);
  let mercuryColor = mercurySpectrum(tubeT) * (0.3 + mids * 0.4);

  let edgeMask = smoothstep(0.015, 0.22, edgeMag);
  let neonLine = (neonColor + mercuryColor) * edgeMask * intensity * (0.75 + treble * 0.5 + flicker * 0.3);

  let glow = smoothstep(0.0, glowRadius * 0.10, edgeMag) * (1.0 - smoothstep(glowRadius * 0.05, glowRadius * 0.15, edgeMag));
  let glowBloom = glow * intensity * 0.5 * neonColor;

  let electrodeGlow = exp(-abs(bendUV.x - 0.05) * 30.0) + exp(-abs(bendUV.x - 0.95) * 30.0);
  let sputter = vec3<f32>(1.0, 0.85, 0.6) * electrodeGlow * (0.15 + flicker * 0.25) * edgeMask;

  let chromaShift = vec2<f32>(texel.x * 1.5, 0.0) * edgeMask;
  let rEnd = textureSampleLevel(readTexture, u_sampler, clamp(uv + chromaShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bEnd = textureSampleLevel(readTexture, u_sampler, clamp(uv - chromaShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let chromaticBase = vec3<f32>(rEnd, baseColor.g, bEnd);

  let haze = exp(-depth * 2.0) * 0.15 * mids;
  let atmospheric = vec3<f32>(0.6, 0.7, 0.9) * haze;

  let bloomRing = smoothstep(0.25, 0.0, abs(edgeMag - 0.12)) * 0.3 * intensity;
  let secondaryBloom = neonColor * bloomRing * (0.4 + bass * 0.3);

  // ── Idea 2: positive-column striations (native gas discharge) ────────
  // A real discharge column shows standing bright/dark bands ALONG the tube. The
  // tube direction is the gradient's perpendicular, which the four taps above
  // already give. Raw per-pixel tangents are jittery and `dot(pixelPos, tangent)`
  // multiplies that jitter by the distance from the origin (speckle on curved
  // edges), so the tangent is snapped to 8 directions and the phase is measured
  // from a tile-local origin (tile = 3 bands, so axis-aligned tubes stay continuous
  // across tile edges). Sign is fixed so the two flanks of a line do not
  // counter-propagate. ~14 px per band at 1080p; amplitude rides the mains flicker,
  // fades out on weak edges, and modulates the whole tube emission (line+glow+core).
  let gDir = vec2<f32>(l - r, t - b);
  let tang0 = vec2<f32>(-gDir.y, gDir.x) / max(length(gDir), 1e-4);
  let tang = select(-tang0, tang0, (tang0.x > 1e-4) || (abs(tang0.x) <= 1e-4 && tang0.y >= 0.0));
  // snap to 8 directions without trig: round(2*unit) -> {0, 26.6, 45, 63.4, 90 deg} and mirrors
  let tangQ = normalize(round(tang * 2.0) + vec2<f32>(1e-6, 0.0));
  let pxScale = dims.y / 1080.0;
  let bandPx = 14.0 * pxScale;
  let tilePx = 3.0 * bandPx;
  let pFull = vec2<f32>(gid.xy);
  let pLocal = pFull - floor(pFull / tilePx) * tilePx;
  let striPhase = dot(pLocal, tangQ) / bandPx - time * 1.4;
  let striBand = 0.5 + 0.5 * cos(6.28318 * striPhase);
  let striAmt = smoothstep(0.02, 0.08, edgeMag) * 0.45 * (0.6 + 0.4 * flicker);
  let striation = 1.0 + striAmt * (2.0 * striBand - 1.0);

  let tubeGeometry = smoothstep(0.02, 0.06, edgeMag) * (1.0 - smoothstep(0.12, 0.20, edgeMag));
  let tubeCore = neonColor * tubeGeometry * (0.55 + flicker * 0.4);
  let sheath = smoothstep(0.05, 0.18, edgeMag) * (1.0 - smoothstep(0.18, 0.42, edgeMag));
  let darkSheath = 1.0 - sheath * 0.55;

  // ── Idea 1: ring-gather spill glow (native) ──────────────────────────
  // A lit tube casts a pool of its own colour onto the wall around it. HEAD's `glow`
  // is a band of the same 1-px gradient magnitude, so it never leaves the edge. One ring
  // of four integer-load taps at r = 0.6 * glowRadius * 40 px (1080p) asks how much
  // high-contrast edge sits within reach (|luma(tap) - luma(here)|, knee'd so texture
  // does not haze the frame); the mean of the four is the pool strength. The pool is
  // added to the sheath-darkened base, not on top of the tube itself, so energy is not
  // stacked on already-saturated pixels. (A single ring has no 1/d^2 profile: this is a
  // plain ring gather, not a soft inverse-square falloff.) Four taps because the 8-tap
  // two-ring version cost ~1.35-1.4x HEAD on an idle SwiftShader; the taps are on the
  // axes, so diagonal edges are caught by fewer taps than axis-aligned ones.
  let spillR = glowRadius * 40.0 * pxScale;
  let dimsI = vec2<i32>(dims);
  let pixI = vec2<i32>(gid.xy);
  let hiI = dimsI - vec2<i32>(1);
  let o0 = i32(round(0.6 * spillR));
  let lw = vec3<f32>(0.299, 0.587, 0.114);
  // reference from the same kind of load as the taps (HEAD's `luma` is a bilinear sample at the texel
  // corner, half a texel off the integer loads), so glowRadius = 0 gives exactly zero spill
  let lumaC = dot(textureLoad(readTexture, pixI, 0).rgb, lw);
  let ring = vec4<f32>(
    dot(textureLoad(readTexture, clamp(pixI + vec2<i32>( o0, 0), vec2<i32>(0), hiI), 0).rgb, lw),
    dot(textureLoad(readTexture, clamp(pixI + vec2<i32>(0,  o0), vec2<i32>(0), hiI), 0).rgb, lw),
    dot(textureLoad(readTexture, clamp(pixI + vec2<i32>(-o0, 0), vec2<i32>(0), hiI), 0).rgb, lw),
    dot(textureLoad(readTexture, clamp(pixI + vec2<i32>(0, -o0), vec2<i32>(0), hiI), 0).rgb, lw));
  let kRing = smoothstep(vec4<f32>(0.10), vec4<f32>(0.40), abs(ring - vec4<f32>(lumaC)) * edgeStrength);
  let spillAmt = (kRing.x + kRing.y + kRing.z + kRing.w) * 0.25;
  let spill = neonColor * spillAmt * intensity * 0.9 * (1.0 - 0.6 * edgeMask);

  var finalColor = chromaticBase * darkSheath + (neonLine + glowBloom + tubeCore) * striation + secondaryBloom + sputter + atmospheric + spill;
  finalColor = acesTonemap(finalColor * 1.2);

  let tubeExcitation = edgeMask * (flicker + 0.3) + glow * 0.5 + electrodeGlow * 0.2 + spillAmt * 0.3;
  let finalAlpha = clamp(tubeExcitation * intensity * depth, 0.25, 0.98);
  let display = vec4<f32>(finalColor, finalAlpha);

  textureStore(writeTexture, vec2<i32>(gid.xy), display);
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), display);
}
