// ═══════════════════════════════════════════════════════════════════
//  Celestial Aether-Seraphim Wings
//  Category: generative
//  Features: upgraded-rgba, temporal-feedback, audio-reactive, mouse-driven, raymarched
//  Complexity: High
//  Enrichment: Aerodynamic lift (Wolfram Alpha)
//    C_L = 2πα (thin airfoil, small angle α in radians)
//    Stall angle: ~15° (0.262 rad)
//    C_D ≈ C_D0 + C_L²/(π A R e)
//    Lift drives brightness; stall = turbulent breakdown
//  Upgraded: 2026-10-10
//  Ideas: stall-vortex shedding perturbs the feather fold geometry past the
//         stall angle (turbulent breakup, not just a color tint); lift-direction
//         hue shift tints the leading edge warm/cool by the sign of AOA; aether plumage contour lines; angelic halo refraction
//  A packing: display RGBA (same as writeTexture), exact history read fixed
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// --- ACES Filmic Tone Mapping ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 2D Rotation
fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

// Smooth Min
fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// Wing SDF (KIFS Fractal)
fn map(pos: vec3<f32>) -> f32 {
  var p = pos;

  // Audio
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // ═══ Aerodynamic Flap (Damped Harmonic Oscillator) ═══
  // Wing beats follow underdamped oscillation
  // ζ = c/(2√(mk)), ω = ω₀√(1-ζ²), flap = sin(ωt) · e^(-ζω₀t_mod)
  let zeta = 0.15 + mids * 0.3;
  let omega0 = 2.0 + bass * 3.0;
  let omega = omega0 * sqrt(1.0 - zeta * zeta);
  let tMod = fract(u.config.x * (0.2 + bass * 0.3)) * 4.0;
  let flap = sin(tMod * omega) * exp(-zeta * omega0 * tMod);

  // Ascent over time
  p.y += u.config.x * 2.0 * u.zoom_params.w;

  // Domain Repetition
  p.y = (fract(p.y / 8.0 + 0.5) - 0.5) * 8.0;

  var d = 1000.0;

  // Base fold
  p.x = abs(p.x);

  let time = u.config.x * 0.5;
  let beat = sin(time * 3.14 + bass * 2.0) * 0.2;

  // Idea: stall-vortex shedding. Reuses the same lift-model angle of attack as
  // the main() shading pass so the geometry itself breaks up past stall, not
  // just the color. Below stall this term is ~0 and the fold is untouched.
  let alphaAOA_map = (u.zoom_config.z - 0.5) * 0.5;
  let stallAmt = smoothstep(0.2, 0.25, abs(alphaAOA_map));

  for (var i = 0; i < 5; i++) {
    p.x = abs(p.x) - u.zoom_params.x * 1.5;
    p.y = abs(p.y) - 0.5;
    p.z = abs(p.z) - 0.2;

    let pXY = rot(0.4 + beat + flap * 0.3) * p.xy;
    p.x = pXY.x;
    p.y = pXY.y;

    let pYZ = rot(0.2 - beat*0.5) * p.yz;
    p.y = pYZ.x;
    p.z = pYZ.y;

    // Vortex shedding: a per-fold-iteration swirl phase so the turbulence
    // reads as a traveling vortex street along the wing rather than uniform jitter
    let shedPhase = time * 6.0 + f32(i) * 2.4 + bass * 4.0;
    let vortex = vec2<f32>(sin(shedPhase), cos(shedPhase * 1.3)) * stallAmt * 0.06;
    p.x += vortex.x;
    p.z += vortex.y;

    // Wing feather structures
    let feather = length(p.xz) - u.zoom_params.y * (1.0 - f32(i) * 0.15);

    // Idea 1: Aether plumage contour lines
    let contour = abs(fract(feather * 10.0 - time * 2.0) - 0.5) * 0.1;
    d = smin(d, max(feather, -contour), 0.3);
  }

  // Audio reactive fracturing
  let fracture = sin(pos.x * 10.0) * cos(pos.y * 10.0) * sin(pos.z * 10.0);
  d += fracture * bass * 0.1;

  return d;
}

