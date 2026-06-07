// ═══════════════════════════════════════════════════════════════════
//  Celestial Aether-Seraphim Wings
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven, raymarched
//  Complexity: High
//  Enrichment: Aerodynamic lift (Wolfram Alpha)
//    C_L = 2πα (thin airfoil, small angle α in radians)
//    Stall angle: ~15° (0.262 rad)
//    C_D ≈ C_D0 + C_L²/(π A R e)
//    Lift drives brightness; stall = turbulent breakdown
//  Created: 2026-06-07
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

    // Wing feather structures
    let feather = length(p.xz) - u.zoom_params.y * (1.0 - f32(i) * 0.15);
    d = smin(d, feather, 0.3);
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

    // Thin-film interference iridescence
    let hue = fract(u.zoom_params.z + t * 0.1 + fresnel * 0.5);
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

  // Atmospheric Fog
  col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.05 * t));

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass);
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  // ACES tone mapping + semantic alpha
  col = acesToneMap(col * 1.1);
  let alpha = clamp(length(col) * 1.2, 0.2, 0.95);

  // Temporal feedback
  let uvScreen = vec2<f32>(coords) / res;
  let prev = textureSampleLevel(dataTextureC, u_sampler, uvScreen, 0.0);
  col = mix(prev.rgb * 0.96, col, 0.25);

  let outColor = vec4<f32>(col, alpha);
  textureStore(writeTexture, coords, outColor);
  textureStore(dataTextureA, coords, outColor);
}
