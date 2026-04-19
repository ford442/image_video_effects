// ═══════════════════════════════════════════════════════════════════
//  spectral-flow-structure
//  Category: advanced-hybrid
//  Features: pixel-sorting, structure-tensor, LIC, optical-flow,
//            audio-reactive, mouse-driven
//  Complexity: Very High
//  Chunks From: spectral-flow-sorting (pixel sorting along flow,
//               frequency analysis), conv-structure-tensor-flow
//               (structure tensor eigenvectors, coherency, LIC)
//  Created: 2026-04-18
//  By: Agent CB-7 — Flow & Multi-Pass Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Structure-tensor-guided pixel sorting. Eigenvectors from the
//  structure tensor replace optical flow as the sort direction.
//  Coherency (eigenvalue ratio) modulates sort threshold and blend.
//  LIC texture adds flow-line visualization. Audio reactivity and
//  mouse vortices disturb the natural texture flow.
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
  let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
  return dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

// ═══ CHUNK: structureTensor (from conv-structure-tensor-flow) ═══
fn structureTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  let gx =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
    -2.0 * sampleLuma(uv, pixelSize, -1,  0) +
    -1.0 * sampleLuma(uv, pixelSize, -1,  1) +
     1.0 * sampleLuma(uv, pixelSize,  1, -1) +
     2.0 * sampleLuma(uv, pixelSize,  1,  0) +
     1.0 * sampleLuma(uv, pixelSize,  1,  1);
  let gy =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
    -2.0 * sampleLuma(uv, pixelSize,  0, -1) +
    -1.0 * sampleLuma(uv, pixelSize,  1, -1) +
     1.0 * sampleLuma(uv, pixelSize, -1,  1) +
     2.0 * sampleLuma(uv, pixelSize,  0,  1) +
     1.0 * sampleLuma(uv, pixelSize,  1,  1);
  let Ix2 = gx * gx;
  let Iy2 = gy * gy;
  let Ixy = gx * gy;
  return vec4<f32>(Ix2, Iy2, Ixy, 0.0);
}

fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  var sum = vec4<f32>(0.0);
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      sum += structureTensor(uv + offset, pixelSize);
    }
  }
  return sum / 9.0;
}

