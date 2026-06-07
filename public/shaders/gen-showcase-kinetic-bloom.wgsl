// ═══════════════════════════════════════════════════════════════════
//  Kinetic Bloom
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven
//  Complexity: Medium
//  Enrichment: Damped harmonic oscillator (Wolfram Alpha)
//    Equation: m d²x/dt² + c dx/dt + kx = 0
//    ζ = c / (2√(mk)), ω₀ = √(k/m), ω = ω₀√(1-ζ²)
//    Underdamped motion: x(t) = e^(-ζω₀t) cos(ωt)
//    Example: ω₀=6 rad/s, ζ=0.2 → ω=5.879 rad/s
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
  let texel = vec2<f32>(id.xy);
  let uv = texel / dims;

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
  let nPetals = 3.0 + petalCount * 9.0;

  // ═══ Damped Harmonic Oscillator (Wolfram Alpha) ═══
  // Underdamped spring-mass: ζ < 1, ω = ω₀√(1-ζ²)
  // Each petal behaves as an independent spring-mass system
  let zeta = 0.1 + mids * 0.4;
  let omega0 = 3.0 + bass * 5.0;
  let omega = omega0 * sqrt(1.0 - zeta * zeta);
  // Bass triggers new bloom cycle; repeating underdamped envelope
  let bloomCycle = fract(t * (0.2 + bass * 0.5));
  let tOsc = bloomCycle * 5.0;
  let motion = exp(-zeta * omega0 * tOsc) * cos(omega * tOsc);
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
  let alpha = clamp(length(col) * 1.2, 0.2, 0.95);

  // Temporal feedback
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = mix(prev.rgb * 0.96, col, 0.25);

  // Output
  let outColor = vec4<f32>(col * bloom, alpha);
  textureStore(writeTexture, id.xy, outColor);
  textureStore(dataTextureA, id.xy, outColor);

  // Depth
  textureStore(writeDepthTexture, id.xy, vec4<f32>(bloom, 0.0, 0.0, 1.0));
}
