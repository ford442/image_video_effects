// ═══════════════════════════════════════════════════════════════════
//  Magnetic Pixels
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: dipole field-line loops (flux-function isolines); N/S pole lobes, hold to freeze + flip; soft pole glow
//  A packing: ACES display RGBA; texel (0,0) = (dipole phase, last time, 0, 1) state, read back via exact C load
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.283185307;

// ═══ CHUNK: hash12 (common) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: aces_tone_map ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Dipole magnetic field B = (3(m·r)r - m|r|²) / |r|⁵
fn dipole_field(pos: vec2<f32>, dipolePos: vec2<f32>, moment: vec2<f32>) -> vec2<f32> {
  let r = pos - dipolePos;
  let r2 = dot(r, r);
  let r2_safe = max(r2, 0.0001);
  let invR5 = 1.0 / (r2_safe * r2_safe * sqrt(r2_safe));
  let m_dot_r = dot(moment, r);
  return (3.0 * m_dot_r * r - moment * r2_safe) * invR5;
}

// Vector potential A = cross(m, r) / |r|³  (scalar in 2D)
fn vector_potential(pos: vec2<f32>, dipolePos: vec2<f32>, moment: vec2<f32>) -> f32 {
  let r = pos - dipolePos;
  let r2 = dot(r, r);
  let r2_safe = max(r2, 0.0001);
  return (moment.x * r.y - moment.y * r.x) / (r2_safe * sqrt(r2_safe));
}

