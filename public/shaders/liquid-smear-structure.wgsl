// ═══════════════════════════════════════════════════════════════════
//  liquid-smear-structure
//  Category: advanced-hybrid
//  Features: liquid-smear, structure-tensor, LIC, temporal, mouse-driven
//  Complexity: Very High
//  Chunks From: liquid-smear.wgsl, conv-structure-tensor-flow.wgsl
//  Created: 2026-04-18
//  By: Agent CB-14 — Liquid Effects Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Temporal liquid smear accumulates structure-tensor LIC flow.
//  Mouse pulls pixels along eigenvector streamlines while decay
//  creates painterly trails that follow image edges and texture.
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

// ═══ CHUNK: palette (from conv-structure-tensor-flow.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
  let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
  return dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let smearDecay = mix(0.85, 0.99, u.zoom_params.x);
  let licSteps = i32(mix(8.0, 32.0, u.zoom_params.y));
  let coherencyBoost = mix(0.5, 4.0, u.zoom_params.z);
  let mouseInfluence = u.zoom_params.w;

  // === STRUCTURE TENSOR FLOW (from conv-structure-tensor-flow) ===
  let tensor = smoothTensor(uv, pixelSize);
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
  let mouseDist = length(uv - mousePos);
  let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * mouseInfluence;
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

  let rotAngle = time * 0.2;
  let cosR = cos(rotAngle);
  let sinR = sin(rotAngle);
  let animatedDir = vec2<f32>(
    eigenvec.x * cosR - eigenvec.y * sinR,
    eigenvec.x * sinR + eigenvec.y * cosR
  );

  let licValue = lic(uv, animatedDir, pixelSize, licSteps, 1.5);

  // === LIQUID SMEAR (from liquid-smear) ===
  let aspect = resolution.x / resolution.y;
  let brushSize = 0.05 + mouseInfluence * 0.2;
  let smearStrength = 0.1 + mouseInfluence * 0.9;

  let dist = distance(uv * vec2(aspect, 1.0), mousePos * vec2(aspect, 1.0));
  var offset = vec2<f32>(0.0);
  if (dist < brushSize && dist > 0.001) {
    var dir = normalize(mousePos - uv);
    offset = dir * smearStrength * (1.0 - smoothstep(0.0, brushSize, dist)) * 0.05;
  }

  // Sample previous smeared LIC frame
  var history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Current LIC color
  let flowAngle = atan2(eigenvec.y, eigenvec.x) * 0.15915 + 0.5;
  let color = palette(flowAngle, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
  let currentLIC = color * (0.3 + 0.7 * boostedCoherency) * (0.5 + 0.5 * licValue);

  // Sample history at offset for smear
  var smeared = textureSampleLevel(dataTextureC, u_sampler, uv - offset, 0.0);
  if (history.a == 0.0) {
    smeared = vec4<f32>(currentLIC, 1.0);
  }

  // Blend current LIC with smeared history
  let blend = mix(vec4<f32>(currentLIC, 1.0), smeared, smearDecay);
  textureStore(dataTextureA, global_id.xy, blend);

  // Smear tint
  let smearTint = vec3<f32>(0.02, 0.01, 0.0) * smearStrength;
  let finalColor = blend.rgb + smearTint;

  // Alpha
  let alpha = clamp(0.5 + length(offset) * 10.0 + blend.a * 0.3, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
