// ═══════════════════════════════════════════════════════════════════
//  Neural Fractal HDR
//  Category: advanced-hybrid
//  Features: generative, neural-fractal, HDR-bloom, tone-mapped
//  Complexity: Very High
//  Chunks From: gen-neural-fractal.wgsl, alpha-hdr-bloom-chain.wgsl
//  Created: 2026-04-18
//  By: Agent CB-23 — Generative Abstract Enhancer
//  Upgraded: 2026-10-31
//  Ideas: smooth iteration count on swish-layer escapes (§12.2 E); activation-layer fingerprint tints the closest-approach glow; Lyapunov sensitivity contours (tangent vector carried through the layers; iso-lines of the finite-time exponent as thin HDR lines)
//  A packing: raw HDR (A.rgb = hdrFinal, A.a = exposure); writeTexture = ACES display
// ═══════════════════════════════════════════════════════════════════
//  Neural network weight visualization fractals with HDR bloom
//  chain. Iteration traps produce bright values that bloom across
//  neighbors, then ACES tone-mapped for cinematic display.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: sigmoid (from gen-neural-fractal.wgsl) ═══
fn sigmoid(x: f32) -> f32 {
  return 1.0 / (1.0 + exp(-x));
}

fn tanh_activation(x: f32) -> f32 {
  return tanh(x);
}

fn swish(x: f32) -> f32 {
  return x * sigmoid(x);
}

fn neuralLayer(z: vec2<f32>, c: vec2<f32>, activation: i32) -> vec2<f32> {
  var result: vec2<f32>;
  if (activation == 0) {
    result = vec2<f32>(sigmoid(z.x * z.x - z.y * z.y + c.x), sigmoid(2.0 * z.x * z.y + c.y));
  } else if (activation == 1) {
    result = vec2<f32>(tanh_activation(z.x * z.x - z.y * z.y + c.x), tanh_activation(2.0 * z.x * z.y + c.y));
  } else if (activation == 2) {
    result = vec2<f32>(swish(z.x * z.x - z.y * z.y + c.x), swish(2.0 * z.x * z.y + c.y));
  } else {
    result = vec2<f32>(sigmoid(z.x * z.x - z.y * z.y + c.x), tanh_activation(2.0 * z.x * z.y + c.y));
  }
  return result;
}

fn domainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
  let warp1 = vec2<f32>(sin(p.x * 3.0 + time * 0.5) * 0.1, cos(p.y * 3.0 + time * 0.3) * 0.1);
  let warp2 = vec2<f32>(sin(p.y * 5.0 - time * 0.4) * 0.05, cos(p.x * 5.0 + time * 0.6) * 0.05);
  return p + warp1 + warp2;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

// ═══ CHUNK: toneMapACES (from alpha-hdr-bloom-chain.wgsl) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Activation derivative from the layer OUTPUT (no extra exp): 0 sigmoid, 1 tanh, 2 swish
fn actDeriv(out: f32, x: f32, kind: i32) -> f32 {
  let sg = out * (1.0 - out);
  let th = 1.0 - out * out;
  let s = select(0.5, out / x, abs(x) > 1e-4);
  let sw = s + out * (1.0 - s);
  return select(select(sg, th, kind == 1), sw, kind == 2);
}

