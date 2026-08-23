// ═══════════════════════════════════════════════════════════════════
//  Holographic Interference v2.1 — Visualist upgrade (2026-07-22)
//  Category: generative
//  Features: generative, laser-interference, animated-speckle, thin-film-tint,
//            mouse-parallax, depth-aware, audio-reactive, aces, upgraded-rgba
//  Complexity: Very High
//  Chunks From: holographic_interference, interference-sim, aces-tonemap
//  Upgrade notes:
//    - Animated laser speckle grain (treble-scaled "boiling" cell hash)
//    - IQ cosine palette thin-film tint at low mix, keyed on film thickness
//    - Mouse position tilts the reference-beam angle (holographic parallax)
//    - depthWeight slider now drives parallax/attenuation strength
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

const PI: f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Coherent-source speckle: two decorrelated hashes multiplied, like a real
// random interference amplitude distribution (exponential-ish falloff).
fn speckleNoise(uv: vec2<f32>, scale: f32) -> f32 {
  let p = uv * scale;
  let h1 = hash12(p);
  let h2 = hash12(p + vec2(53.1, 17.3));
  return h1 * h2 * 2.0;
}

// Animated laser grain: a temporally jittered cell hash so the speckle field
// "boils" over time like light scattered off a moving diffuser. The jitter
// amplitude grows with treble so the shimmer tracks audio sparkle.
fn animatedSpeckle(p: vec2<f32>, scale: f32, t: f32, treble: f32) -> f32 {
  let jx = hash12(vec2(t * 0.31, 1.7));
  let jy = hash12(vec2(t * 0.47, 4.3));
  let jitter = vec2(jx, jy) * (6.0 + treble * 18.0);
  let cell = floor(p * scale + jitter);
  let coarse = hash12(cell);
  let fine = hash12(cell * 1.93 + vec2(t * 3.1, t * 1.7));
  return coarse * 0.7 + fine * 0.3;
}

