// ═══════════════════════════════════════════════════════════════════
//  cyber-trace-structure
//  Category: advanced-hybrid
//  Features: mouse-driven, cyber-trace, structure-tensor, lic-flow
//  Complexity: Very High
//  Chunks From: cyber-trace.wgsl, conv-structure-tensor-flow.wgsl
//  Created: 2026-04-18
//  By: Agent CB-18
// ═══════════════════════════════════════════════════════════════════
//  A glowing mouse trace that follows the image's structure tensor
//  flow field. The trace color shifts via HSL along LIC streamlines.
//  Fluid viscosity makes the trace linger and twist with edges. Alpha
//  stores coherency — how strongly the trace follows structure.
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
  var tc = t;
  if (tc < 0.0) { tc = tc + 1.0; }
  if (tc > 1.0) { tc = tc - 1.0; }
  if (tc < 1.0/6.0) { return p + (q - p) * 6.0 * tc; }
  if (tc < 1.0/2.0) { return q; }
  if (tc < 2.0/3.0) { return p + (q - p) * (2.0/3.0 - tc) * 6.0; }
  return p;
}

fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
  if (s == 0.0) {
    return vec3<f32>(l);
  }
  var q: f32;
  if (l < 0.5) {
    q = l * (1.0 + s);
  } else {
    q = l + s - l * s;
  }
  let p = 2.0 * l - q;
  return vec3<f32>(
    hue2rgb(p, q, h + 1.0/3.0),
    hue2rgb(p, q, h),
    hue2rgb(p, q, h - 1.0/3.0)
  );
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
  return vec4<f32>(gx * gx, gy * gy, gx * gy, 0.0);
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
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let decaySpeed = u.zoom_params.x;
  let glowIntensity = u.zoom_params.y;
  let hueShiftParam = u.zoom_params.z;
  let brushSize = u.zoom_params.w;

  // Structure tensor flow
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

  // Mouse vortex + brush
  let aspect = res.x / res.y;
  let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let baseBrush = smoothstep(brushSize, brushSize * 0.5, dist);
  let isMouseDown = mouseDown > 0.5;
  let brush = baseBrush * (select(0.5, 1.0, isMouseDown));

  // Mouse disturbs flow
  let mouseFactor = exp(-dist * dist * 8.0);
  let mouseAngle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
  let vortex = vec2<f32>(-sin(mouseAngle), cos(mouseAngle)) * mouseFactor;
  eigenvec = normalize(mix(eigenvec, vortex, mouseFactor * 0.5));

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

  // LIC along flow
  let licValue = lic(uv, eigenvec, pixelSize, 16, 1.5);

  // History
  let historyColor = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

  // Trace color follows flow angle
  let flowAngle = atan2(eigenvec.y, eigenvec.x) * 0.15915 + 0.5;
  let drawColor = hslToRgb(fract(flowAngle + hueShiftParam + time * 0.05), 1.0, 0.5);

  // Add brush to history, decay along flow
  let flowDecay = decaySpeed * (0.8 + 0.2 * coherency);
  let newHistory = clamp(historyColor.rgb * flowDecay + drawColor * brush, vec3<f32>(0.0), vec3<f32>(2.0));

  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newHistory, 1.0));

  // Composition: input + glowing trace tinted by LIC
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let traceTint = mix(vec3<f32>(1.0, 0.9, 0.7), vec3<f32>(0.7, 0.9, 1.0), flowAngle);
  let finalColor = inputColor + newHistory * glowIntensity * traceTint * (0.5 + 0.5 * licValue);

  let boostedCoherency = pow(coherency, 0.5);
  let alpha = boostedCoherency * (0.5 + 0.5 * licValue);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