// ═══ CHUNK: LIC (from conv-structure-tensor-flow) ═══
fn lic(uv: vec2<f32>, direction: vec2<f32>, pixelSize: vec2<f32>, steps: i32, stepSize: f32) -> f32 {
  var pos = uv;
  var accum = 0.0;
  var weight = 0.0;
  for (var i = 0; i < steps; i++) {
    let lum = dot(textureSampleLevel(readTexture, u_sampler, pos, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let w = 1.0 - f32(i) / f32(steps);
    accum += lum * w;
    weight += w;
    pos += direction * stepSize * pixelSize;
  }
  pos = uv;
  for (var i = 0; i < steps; i++) {
    let lum = dot(textureSampleLevel(readTexture, u_sampler, pos, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let w = 1.0 - f32(i) / f32(steps);
    accum += lum * w;
    weight += w;
    pos -= direction * stepSize * pixelSize;
  }
  return accum / max(weight, 0.001);
}

// ═══ PIXEL SORTING ALONG STRUCTURE FLOW ═══
fn sortAlongFlow(uv: vec2<f32>, flowDir: vec2<f32>, threshold: f32, pixelSize: vec2<f32>) -> vec3<f32> {
  var sorted = vec3<f32>(0.0);
  var weights = 0.0;
  for (var i: i32 = -4; i <= 4; i++) {
    let t = f32(i) / 4.0;
    let sampleUV = uv + flowDir * t * 0.08;
    if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) {
      continue;
    }
    let sample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
    let weight = select(0.0, luma, luma > threshold);
    sorted += sample * weight;
    weights += weight;
  }
  return select(vec3<f32>(0.0), sorted / weights, weights > 0.001);
}

// ═══ FREQUENCY ANALYSIS ═══
fn analyzeFrequency(uv: vec2<f32>, pixel: vec2<f32>) -> f32 {
  var gradientSum = 0.0;
  var sampleCount = 0.0;
  for (var i: i32 = -2; i <= 2; i++) {
    for (var j: i32 = -2; j <= 2; j++) {
      let offset = vec2<f32>(f32(i), f32(j)) * pixel * 3.0;
      let sample = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
      let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
      let nextOffset = vec2<f32>(f32(i + 1), f32(j)) * pixel * 3.0;
      let nextSample = textureSampleLevel(readTexture, u_sampler, uv + nextOffset, 0.0).rgb;
      let nextLuma = dot(nextSample, vec3<f32>(0.299, 0.587, 0.114));
      gradientSum += abs(luma - nextLuma);
      sampleCount += 1.0;
    }
  }
  return gradientSum / sampleCount;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);

  // Audio input
  let audioOverall = u.zoom_config.x;
  let audioReactivity = 1.0 + audioOverall * 0.3;

  // Parameters
  let licSteps = i32(mix(6.0, 24.0, u.zoom_params.x));
  let coherencyBoost = mix(0.5, 3.0, u.zoom_params.y);
  let sortThreshold = u.zoom_params.z * 0.5;
  let smoothing = mix(0.0, 0.9, u.zoom_params.w);

  // Mouse interaction
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let distToMouse = length(uv - mousePos);
  let mouseGravity = 1.0 - smoothstep(0.0, 0.35, distToMouse);
  let clickPulse = select(0.0, 1.0, isMouseDown) * sin(distToMouse * 25.0 - time * 5.0) * exp(-distToMouse * 3.0);

  // ═══ STRUCTURE TENSOR ═══
  let tensor = smoothTensor(uv, pixelSize);
  let Jxx = tensor.x;
  let Jyy = tensor.y;
  let Jxy = tensor.z;

  // Eigenvalues
  let trace = Jxx + Jyy;
  let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
  let lambda1 = (trace + diff) * 0.5;
  let lambda2 = (trace - diff) * 0.5;

  // Dominant eigenvector (texture flow direction)
  var eigenvec = vec2<f32>(1.0, 0.0);
  if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
    eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
  }

  // Coherency: how strongly oriented
  let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);
  let boostedCoherency = pow(coherency, 1.0 / coherencyBoost);

  // Mouse vortex disturbance
  let mouseDist = length(uv - mousePos);
  let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * mouseGravity;
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
    let rElapsed = time - rStart;
    if (rElapsed > 0.0 && rElapsed < 3.0) {
      let rDist = length(uv - rPos);
      let wave = exp(-pow((rDist - rElapsed * 0.3) * 8.0, 2.0));
      let turbAngle = atan2(uv.y - rPos.y, uv.x - rPos.x) + rElapsed * 3.0;
      rippleTurb += vec2<f32>(cos(turbAngle), sin(turbAngle)) * wave * (1.0 - rElapsed / 3.0);
    }
  }
  eigenvec = normalize(eigenvec + rippleTurb * 2.0);

  // Animate flow
  let rotAngle = time * 0.2;
  let cosR = cos(rotAngle);
  let sinR = sin(rotAngle);
  let animatedDir = vec2<f32>(
    eigenvec.x * cosR - eigenvec.y * sinR,
    eigenvec.x * sinR + eigenvec.y * cosR
  );

  // LIC along the structure flow
  let licValue = lic(uv, animatedDir, pixelSize, licSteps, 1.5);

  // ═══ PIXEL SORT ALONG STRUCTURE FLOW ═══
  let flowMag = length(eigenvec);
  let cursorFlow = normalize(uv - mousePos + 0.001) * mouseGravity * 3.0 * (1.0 + select(0.0, 3.0, isMouseDown));
  let combinedFlow = eigenvec * flowMag * 5.0 + cursorFlow + clickPulse;
  let combinedDir = select(vec2<f32>(0.0), normalize(combinedFlow), length(combinedFlow) > 0.001);

  let sortedColor = sortAlongFlow(uv, combinedDir, sortThreshold * (1.0 - boostedCoherency * 0.5), pixelSize);

  // Frequency analysis
  let dominantFreq = analyzeFrequency(uv, pixelSize);

  // Base color
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Blend based on flow and coherency
  var color = mix(baseColor, sortedColor, length(combinedFlow) * smoothing * boostedCoherency);

  // Coherency-based color shift
  let flowAngle = atan2(eigenvec.y, eigenvec.x) / 6.28 + 0.5;
  let flowColor = palette(flowAngle, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
  color = mix(color, flowColor * (0.3 + 0.7 * boostedCoherency), boostedCoherency * 0.4);

  // Frequency tint
  let freqColor = vec3<f32>(dominantFreq * 2.0, dominantFreq * 1.5, dominantFreq * 3.0);
  color = mix(color, freqColor, dominantFreq * 0.3);

  // LIC texture overlay
  color = mix(color, color * (0.5 + 0.5 * licValue), 0.3);

  // Audio reactivity boost
  color *= audioReactivity;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = mix(0.8, 1.0, flowMag * 0.5 * boostedCoherency + mouseGravity * 0.2);

  textureStore(writeTexture, id, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
