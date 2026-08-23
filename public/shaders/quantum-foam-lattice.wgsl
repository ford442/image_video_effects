// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam Lattice
//  Category: generative
//  Features: audio-reactive, temporal-feedback, chromatic-dispersion,
//            quantum-foam, crystalline-lattice, mouse-warp,
//            spectral-cells, ripple-waves
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-07-26 (Batch 18 — Algorithmist)
//    · Fixed double-tonemap feedback: dataTextureA now stores linear
//      HDR (clamped ~1.2); ACES applied only to display output.
//    · Per-cell FFT spectrum: each voronoi cell rotates hue by its own
//      plasmaBuffer FFT bin.
//    · Click ripples send decaying radial displacement waves through
//      the lattice.
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn hash31(p: vec3<f32>) -> f32 {
  let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(h) * 43758.5453123);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pos = p;
  let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * noise2(pos);
    pos = rot * pos * 2.0 + vec2<f32>(100.0);
    a = a * 0.5;
  }
  return v;
}

// Hue rotation helper: cheap spectral shift of an RGB triple by a
// cyclic hue offset in [0,1). Used to give each cell its own FFT hue.
fn hueRotate(hue: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
  return clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

// Planck length: 1.6163×10^-35 meters
// Planck time: 5.39×10^-44 seconds
// Vacuum energy density: ~10^-9 J/m³ (cosmological constant problem: theoretical QED predicts 10^113 J/m³!)
// Quantum foam: fluctuations at Planck scale l_P = 1.616e-35 m
fn planckScaleNoise(p: vec2<f32>, time: f32) -> f32 {
  // Conceptual Planck-scale granularity mapped to shader frequency space
  let highFreq = 120.0; // Inspired by inverse Planck length scaled to render space
  let planckTimeScale = 5.39; // 5.39e-44 s × 1e44, conceptual scaling
  let t = time * planckTimeScale * 0.1;
  let h1 = hash21(p * highFreq + vec2<f32>(t, t * 0.7));
  let h2 = hash21(p * highFreq * 1.618 + vec2<f32>(-t * 0.5, t));
  return (h1 + h2) * 0.5;
}

fn voronoi(p: vec2<f32>, time: f32) -> vec3<f32> {
  let n = floor(p);
  let f = fract(p);
  var minDist = 1e9;
  var secondDist = 1e9;
  var nearest = vec2<f32>(0.0);
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let g = vec2<f32>(f32(x), f32(y));
      let o = hash22(n + g) + 0.5 * sin(time * 0.3 + hash22(n + g) * 6.283) * 0.3;
      let r = g + o - f;
      let d = dot(r, r);
      if (d < minDist) {
        secondDist = minDist;
        minDist = d;
        nearest = n + g;
      } else if (d < secondDist) {
        secondDist = d;
      }
    }
  }
  return vec3<f32>(minDist, secondDist, hash21(nearest));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  // Previous frame now stores LINEAR HDR (not tonemapped), so the
  // feedback blend below stays in linear space.
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // ── Slider wiring (saved-preset contract: ids/defaults unchanged) ──
  // density  → lattice cell density (2..12 cells across the short axis)
  // foam     → vacuum-fluctuation amplitude: bubble threshold + gain
  // warp     → mouse + click-ripple displacement strength
  // sparkle  → treble sparkle density at node intersections
  let latticeDensity = mix(2.0, 12.0, u.zoom_params.x);
  let foamIntensity = u.zoom_params.y;
  let warpStrength = u.zoom_params.z;
  let sparkleAmount = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = uv * vec2<f32>(aspect, 1.0) * latticeDensity;

  // Mouse warps the lattice locally
  let mouseUV = mouse * 0.5 + 0.5;
  let mouseUVAspect = mouseUV * vec2<f32>(aspect, 1.0) * latticeDensity;
  let mouseWarp = p - mouseUVAspect;
  let mouseDist = length(mouseWarp);
  let mouseInfluence = exp(-mouseDist * mouseDist * 3.0) * warpStrength;
  var warpedP = p + normalize(mouseWarp + vec2<f32>(0.001)) * mouseInfluence * 2.0;

  // Click ripples: decaying radial displacement waves travelling
  // outward through the lattice from each click point.
  var rippleDisp = vec2<f32>(0.0);
  var rippleGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age > 0.0 && age < 3.0) {
      let rpPos = rp.xy * vec2<f32>(aspect, 1.0) * latticeDensity;
      let toP = warpedP - rpPos;
      let rd = length(toP);
      // Expanding wavefront: crest radius grows with age, decays with
      // both distance from the crest and elapsed time.
      let crest = age * 4.0;
      let band = exp(-abs(rd - crest) * 2.5);
      let decay = exp(-age * 1.6);
      let amp = band * decay * warpStrength * rp.w;
      rippleDisp = rippleDisp + normalize(toP + vec2<f32>(0.001)) * amp * sin(rd * 6.0 - age * 10.0) * 0.6;
      rippleGlow = rippleGlow + band * decay * rp.w;
    }
  }
  warpedP = warpedP + rippleDisp;

  // Quantum foam: bubbling vacuum fluctuations
  // Planck time 5.39e-44 s drives foam animation speed conceptually
  let planckTimeScale = 5.39; // scaled conceptual factor
  let foamTime = time * (0.5 + bass * 1.5) * planckTimeScale * 0.1;
  let foamScale = 4.0 + bass * 6.0;
  let foamNoise = fbm2(warpedP * foamScale + vec2<f32>(foamTime * 0.2, foamTime * 0.15), 4);
  let planckFluctuation = planckScaleNoise(warpedP, time);
  let bubbleField = sin(foamNoise * 12.0 + foamTime + planckFluctuation * 2.0) * 0.5 + 0.5;
  // Foam slider lowers the bubble threshold and raises bubble gain.
  let bubbleLo = 0.62 - foamIntensity * 0.14;
  let bubbleHi = 0.80 - foamIntensity * 0.10;
  let bubbleMask = smoothstep(bubbleLo, bubbleHi, bubbleField) * (0.25 + foamIntensity * 0.95);

  // Crystalline lattice from voronoi
  let v = voronoi(warpedP + vec2<f32>(sin(time * 0.1), cos(time * 0.08)), time);
  let minDist = sqrt(v.x);
  let secondDist = sqrt(v.y);
  let cellId = v.z;

  // Lattice edges with distortion from mids
  let edgeWidth = 0.04 + mids * 0.06;
  let edge = smoothstep(edgeWidth, 0.0, secondDist - minDist);
  let latticeDistortion = sin(minDist * 20.0 + mids * 6.28 + time) * 0.5 + 0.5;
  let distortedEdge = edge * (0.7 + latticeDistortion * 0.3);

  // Node intersections = lattice points
  let node = smoothstep(0.08 + mids * 0.05, 0.0, minDist);

  // Bass drives lattice pulse
  let pulse = 1.0 + bass * sin(time * 3.0 + cellId * 10.0) * 0.5;

  // Chromatic dispersion: R/G/B channel offsets per element
  let caStrength = 0.015 * (1.0 + treble);
  let rOffset = vec2<f32>(caStrength, 0.0);
  let gOffset = vec2<f32>(0.0, -caStrength * 0.5);
  let bOffset = vec2<f32>(-caStrength * 0.8, caStrength * 0.3);

  let vr = voronoi((warpedP + rOffset * latticeDensity) + vec2<f32>(sin(time * 0.1), cos(time * 0.08)), time);
  let vg = voronoi((warpedP + gOffset * latticeDensity) + vec2<f32>(sin(time * 0.1), cos(time * 0.08)), time);
  let vb = voronoi((warpedP + bOffset * latticeDensity) + vec2<f32>(sin(time * 0.1), cos(time * 0.08)), time);

  let edgeR = smoothstep(edgeWidth, 0.0, sqrt(vr.y) - sqrt(vr.x));
  let edgeG = smoothstep(edgeWidth, 0.0, sqrt(vg.y) - sqrt(vg.x));
  let edgeB = smoothstep(edgeWidth, 0.0, sqrt(vb.y) - sqrt(vb.x));

  // Treble creates sparkles at node intersections
  let sparkleNoise = hash31(vec3<f32>(floor(warpedP * latticeDensity), fract(time * 10.0)));
  let sparkle = step(1.0 - sparkleAmount * 0.15, sparkleNoise) * treble * node * 3.0 * sparkleAmount;

  // Per-cell spectrum: rotate each voronoi cell's hue by its own FFT
  // bin so the lattice shimmers across the spectrum as audio plays.
  let cellBin = u32(floor(cellId * 256.0)) % 8u;
  let cellFFT = plasmaBuffer[1u + cellBin].x;
  let hue = cellId + time * 0.02 + cellFFT * 0.85;
  let cellColor = hueRotate(hue);

  let latticeColor = vec3<f32>(edgeR, edgeG, edgeB) * cellColor * pulse * (0.6 + bass * 0.6);
  let nodeColor = vec3<f32>(0.8, 0.9, 1.0) * node * pulse * (1.0 + bass);
  let sparkleColor = vec3<f32>(1.0, 0.95, 0.8) * sparkle;

  // Foam bubbles with chromatic tint (also spectralized per cell)
  let bubbleHue = fract(cellId * 0.7 + time * 0.03 + cellFFT * 0.5);
  let bubbleColor = hueRotate(bubbleHue);
  let bubbles = bubbleColor * bubbleMask * (0.4 + treble * 0.4);

  // Ripple crests leave a faint energy glow on the lattice
  let rippleGlowColor = cellColor * rippleGlow * 0.35;

  var color = latticeColor + nodeColor + sparkleColor + bubbles + rippleGlowColor;

  // Temporal feedback in LINEAR space (same blend weights as before:
  // 0.25 + bass * 0.15). prev.rgb is linear HDR, so no double-tonemap.
  let feedback = mix(color, prev.rgb, 0.25 + bass * 0.15);

  // Store linear HDR (clamped pre-tint ~1.2) for next frame's feedback.
  let linearHDR = clamp(feedback, vec3<f32>(0.0), vec3<f32>(1.2));

  // ACES tone mapping applied ONLY to the final display output.
  color = acesToneMap(feedback);

  // Semantic alpha: based on edge density + bubble presence + sparkle
  let alpha = clamp(distortedEdge * 0.7 + bubbleMask * 0.5 + node * 0.6 + sparkle * 0.3 + rippleGlow * 0.2, 0.0, 1.0);

  
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(u.config.z/u.config.w, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let __finalRGB = color + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(__finalRGB, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(linearHDR, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(distortedEdge * 0.5 + node * 0.3 + bubbleMask * 0.2, 0.0, 0.0, 0.0));
}
