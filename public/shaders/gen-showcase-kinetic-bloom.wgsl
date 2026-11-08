// ═══════════════════════════════════════════════════════════════════
//  Kinetic Bloom
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven
//  Complexity: Medium
//  Upgraded: 2026-10-25
//  Ideas: circulating ring-down phase front (petals ring out of phase, §12.1 t2/t3);
//         Fresnel-Schlick petal rim from the dome normal (§12.2F);
//         energy-conserving bloom halo from exact C taps (§12.2F)
//  HEAD fixes: petal count rounded to an integer (7.5 left a seam at theta=±pi); history read with
//         a filtering sampler at an off-centre uv -> exact textureLoad, texel-centred uv;
//         alpha floor 0.2 over the void -> coverage alpha; output multiplied by a shoulder profile
//         instead of the pure dome (petals were ~30% bright, flower near-black)
//  A packing: display RGBA (post-bloom), unchanged
//  Enrichment: Damped harmonic oscillator (Wolfram Alpha)
//    Equation: m d²x/dt² + c dx/dt + kx = 0
//    ζ = c / (2√(mk)), ω₀ = √(k/m), ω = ω₀√(1-ζ²)
//    Underdamped motion: x(t) = e^(-ζω₀t) cos(ωt)
//    Example: ω₀=6 rad/s, ζ=0.2 → ω=5.879 rad/s
//  Created: 2026-06-07
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// --- ACES Filmic Tone Mapping ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Hash / Noise helpers ---
fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn vnoise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash22(i).x;
  let b = hash22(i + vec2<f32>(1.0, 0.0)).x;
  let c = hash22(i + vec2<f32>(0.0, 1.0)).x;
  let d = hash22(i + vec2<f32>(1.0, 1.0)).x;
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// --- SDF helpers ---
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// --- Polar helpers ---
fn toPolar(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(length(p), atan2(p.y, p.x));
}

