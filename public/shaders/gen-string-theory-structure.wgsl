// ═══════════════════════════════════════════════════════════════════
//  String Theory Structure
//  Category: advanced-hybrid
//  Features: generative, wave-equation, structure-tensor, LIC
//  Complexity: Very High
//  Chunks From: gen-string-theory.wgsl, conv-structure-tensor-flow.wgsl
//  Created: 2026-04-18
//  By: Agent CB-23 — Generative Abstract Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Vibrating string harmonics visualized through structure tensor
//  analysis. Wave gradients drive line-integral-convolution flow
//  lines that reveal the hidden topology of the interference field.
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

// ═══ CHUNK: standingWave (from gen-string-theory.wgsl) ═══
fn standingWave(x: f32, t: f32, freq: f32, amplitude: f32, damping: f32) -> f32 {
  let k = freq * 6.28318;
  let w = freq * 3.14159;
  return 2.0 * amplitude * sin(k * x) * cos(w * t) * damping;
}

fn harmonicWave(x: f32, t: f32, fundamental: f32, harmonic: i32, amplitude: f32) -> f32 {
  let n = f32(harmonic);
  return standingWave(x, t, fundamental * n, amplitude / n, 1.0);
}

fn harmonicColor(n: i32, t: f32) -> vec3<f32> {
  let hue = fract(f32(n) * 0.15 + t * 0.05);
  let sat = 0.8;
  let light = 0.6;
  let c = (1.0 - abs(2.0 * light - 1.0)) * sat;
  let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
  let m = light - c * 0.5;
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (hue < 1.0/6.0) { r = c; g = x; }
  else if (hue < 2.0/6.0) { r = x; g = c; }
  else if (hue < 3.0/6.0) { g = c; b = x; }
  else if (hue < 4.0/6.0) { g = x; b = c; }
  else if (hue < 5.0/6.0) { r = x; b = c; }
  else { r = c; b = x; }
  return vec3<f32>(r + m, g + m, b + m);
}

// ═══ CHUNK: palette (from conv-structure-tensor-flow.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

// Evaluate the string field at a point
fn stringField(p: vec2<f32>, t: f32, fundamental: f32, harmonicRichness: i32, damping: f32, excitement: f32) -> f32 {
  var y = 0.0;
  let numStrings = 5;
  for (var s: i32 = 0; s < numStrings; s++) {
    let angle = f32(s) * 0.314 + t * 0.02;
    let cosA = cos(angle);
    let sinA = sin(angle);
    let stringCenter = vec2<f32>(0.5 * 1.0, 0.5 + f32(s - 2) * 0.15);
    let local = p - stringCenter;
    let stringX = local.x * cosA + local.y * sinA;
    let stringY = -local.x * sinA + local.y * cosA;
    if (abs(stringX) < 1.5) {
      let x = (stringX + 1.5) / 3.0;
      var sy = 0.0;
      for (var h: i32 = 1; h <= harmonicRichness; h++) {
        let harmAmp = 0.1 * (1.0 + excitement) / f32(h);
        let damp = pow(damping, f32(h));
        sy += harmonicWave(x, t, fundamental, h, harmAmp * damp);
      }
      let dist = abs(stringY - sy);
      y += exp(-dist * 50.0) * 0.3;
    }
  }
  return y;
}

// Structure tensor from string field
fn stringStructureTensor(p: vec2<f32>, t: f32, fundamental: f32, harmonicRichness: i32, damping: f32, excitement: f32, eps: f32) -> vec4<f32> {
  let h = stringField(p, t, fundamental, harmonicRichness, damping, excitement);
  let hx = stringField(p + vec2<f32>(eps, 0.0), t, fundamental, harmonicRichness, damping, excitement);
  let hy = stringField(p + vec2<f32>(0.0, eps), t, fundamental, harmonicRichness, damping, excitement);
  let gx = (hx - h) / eps;
  let gy = (hy - h) / eps;
  let Ix2 = gx * gx;
  let Iy2 = gy * gy;
  let Ixy = gx * gy;
  return vec4<f32>(Ix2, Iy2, Ixy, 0.0);
}

