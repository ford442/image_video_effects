// ═══════════════════════════════════════════════════════════════════
//  data-stream-structure
//  Category: advanced-hybrid
//  Features: mouse-driven, structure-tensor, LIC, glitch
//  Complexity: Very High
//  Chunks From: data-stream.wgsl, conv-structure-tensor-flow.wgsl
//  Created: 2026-04-18
//  By: Agent CB-17
// ═══════════════════════════════════════════════════════════════════
//  Digital data streams that flow along the dominant texture
//  orientation computed by structure tensor eigenvectors. Each strip
//  follows the local flow field, creating data that aligns with
//  edges and structures in the image.
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

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;

  let speed = u.zoom_params.x;
  let density = u.zoom_params.y;
  let turbulence = u.zoom_params.z;
  let glow = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let interactDist = distance(uv, mousePos);
  let interactRadius = 0.3;
  let interact = smoothstep(interactRadius, 0.0, interactDist) * turbulence;

  // Compute structure tensor for flow direction
  let tensor = smoothTensor(uv, pixelSize);
  let Jxx = tensor.x;
  let Jyy = tensor.y;
  let Jxy = tensor.z;

  let trace = Jxx + Jyy;
  let det = Jxx * Jyy - Jxy * Jxy;
  let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
  let lambda1 = (trace + diff) * 0.5;

  var eigenvec = vec2<f32>(1.0, 0.0);
  if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
    eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
  }

  // Data strips aligned with eigenvector
  let numStrips = 20.0 + density * 100.0;
  let stripIdx = floor(dot(uv, eigenvec) * numStrips);
  let rand = fract(sin(stripIdx * 12.9898) * 43758.5453);

  let flowSpeed = (rand * 0.5 + 0.5) * speed * 0.5;
  let perp = vec2<f32>(-eigenvec.y, eigenvec.x);

  let xOffset = interact * sin(dot(uv, perp) * 10.0 + time * 5.0) * 0.05;

  var sampleUV = uv;
  sampleUV = sampleUV + eigenvec * (time * flowSpeed);
  sampleUV = sampleUV + perp * xOffset;

  // Wrap along flow direction
  sampleUV = fract(sampleUV);

  if (rand > 0.8) {
    sampleUV = sampleUV + eigenvec * (sin(time * 10.0) * 0.01);
  }

  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let lum = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let digitalColor = vec3<f32>(0.0, lum * 1.5, lum * 0.2);

  let blockCoord = floor(uv * 50.0);
  let noise = hash12(vec2<f32>(stripIdx, blockCoord.y) + vec2<f32>(0.0, time));
  let bright = step(0.98, noise * (sin(time * 2.0 + stripIdx) * 0.5 + 0.5));

  let finalRGB = mix(color.rgb, digitalColor, glow);
  let outputColor = finalRGB + vec3<f32>(0.0, bright * glow, 0.0);

  // Color by flow direction
  let flowAngle = atan2(eigenvec.y, eigenvec.x) * 0.15915 + 0.5;
  let flowColor = palette(flowAngle, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
  let finalColor = mix(outputColor, flowColor * lum * 2.0, glow * 0.3);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