// IQ cosine palette: thin-film hues that sweep as the emulsion thickness
// changes. Kept at low mix downstream so the laser fringe colors stay dominant.
fn iqPalette(t: f32) -> vec3<f32> {
  let a = vec3(0.5, 0.5, 0.5);
  let b = vec3(0.5, 0.5, 0.5);
  let c = vec3(1.0, 1.0, 1.0);
  let d = vec3(0.0, 0.33, 0.67);
  return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Slider params (saved-preset contract: ids/defaults unchanged) ──
  let filmThickness = u.zoom_params.x * 2.5 + 0.2;  // Film Thickness → object-beam path
  let waveScale = u.zoom_params.y * 5.0 + 0.8;      // Wave Scale → laser wavenumber
  let depthWeight = u.zoom_params.z;                // Depth Weight → parallax strength
  let chromaAberr = u.zoom_params.w * 0.025;        // Chromatic Aberration → dispersion

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  // Depth Weight slider gates how strongly the depth buffer modulates the plate
  let depthFactor = mix(1.0, mix(0.25, 1.0, depth), depthWeight);

  // Virtual object controlled by mouse, with depth parallax
  let objectPos = mouse * 2.0 - 1.0;
  let aspect = resolution.x / resolution.y;
  let aspectUV = (uv - 0.5) * vec2(aspect, 1.0);
  let objDist = length(aspectUV - objectPos * 0.4);

  // Reference beam angle: bass pumps it, and the mouse tilts it so the whole
  // interference field shears with viewpoint like a real holographic plate.
  let mouseTilt = (mouse - 0.5) * vec2(0.55, 0.3) * PI;
  let refAngle = (0.25 + bass * 0.25) * PI + mouseTilt.x + mouseTilt.y - held * 0.12;
  let k = waveScale * 25.0;

  // Multi-source laser interference with object and reference beams
  var interference = 0.0;
  var speckleCoherence = 0.0;
  var grainAccum = 0.0;
  let sourceCount = 3 + i32(plasmaBuffer[(u32(fract(time * 0.1) * 8.0) % 8u) + 1u].x * 2.0);
  for (var i = 0; i < sourceCount; i = i + 1) {
    let fi = f32(i);
    let srcAngle = fi * PI * 0.67 + time * 0.12;
    let srcPos = vec2(cos(srcAngle) * 0.35, sin(srcAngle) * 0.35);
    // Object beam: spherical wave from virtual object
    let objPath = sqrt(objDist * objDist + filmThickness * filmThickness);
    let objPhase = k * objPath;
    // Reference beam: planar wavefront at the (mouse-tilted) angle
    let beamAngle = refAngle + fi * 0.15;
    let refPath = (aspectUV.x - srcPos.x) * cos(beamAngle) + (aspectUV.y - srcPos.y) * sin(beamAngle);
    let refPhase = k * refPath;
    // Phase accumulation from interference
    let phaseAccum = objPhase - refPhase + time * 0.3;
    interference = interference + cos(phaseAccum);
    // Speckle from coherent source interference (static component)
    speckleCoherence = speckleCoherence + speckleNoise(uv + fi * 4.1, 600.0 + fi * 300.0);
    // Animated grain per source at slightly different scales/time offsets
    grainAccum = grainAccum + animatedSpeckle(uv, 380.0 + fi * 260.0, time + fi * 7.7, treble);
  }
  interference = interference / f32(sourceCount);
  speckleCoherence = speckleCoherence / f32(sourceCount);
  grainAccum = grainAccum / f32(sourceCount);

  // Interference contrast envelope
  let contrast = 0.5 + 0.5 * interference;

  // Chromatic dispersion: different wavelengths have different fringe spacing
  let rPhase = contrast * (1.0 + chromaAberr) * 12.0;
  let gPhase = contrast * 12.0;
  let bPhase = contrast * (1.0 - chromaAberr) * 12.0;
  let rFringe = cos(rPhase + time * 0.2) * 0.5 + 0.5;
  let gFringe = cos(gPhase + time * 0.15) * 0.5 + 0.5;
  let bFringe = cos(bPhase + time * 0.25) * 0.5 + 0.5;

  var color = vec3(rFringe, gFringe, bFringe) * (0.6 + contrast * 0.8);

  // Fine carrier fringe: a high-frequency luminance comb riding on the main
  // fringe field, phase-dithered by the animated grain for extra realism.
  let carrier = cos(contrast * 48.0 + grainAccum * 6.0 + time * 0.1);
  color = color * (1.0 + carrier * 0.08);

  // Animated laser speckle: treble-scaled shimmer modulates fringe intensity
  let shimmerGain = clamp(0.35 + treble * 0.45, 0.0, 1.0);
  let shimmer = mix(0.8, 0.8 + grainAccum * 0.75, shimmerGain);
  color = color * shimmer;

  // Static coherence speckle modulates amplitude (original soul preserved)
  color = color * (0.65 + speckleCoherence * 0.5);

  // Thin-film IQ cosine palette tint keyed on film thickness (subtle, ~0.3 mix)
  let tintKey = filmThickness * 0.22 + contrast * 0.3 + time * 0.015;
  let tint = iqPalette(tintKey);
  color = mix(color, color * (tint * 1.8 + vec3(0.1, 0.1, 0.1)), 0.3);

  // HDR bloom on constructive interference zones (bass punch, mids sparkle)
  let construct = smoothstep(0.65, 0.95, contrast);
  color = color + vec3(construct * 0.5, construct * 0.35, construct * 0.55) * (1.0 + bass * 0.5 + mids * 0.15);

  // Depth-scaled holographic parallax attenuation, driven by Depth Weight
  let parallaxAtten = mix(1.0, mix(0.4, 1.0, depthFactor), depthWeight * 0.85 + 0.15);
  color = color * parallaxAtten;

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = max(time - ripple.z, 0.0);
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    clickFront += exp(-age * 1.9) * exp(-abs(rDist - age * 0.38) * 58.0);
  }
  color += vec3<f32>(0.4, 0.75, 1.0) * clickFront * (0.2 + treble * 0.15);

  // Alpha: interference_contrast * speckle_coherence * depth (semantic alpha)
  let alpha = clamp(contrast * speckleCoherence * depthFactor * (0.7 + shimmer * 0.3) + clickFront * 0.08, 0.03, 0.94);

  // Single ACES pass (exposure chosen to match the old double-map feel)
  color = acesToneMap(color * 1.35);

  textureStore(writeTexture, pixel, vec4(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4(color, alpha));
}