// LIC along string gradient flow
fn stringLIC(p: vec2<f32>, direction: vec2<f32>, t: f32, fundamental: f32, harmonicRichness: i32, damping: f32, excitement: f32, steps: i32, stepSize: f32) -> f32 {
  var pos = p;
  var accum = 0.0;
  var weight = 0.0;
  for (var i = 0; i < steps; i++) {
    let lum = stringField(pos, t, fundamental, harmonicRichness, damping, excitement);
    let w = 1.0 - f32(i) / f32(steps);
    accum += lum * w;
    weight += w;
    pos += direction * stepSize;
  }
  pos = p;
  for (var i = 0; i < steps; i++) {
    let lum = stringField(pos, t, fundamental, harmonicRichness, damping, excitement);
    let w = 1.0 - f32(i) / f32(steps);
    accum += lum * w;
    weight += w;
    pos -= direction * stepSize;
  }
  return accum / max(weight, 0.001);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let t = u.config.x;
  let coord = vec2<i32>(global_id.xy);

  let fundamental = mix(0.5, 3.0, u.zoom_params.x);
  let harmonicRichness = i32(mix(1.0, 10.0, u.zoom_params.y));
  let damping = mix(0.8, 0.99, u.zoom_params.z);
  let excitement = u.zoom_params.w;

  let aspect = resolution.x / resolution.y;
  var p = uv;
  p.x = p.x * aspect;

  // Parameters for structure tensor
  let licSteps = i32(mix(8.0, 24.0, u.zoom_params.x));
  let coherencyBoost = mix(0.5, 4.0, u.zoom_params.y);
  let flowSpeed = mix(0.3, 2.0, u.zoom_params.z);

  // Compute structure tensor from string field
  let eps = 0.005;
  let tensor = stringStructureTensor(p, t, fundamental, harmonicRichness, damping, excitement, eps);
  let Jxx = tensor.x;
  let Jyy = tensor.y;
  let Jxy = tensor.z;

  let trace = Jxx + Jyy;
  let det = Jxx * Jyy - Jxy * Jxy;
  let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
  let lambda1 = (trace + diff) * 0.5;
  let lambda2 = (trace - diff) * 0.5;

  var eigenvec = vec2<f32>(1.0, 0.0);
  if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
    eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
  }

  let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);
  let boostedCoherency = pow(coherency, 1.0 / coherencyBoost);

  // Mouse vortex disturbance
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * excitement;
  let mouseAngle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
  let vortex = vec2<f32>(-sin(mouseAngle), cos(mouseAngle)) * mouseFactor;
  eigenvec = normalize(mix(eigenvec, vortex, mouseFactor));

  // Ripple turbulence
  var rippleTurb = vec2<f32>(0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rPos = ripple.xy;
    let rStart = ripple.z;
    let rElapsed = t - rStart;
    if (rElapsed > 0.0 && rElapsed < 3.0) {
      let rDist = length(uv - rPos);
      let wave = exp(-pow((rDist - rElapsed * 0.3) * 8.0, 2.0));
      let turbAngle = atan2(uv.y - rPos.y, uv.x - rPos.x) + rElapsed * 3.0;
      rippleTurb += vec2<f32>(cos(turbAngle), sin(turbAngle)) * wave * (1.0 - rElapsed / 3.0);
    }
  }
  eigenvec = normalize(eigenvec + rippleTurb * 2.0);

  // Animate flow
  let rotAngle = t * 0.2 * flowSpeed;
  let cosR = cos(rotAngle);
  let sinR = sin(rotAngle);
  let animatedDir = vec2<f32>(eigenvec.x * cosR - eigenvec.y * sinR, eigenvec.x * sinR + eigenvec.y * cosR);

  // LIC along flow
  let licValue = stringLIC(p, animatedDir, t, fundamental, harmonicRichness, damping, excitement, licSteps, 0.002);

  // Color by direction and coherency
  let flowAngle = atan2(eigenvec.y, eigenvec.x) * 0.15915 + 0.5;
  let flowCol = palette(flowAngle, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
  var finalColor = flowCol * (0.3 + 0.7 * boostedCoherency) * (0.5 + 0.5 * licValue);

  // Add string harmonics glow
  var stringGlow = vec3<f32>(0.0);
  for (var h: i32 = 1; h <= min(harmonicRichness, 5); h++) {
    let hCol = harmonicColor(h, t);
    stringGlow += hCol * (1.0 / f32(h));
  }
  finalColor = mix(finalColor, stringGlow * licValue * 0.5, 0.3);

  // Vignette
  let vignette = 1.0 - length(uv - 0.5) * 0.6;
  finalColor *= vignette;

  textureStore(dataTextureA, coord, vec4<f32>(finalColor, licValue));
  textureStore(writeTexture, coord, vec4<f32>(finalColor, licValue));
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