// --- Color palette ---
fn palette(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  let b = vec3<f32>(0.5, 0.5, 0.5);
  let c = vec3<f32>(1.0, 0.7, 0.9);
  let d = vec3<f32>(0.0, 0.33, 0.67);
  return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let dims = vec2<f32>(textureDimensions(writeTexture));
  if (id.x >= u32(dims.x) || id.y >= u32(dims.y)) { return; }
  let texel = vec2<f32>(id.xy);
  let uv = (texel + vec2<f32>(0.5)) / dims;

  let t = u.config.x;
  let mouseDown = u.zoom_config.w;
  let mouse = u.zoom_config.yz;

  // Audio data
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let overall = (bass + mids + treble) / 3.0;

  // Zoom params
  let petalCount = u.zoom_params.x;
  let complexity = u.zoom_params.y;
  let openness = u.zoom_params.z;
  let spin = u.zoom_params.w;

  // Aspect-corrected centered coordinates
  var p = (uv - 0.5) * 2.0;
  let aspect = dims.x / dims.y;
  p.x *= aspect;

  // Mouse interaction
  var mousePos = (mouse - 0.5) * 2.0;
  mousePos.x *= aspect;
  let mDist = length(p - mousePos);

  // When mouse is claimed, center the bloom at mouse and increase openness
  var center = vec2<f32>(0.0);
  var openMod = openness;
  var spinMod = spin;
  if (mouseDown > 0.5) {
    center = mousePos;
    openMod = mix(openness, 1.0, 0.5);
    spinMod = spin * (1.0 + mDist * 0.5);
  }

  // Local coordinates relative to bloom center
  let lp = p - center;
  let polar = toPolar(lp);
  let r = polar.x;
  let theta = polar.y;

  // Petal count: 3 to 12 based on param
  // HEAD fix: an integer count so cos(rot*n) closes at theta=±pi (7.5 petals left a seam).
  let nPetals = floor(3.0 + petalCount * 9.0 + 0.5);

  // ═══ Damped Harmonic Oscillator (Wolfram Alpha) ═══
  // Underdamped spring-mass: ζ < 1, ω = ω₀√(1-ζ²)
  // Each petal behaves as an independent spring-mass system
  let zeta = 0.1 + mids * 0.4;
  let omega0 = 3.0 + bass * 5.0;
  let omega = omega0 * sqrt(1.0 - zeta * zeta);
  // Bass triggers new bloom cycle; repeating underdamped envelope
  let bloomCycle = fract(t * (0.2 + bass * 0.5));
  let tOsc = bloomCycle * 5.0;
  // ── Idea 1: circulating ring-down front. The comment above says every petal is its own
  // spring, but they all shared one phase. A continuous angular phase lag (one lobe that rides
  // the spin) makes the petals ring out of phase, so a wave sweeps round the flower.
  let spin0 = theta + t * spinMod * TAU * 0.1 + mids * 0.5;
  let ringLag = 1.6 * (0.5 + 0.5 * cos(spin0 - 1.3));
  let motion = exp(-zeta * omega0 * tOsc) * cos(omega * tOsc - ringLag);
  // Bass drives excitation amplitude
  let excitation = 1.0 + bass * 2.0;

  // Spin over time + audio mid
  let rot = theta + t * spinMod * TAU * 0.1 + mids * 0.5;

  // Petal shape using sine modulation of radius
  let petalShape = 0.5 + 0.5 * cos(rot * nPetals);
  // Petal position = rest + amplitude * motion (spring-mass system)
  let petalR = 0.3 + openMod * 0.4 * petalShape + 0.15 * motion * excitation;

  // Bloom intensity: petals + core
  let bloom = 1.0 - smoothstep(0.0, petalR, r);
  let core = 1.0 - smoothstep(0.0, 0.15, r);
  // HEAD fix: multiplying the output by the pure dome `bloom` left the petal body at ~30% and the
  // flower near-black (meanL 0.019); a shoulder profile keeps the petals solid. `bloom` itself
  // still drives the rings mask and depth.
  let body = 1.0 - smoothstep(petalR * 0.4, petalR, r);

  // Secondary ring structure (complexity)
  let rings = sin(r * 20.0 - t * 2.0 * spinMod) * complexity;
  let ringMask = smoothstep(0.0, 0.5, bloom) * (1.0 - smoothstep(0.5, 1.0, bloom));

  // Color based on angle and depth
  let colorT = theta / TAU + t * 0.03 + bass * 0.1 + r * 0.5;
  var col = palette(colorT);

  // Add warmth to core
  col += core * vec3<f32>(1.0, 0.8, 0.4) * 0.5;

  // Rings add chromatic detail
  col += rings * ringMask * vec3<f32>(0.3, 0.5, 0.7) * complexity;

  // Treble adds high-frequency jitter (pollen sparkles)
  let pollen = hash22(floor(lp * 80.0 + t * 0.02 + treble * 5.0)).x;
  let pollenGlow = smoothstep(0.97, 1.0, pollen) * treble * 3.0;
  col += vec3<f32>(pollenGlow * 0.9, pollenGlow * 0.7, pollenGlow * 0.3);

  // Bass makes the bloom "pulse" brighter
  let pulse = 1.0 + bass * 0.5;
  col *= pulse;

  // Mouse glow when claimed
  if (mouseDown > 0.5) {
    let mouseGlow = exp(-mDist * 5.0) * 0.3;
    col += vec3<f32>(0.5, 0.8, 1.0) * mouseGlow;
  }

  // Vignette
  let vig = 1.0 - smoothstep(0.4, 1.2, length(p));
  col *= vig;

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass);
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  // ACES tone mapping + semantic alpha
  col = acesToneMap(col * 1.1);
  var alpha = 0.0;

  // Temporal feedback (exact C: the old filtered read at an off-centre uv blurred every frame)
  let coord = vec2<i32>(id.xy);
  let maxC = vec2<i32>(dims) - vec2<i32>(1);
  let prev = textureLoad(dataTextureC, coord, 0);
  col = mix(prev.rgb * 0.96, col, 0.25);

  // ── Idea 3: energy-conserving bloom halo (§12.2F). Glow is moved outward, not added: the
  // output is mix(source, spread, k) where spread is 4 exact C taps of last frame's display.
  let hr = vec2<i32>(6, 6);
  let spread = 0.25 * (
    textureLoad(dataTextureC, clamp(coord + vec2<i32>(hr.x, 0), vec2<i32>(0), maxC), 0).rgb +
    textureLoad(dataTextureC, clamp(coord - vec2<i32>(hr.x, 0), vec2<i32>(0), maxC), 0).rgb +
    textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, hr.y), vec2<i32>(0), maxC), 0).rgb +
    textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, hr.y), vec2<i32>(0), maxC), 0).rgb);
  var outRgb = mix(col * body, spread, 0.2);

  // ── Idea 2: Fresnel–Schlick petal rim (§12.2F). The bloom profile is a dome, so a normal
  // comes for free: n_z = sqrt(1-(r/petalR)^2). Translucent petal edges glint, F0 = 0.04.
  let sR = r / max(petalR, 0.05);
  let domeNz = sqrt(max(1.0 - sR * sR, 0.0));
  let omn = 1.0 - domeNz;
  let schlick = 0.04 + 0.96 * omn * omn * omn * omn * omn;
  let rimMask = smoothstep(1.0, 0.94, sR) * smoothstep(0.5, 0.85, sR);
  outRgb += palette(colorT + 0.15) * schlick * rimMask * 0.9 * (0.6 + 0.4 * openMod);

  alpha = clamp(length(outRgb) * 1.2, 0.0, 0.95);
  let outColor = vec4<f32>(outRgb, alpha);
  textureStore(writeTexture, id.xy, outColor);
  textureStore(dataTextureA, id.xy, outColor);

  // Depth
  textureStore(writeDepthTexture, id.xy, vec4<f32>(bloom, 0.0, 0.0, 1.0));
}
