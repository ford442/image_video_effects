// ═══════════════════════════════════════════════════════════════════
//  Voronoi Multi-Focal Selective
//  Category: image
//  Features: mouse-driven, depth-aware, temporal
//  Complexity: High
//  Upgraded by: Optimizer Agent
//  Date: 2026-05-03
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
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
  return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453);
}
fn valueNoise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0; var a = 0.5;
  var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  var pos = p;
  for(var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise2D(pos);
    pos = rot * pos * 2.0 + 100.0;
    a = a * 0.5;
  }
  return v;
}
fn voronoi(uv: vec2<f32>, time: f32) -> vec2<f32> {
  let i = floor(uv);
  let f = fract(uv);
  var minDist = 1.0;
  var cellId = vec2<f32>(0.0);
  for(var y: i32 = -1; y <= 1; y = y + 1) {
    for(var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let point = neighbor + hash22(i + neighbor);
      let diff = point - f;
      let dist = length(diff);
      let closer = f32(dist < minDist);
      minDist = mix(minDist, dist, closer);
      cellId = mix(cellId, i + neighbor, closer);
    }
  }
  return vec2<f32>(minDist, hash12(cellId));
}
fn sdStar(p: vec2<f32>, points: f32, inner_r: f32, outer_r: f32) -> f32 {
  let angle = atan2(p.y, p.x);
  let sector = 3.14159265 / points;
  let a = fract(angle / (2.0 * sector)) * 2.0 * sector - sector;
  let r = mix(inner_r, outer_r, smoothstep(-0.1, 0.1, a));
  return length(p) - r;
}
fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
  let k = vec3<f32>(-0.8660254, 0.5, 0.57735027);
  let q = abs(p);
  let d = dot(k.xy, q);
  return max(d, q.y) - r * k.z;
}
fn chromaticSplit(uv: vec2<f32>, offset: vec2<f32>) -> vec3<f32> {
  let r = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv - offset, 0.0).b;
  return vec3<f32>(r, g, b);
}
fn depthSobel(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
  let d00 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).r;
  let d10 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>( texel.x, -texel.y), 0.0).r;
  let d01 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x,  texel.y), 0.0).r;
  let d11 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>( texel.x,  texel.y), 0.0).r;
  let dx = (d11 + d10) - (d01 + d00);
  let dy = (d11 + d01) - (d10 + d00);
  return clamp(length(vec2<f32>(dx, dy)) * 3.0, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let radius = u.zoom_params.x;
  let softness = max(u.zoom_params.y * 0.25, 0.001);
  let desatStrength = u.zoom_params.z;
  let feather = u.zoom_params.w;

  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let grayVec = vec3<f32>(gray);

  // 1. Voronoi-based multi-focal organic desaturation regions
  let vScale = mix(4.0, 14.0, radius);
  let vUV = uv * vScale + mouse * 3.0 + sin(time * 0.2) * 0.5;
  let voro = voronoi(vUV, time);
  let voroMask = smoothstep(0.45, 0.45 - softness, voro.x);

  // 2. Fractal noise masking for irregular organic shapes
  let fbmVal = fbm(uv * 5.0 + time * 0.15, 5);
  let fbmMask = smoothstep(0.35, 0.35 + softness, fbmVal);

  // 3. Polar coordinate angular sector reveals
  let centered = uv - mouse;
  let polarAngle = atan2(centered.y, centered.x);
  let sectorCount = mix(2.0, 10.0, feather);
  let sectorAngle = 6.2831853 / sectorCount;
  let sectorFrac = fract(polarAngle / sectorAngle);
  let polarMask = 1.0 - smoothstep(0.5 - softness * 0.5, 0.5 + softness * 0.5, abs(sectorFrac - 0.5));

  // 4. SDF shape library: hexagon ↔ star morph
  let sdfUV = centered * vec2<f32>(aspect, 1.0);
  let shapeSize = mix(0.12, 0.45, radius);
  let hexD = sdHexagon(sdfUV, shapeSize);
  let starD = sdStar(sdfUV, 5.0, shapeSize * 0.35, shapeSize);
  let shapeMorph = smoothstep(0.3, 0.7, feather * 2.0);
  let shapeD = mix(hexD, starD, shapeMorph);
  let shapeMask = 1.0 - smoothstep(0.0, softness * 2.0, shapeD);

  // 5. Wave propagation reveal from mouse click ripples
  var rippleMask = 0.0;
  let rippleCount = u32(u.config.y);
  let rpAspect = vec2<f32>(aspect, 1.0);
  for(var i: u32 = 0u; i < rippleCount && i < 50u; i = i + 1u) {
    let r = u.ripples[i];
    let rp = (r.xy - uv) * rpAspect;
    let dist = length(rp);
    let age = time - r.z;
    let wave = sin(dist * 35.0 - age * 6.0) * 0.5 + 0.5;
    let decay = exp(-age * 1.8);
    let localMask = wave * decay * smoothstep(0.6, 0.0, dist);
    rippleMask = max(rippleMask, localMask);
  }

  // Aggregate masks with organic blending
  let baseMask = max(max(voroMask, fbmMask * 0.6), max(polarMask, shapeMask));
  let combinedMask = clamp(baseMask + rippleMask, 0.0, 1.0);
  let edgeDist = abs(combinedMask - 0.5) * 2.0;
  let boundary = 1.0 - smoothstep(0.0, 0.25, edgeDist);

  // 6. Chromatic aberration reveal at desaturation boundaries
  let caOffset = boundary * softness * 0.025;
  let caColor = chromaticSplit(uv, vec2<f32>(caOffset, 0.0));

  // 7. Depth-aware edge detection via Sobel operator
  let texel = 1.0 / resolution;
  let edgeMag = depthSobel(uv, texel);

  // Final composite
  let desatColor = mix(caColor, grayVec, desatStrength);
  let finalRGB = mix(desatColor, caColor, combinedMask);
  let edgeTint = vec3<f32>(1.0, 0.92, 0.75) * edgeMag * combinedMask * 0.4;
  let finalAlpha = mix(color.a * (1.0 - desatStrength * 0.2), color.a, combinedMask);
  let finalColor = vec4<f32>(finalRGB + edgeTint, finalAlpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