// Normal Calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
  return normalize(
    e.xyy * map(p + e.xyy) +
    e.yyx * map(p + e.yyx) +
    e.yxy * map(p + e.yxy) +
    e.xxx * map(p + e.xxx)
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let coords = vec2<i32>(id.xy);
  let res = vec2<f32>(u.config.z, u.config.w);
  let uv = (vec2<f32>(coords) - vec2<f32>(0.5) * res) / res.y;

  var ro = vec3<f32>(0.0, -2.0, -5.0 + u.config.x * 0.2);
  var rd = normalize(vec3<f32>(uv, 1.0));

  // Audio
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Mouse Interaction
  let mouseX = (u.zoom_config.y - 0.5) * 6.28;
  let mouseY = (u.zoom_config.z - 0.5) * 3.14;

  let roYZ = rot(-mouseY) * ro.yz;
  ro.y = roYZ.x;
  ro.z = roYZ.y;
  let rdYZ = rot(-mouseY) * rd.yz;
  rd.y = rdYZ.x;
  rd.z = rdYZ.y;

  let roXZ = rot(mouseX) * ro.xz;
  ro.x = roXZ.x;
  ro.z = roXZ.y;
  let rdXZ = rot(mouseX) * rd.xz;
  rd.x = rdXZ.x;
  rd.z = rdXZ.y;

  var t = 0.0;
  var max_t = 30.0;
  var d = 0.0;
  var glow = 0.0;

  for (var i = 0; i < 90; i++) {
    let p = ro + rd * t;
    d = map(p);

    // Accumulate glow near surfaces
    glow += 0.01 / (0.01 + abs(d));

    if (d < 0.001 || t > max_t) { break; }
    t += d * 0.6;
  }

  var col = vec3<f32>(0.0);

  // ═══ Aerodynamic Lift (Wolfram Alpha) ═══
  // C_L = 2πα for thin airfoil, stall ~15° (0.262 rad)
  // Angle of attack α from mouse Y (zoom_config.z)
  let alphaAOA = (u.zoom_config.z - 0.5) * 0.5;
  let cl = 2.0 * 3.14159 * alphaAOA;
  let stall = smoothstep(0.2, 0.25, abs(alphaAOA));
  // Lift coefficient drives brightness
  let liftBright = 1.0 + abs(cl) * 0.5;

  if (t < max_t) {
    let p = ro + rd * t;
    let n = calcNormal(p);

    let viewDir = normalize(ro - p);
    let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

    // Thin-film interference iridescence, biased by lift direction: positive
    // AOA (climbing) warms the leading edge, negative AOA cools it — ties the
    // palette to the same Wolfram lift model that already drives brightness
    let liftHueShift = sign(alphaAOA) * clamp(abs(cl) * 0.08, 0.0, 0.15);
    let hue = fract(u.zoom_params.z + t * 0.1 + fresnel * 0.5 + liftHueShift);
    let base_col = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(hue) + vec3<f32>(0.0, 0.33, 0.67)));

    col = base_col * (0.2 + fresnel * 0.8) * liftBright;

    // Lighting
    let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
    let diff = max(dot(n, lightDir), 0.0);
    col += vec3<f32>(diff * 0.3) * base_col;

    // Audio reactive brightness
    col += vec3<f32>(bass * 1.5) * fresnel * base_col;

    // Stall region = turbulent red/orange chaos
    let turb = vec3<f32>(1.0, 0.4, 0.1) * stall * (0.5 + bass * 1.5);
    col += turb;
  }

  // Add volumetric glow
  let glowCol = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(u.zoom_params.z) + vec3<f32>(0.5, 0.0, 0.2)));
  col += vec3<f32>(glow * 0.015) * glowCol;

  // Idea 2: Angelic halo refraction (a giant floating ring above)
  let haloDist = length(uv - vec2<f32>(0.0, 0.6)) - 0.5;
  let haloRing = smoothstep(0.05, 0.0, abs(haloDist));
  col += vec3<f32>(1.0, 0.9, 0.4) * haloRing * (0.5 + treble);

  // Atmospheric Fog
  col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.05 * t));

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass);
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  // ACES tone mapping + semantic alpha
  col = acesToneMap(col * 1.1);
  let alpha = clamp(length(col) * 1.2, 0.2, 0.95);

  // Temporal feedback — exact texel load (plumbing fix: was a filtering
  // textureSampleLevel against an rgba32float history, which the binding
  // contract forbids)
  let prev = textureLoad(dataTextureC, coords, 0);
  col = mix(prev.rgb * 0.96, col, 0.25);

  let outColor = vec4<f32>(col, alpha);
  textureStore(writeTexture, coords, outColor);
  textureStore(dataTextureA, coords, outColor);

  // Real depth (plumbing fix: was hardcoded to zero despite supportsDepth: true)
  let depthNorm = clamp(t / max_t, 0.0, 1.0);
  textureStore(writeDepthTexture, id.xy, vec4<f32>(depthNorm, 0.0, 0.0, 0.0));
}