// Idea 1 helper: Stokes flux function Ψ = (r·sinθ)·A / |m| = sin²θ / |r|.
// Its isolines are exactly the field lines of dipole_field (r = L·sin²θ loops).
fn flux_lines(pos: vec2<f32>, dipolePos: vec2<f32>, mHat: vec2<f32>) -> f32 {
  let r = pos - dipolePos;
  let cr = mHat.x * r.y - mHat.y * r.x;               // |r|·sinθ (signed)
  return vector_potential(pos, dipolePos, mHat) * cr; // = sin²θ / |r|
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let dipoleStrength = u.zoom_params.x * (1.0 + bass * 0.6);
  let fieldRadius = max(u.zoom_params.y * 0.5, 0.02);
  let metallic = u.zoom_params.z;
  let chromaAmt = u.zoom_params.w * 0.015;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthScale = mix(0.6, 1.4, depth);

  // Idea 2 (hold): the rotation phase lives in A texel (0,0) so a held mouse can
  // freeze it. Exact C load; reset on garbage (shader switch) or first frame.
  let st = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let stOk = st.x == st.x && abs(st.x) <= TAU && st.y == st.y && st.y <= time && st.w > 0.5;
  let prevPhase = select(0.0, st.x, stOk);
  let prevTime = select(time, st.y, stOk);
  let dt = clamp(time - prevTime, 0.0, 0.25);
  let phase = (prevPhase + select(dt * 0.8, 0.0, mouseDown)) % TAU;
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, coord, vec4<f32>(phase, time, 0.0, 1.0));
  }

  // Dipole moment rotates with time and bass; holding the mouse flips polarity
  let polarity = select(1.0, -1.0, mouseDown);
  let angle = phase + bass * 1.5;
  let mHat = vec2<f32>(cos(angle), sin(angle)) * polarity;
  let dipoleMoment = mHat * dipoleStrength;

  // Mouse acts as movable dipole; when not active, dipole is at center
  let hasMouse = mousePos.x >= 0.0;
  let dipolePos = select(vec2<f32>(0.5, 0.5), mousePos, hasMouse);

  let aspect = resolution.x / resolution.y;
  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let dipoleAspect = vec2<f32>(dipolePos.x * aspect, dipolePos.y);
  let rVec = uvAspect - dipoleAspect;
  let rLen = length(rVec);
  let axis = rVec / max(rLen, 0.0001);

  // Magnetic field at this pixel
  let B = dipole_field(uvAspect, dipoleAspect, dipoleMoment * fieldRadius * depthScale);
  let Bmag = length(B);
  let Bnorm = B / max(Bmag, 0.0001);

  // Vector potential for Lorentz-like displacement
  let A = vector_potential(uvAspect, dipoleAspect, dipoleMoment * fieldRadius);
  let lorentzDisp = vec2<f32>(-Bnorm.y, Bnorm.x) * A * 0.008 * dipoleStrength;

  // Iron-filing alignment: sample displaced by field direction.
  // Floor fix: the chroma slider fed a baseColor that was never used — the R/B
  // split now rides on the displaced filing sample along the dipole axis.
  let filingUV = clamp(uv + vec2<f32>(lorentzDisp.x / aspect, lorentzDisp.y), vec2<f32>(0.0), vec2<f32>(1.0));
  let chromaOff = vec2<f32>(axis.x * chromaAmt / aspect, axis.y * chromaAmt);
  let colR = textureSampleLevel(readTexture, u_sampler, clamp(filingUV + chromaOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let colG = textureSampleLevel(readTexture, u_sampler, filingUV, 0.0).g;
  let colB = textureSampleLevel(readTexture, u_sampler, clamp(filingUV - chromaOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let filingColor = vec3<f32>(colR, colG, colB);

  // Soft-knee field strength: 0 far away, → 1 at the poles (never a blow-out disc)
  let Bsoft = Bmag * 0.1 / (1.0 + Bmag * 0.1);

  // Metallic sheen based on field alignment with screen X axis
  let alignment = abs(Bnorm.x);
  let sheenB = Bmag / (1.0 + Bmag * 0.25);
  let sheen = vec3<f32>(0.85, 0.78, 0.65) * alignment * sheenB * metallic * 0.4;
  let filingTint = mix(vec3<f32>(0.92, 0.88, 0.82), vec3<f32>(1.0, 0.95, 0.85), alignment);

  // Idea 2: N/S pole lobes — sign of m·r splits the field into a warm north
  // lobe and a cool south lobe, strongest along the moment axis.
  let cosTheta = dot(mHat, axis);
  let northTint = vec3<f32>(1.08, 0.86, 0.62);
  let southTint = vec3<f32>(0.66, 0.84, 1.10);
  let lobeTint = select(southTint, northTint, cosTheta >= 0.0);
  let lobeW = smoothstep(0.15, 0.9, abs(cosTheta)) * smoothstep(0.02, 0.45, Bsoft) * (0.35 + 0.35 * metallic);
  var combined = filingColor * filingTint * mix(vec3<f32>(1.0), lobeTint, lobeW) + sheen;

  // Idea 1: field-line loops — isolines of the flux function, drawn as thin dark
  // lines, anti-aliased by the local pixel spacing and faded where they crowd.
  let lineScale = 6.0 * fieldRadius;
  let px = 1.0 / resolution.y;
  let psi = flux_lines(uvAspect, dipoleAspect, mHat) * lineScale;
  let psiX = flux_lines(uvAspect + vec2<f32>(px, 0.0), dipoleAspect, mHat) * lineScale;
  let psiY = flux_lines(uvAspect + vec2<f32>(0.0, px), dipoleAspect, mHat) * lineScale;
  let gradPx = max(length(vec2<f32>(psiX - psi, psiY - psi)), 1e-5);   // Ψ per pixel
  let distPx = abs(fract(psi + 0.5) - 0.5) / gradPx;
  let spacingPx = 1.0 / gradPx;
  let lineMask = (1.0 - smoothstep(0.6, 1.6, distPx)) * smoothstep(3.0, 9.0, spacingPx);
  let lineAmt = lineMask * smoothstep(0.0, 0.3, dipoleStrength) * 0.55;
  combined = combined * (1.0 - lineAmt);

  // Idea 3: bloom tamed to a soft pole glow, tinted by the lobe it sits in
  let poleGlow = lobeTint * vec3<f32>(1.0, 0.92, 0.75) * Bsoft * Bsoft * 0.35 * (1.0 + mids * 0.5);
  combined = combined + poleGlow;

  let tonemapped = aces_tonemap(max(combined * (1.0 + bass * 0.2), vec3<f32>(0.0)));

  // Alpha = field alignment confidence × depth
  let alignmentConf = smoothstep(0.0, 0.3, Bmag) * alignment;
  let alpha = clamp(alignmentConf * depth + 0.25, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(tonemapped, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  if (global_id.x != 0u || global_id.y != 0u) {
    textureStore(dataTextureA, coord, vec4<f32>(tonemapped, alpha));
  }
}