// Evaluate fractal at given UV for bloom sampling. `full` adds the Lyapunov veins (base eval only).
fn evalFractal(uv: vec2<f32>, resolution: vec2<f32>, time: f32, zoom: f32, colorSpeed: f32, iterations: i32, mutation: f32, full: bool) -> vec3<f32> {
  let aspect = resolution.x / resolution.y;
  let zoomAnim = zoom * (1.0 + 0.2 * sin(time * 0.1));
  let scale = 2.5 / zoomAnim;
  let center = vec2<f32>(sin(time * 0.05) * 0.1, cos(time * 0.07) * 0.1);
  var p = (uv - 0.5) * vec2<f32>(scale * aspect, scale) + center;
  p = domainWarp(p, time);
  let juliaC = vec2<f32>(sin(time * 0.1) * 0.5 + mutation * sin(p.x * 10.0), cos(time * 0.08) * 0.5 + mutation * cos(p.y * 10.0));
  var z = p;
  var iter = 0;
  var trap = 1000.0;
  var trapLayer = 0;
  var sumZ = vec2<f32>(0.0);
  var tang = vec2<f32>(1.0, 0.0);
  var lyap = 0.0;
  for (iter = 0; iter < iterations; iter++) {
    let activationType = (iter / 10) % 4;
    let zPrev = z;
    z = neuralLayer(z, juliaC, activationType);
    let d = length(z - vec2<f32>(0.5, 0.0));
    // ── Idea 2: remember which activation layer fired at the closest approach
    trapLayer = select(trapLayer, activationType, d < trap);
    trap = min(trap, d);
    sumZ = sumZ + z;
    // ── Idea 3: carry a tangent vector through the layers (J = diag(f', g') · 2·zPrev complex-multiply)
    if (full) {
      let kx = select(select(0, 1, activationType == 1), 2, activationType == 2);
      let ky = select(select(0, 1, activationType == 1 || activationType == 3), 2, activationType == 2);
      let ax = zPrev.x * zPrev.x - zPrev.y * zPrev.y + juliaC.x;
      let ay = 2.0 * zPrev.x * zPrev.y + juliaC.y;
      let da = 2.0 * vec2<f32>(zPrev.x * tang.x - zPrev.y * tang.y, zPrev.y * tang.x + zPrev.x * tang.y);
      tang = vec2<f32>(actDeriv(z.x, ax, kx) * da.x, actDeriv(z.y, ay, ky) * da.y);
      let tn2 = max(dot(tang, tang), 1e-30);
      lyap += 0.5 * log(tn2);
      tang = tang * inverseSqrt(tn2);
    }
    if (length(z) > 10.0) { break; }
  }
  // ── Idea 1: smooth iteration count on escape (swish layers are unbounded; sigmoid/tanh never escape)
  let escaped = length(z) > 10.0;
  let nu = f32(iter) + 1.0 - log2(max(log(max(length(z), 1.0001)) / 2.302585, 1.0));
  let iterRatio = select(f32(iter), nu, escaped) / f32(iterations);
  let palA = vec3<f32>(0.5, 0.5, 0.5);
  let palB = vec3<f32>(0.5, 0.5, 0.5);
  let palC = vec3<f32>(1.0, 1.0, 1.0);
  let palD = vec3<f32>(0.0 + time * colorSpeed * 0.1, 0.33 + time * colorSpeed * 0.15, 0.67 + time * colorSpeed * 0.2);
  var col = palette(iterRatio + trap * 2.0, palA, palB, palC, palD);
  let glow = exp(-trap * 5.0) * 0.5;
  // layer fingerprint: sigmoid cool blue, tanh amber, swish green, sigmoid/tanh mix magenta
  var layerTint = vec3<f32>(0.7, 0.2, 0.7);
  layerTint = select(layerTint, vec3<f32>(0.15, 0.35, 0.9), trapLayer == 0);
  layerTint = select(layerTint, vec3<f32>(0.9, 0.5, 0.15), trapLayer == 1);
  layerTint = select(layerTint, vec3<f32>(0.2, 0.8, 0.4), trapLayer == 2);
  col += mix(vec3<f32>(0.4, 0.2, 0.6), layerTint, 0.65) * glow;
  let structure = length(sumZ) * 0.01;
  col = mix(col, col * (1.0 + structure), 0.3);
  if (full) {
    // ── Idea 3: iso-contours of the finite-time Lyapunov exponent (how fast a weight perturbation
    // decays through the layers) drawn as thin HDR gradient-flow lines; fade out where chaotic/escaping
    let lam = lyap / f32(max(iter, 1));
    let isoD = abs(fract(lam * 6.0 + 0.5) - 0.5);
    let vein = (1.0 - smoothstep(0.0, 0.09, isoD)) * (1.0 - smoothstep(0.2, 1.0, lam));
    col += vec3<f32>(0.35, 0.6, 0.95) * vein * 0.8;
  }
  return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let t = u.config.x;
  let coord = vec2<i32>(global_id.xy);

  let zoom = mix(0.5, 3.0, u.zoom_params.x);
  let colorSpeed = mix(0.1, 1.0, u.zoom_params.y);
  let iterations = i32(mix(30.0, 100.0, u.zoom_params.z));
  let mutation = mix(0.0, 0.5, u.zoom_params.w);

  // Base fractal
  var col = evalFractal(uv, resolution, t, zoom, colorSpeed, iterations, mutation, true);

  // === HDR BLOOM KERNEL ===
  let bloomRadius = mix(0.005, 0.03, u.zoom_params.x);
  let bloomIntensity = u.zoom_params.y * 2.0;
  let bloomSamples = 12;
  var bloom = vec3<f32>(0.0);
  var totalWeight = 0.0;

  for (var i = 0; i < bloomSamples; i = i + 1) {
    let angle = f32(i) * 6.283185307 / f32(bloomSamples);
    let radius = bloomRadius * (1.0 + f32(i % 3) * 0.5);
    let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let neighbor = evalFractal(sampleUV, resolution, t, zoom, colorSpeed, iterations / 2, mutation, false);
    let neighborMax = max(neighbor.r, max(neighbor.g, neighbor.b));
    let neighborExposure = max(0.0, neighborMax - 0.6);
    let weight = exp(-f32(i % 3) * 0.5);
    bloom += neighbor * neighborExposure * weight;
    totalWeight += neighborExposure * weight;
  }

  if (totalWeight > 0.001) {
    bloom /= totalWeight;
  }
  bloom *= bloomIntensity;

  let hdrColor = col + bloom;

  // === MOUSE BLOOM BOOST ===
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let mouseGlow = smoothstep(0.2, 0.0, mouseDist) * mouseDown * 2.0;
  let hdrWithMouse = hdrColor + vec3<f32>(mouseGlow * 0.5, mouseGlow * 0.3, mouseGlow * 0.1);

  // === RIPPLE FLASH ===
  let rippleCount = min(u32(u.config.y), 50u);
  var flashAccum = vec3<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = t - ripple.z;
    if (age < 0.5 && rDist < 0.1) {
      let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
      flashAccum += vec3<f32>(flash * 2.0, flash * 1.5, flash);
    }
  }
  let hdrFinal = hdrWithMouse + flashAccum;

  // === TONE MAP ===
  let toneMapExp = mix(0.5, 2.0, u.zoom_params.z);
  let ldrColor = toneMapACES(hdrFinal * toneMapExp);

  // Vignette
  let vignette = 1.0 - length(uv - 0.5) * 0.8;
  let finalColor = ldrColor * vignette;

  let maxChannel = max(hdrFinal.r, max(hdrFinal.g, hdrFinal.b));
  let exposure = max(0.0, maxChannel - 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(hdrFinal, exposure));
  textureStore(writeTexture, coord, vec4<f32>(finalColor, exposure + 0.1));
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
