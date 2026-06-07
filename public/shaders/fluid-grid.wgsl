// ═══════════════════════════════════════════════════════════════════
//  Fluid Grid
//  Category: distortion
//  Features: mouse-driven, audio-reactive, curl-noise, divergence-free, upgraded-rgba
//  Complexity: High
//  Chunks From: fluid-grid, curl2D, fbm, bass_env
//  Upgraded: 2026-05-31
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

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = fbm(p + vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n2 = fbm(p - vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n3 = fbm(p + vec2<f32>(0.0, eps) + t * 0.1, 3);
  let n4 = fbm(p - vec2<f32>(0.0, eps) + t * 0.1, 3);
  let dy = (n1 - n2) / (2.0 * eps);
  let dx = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dx, -dy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let gridSize = 10.0 + u.zoom_params.x * 90.0 * bass_env(bass, mids);
    let viscosity = u.zoom_params.y;
    let repulsion = u.zoom_params.z;
    let restitution = u.zoom_params.w;

    let tileUV = floor(uv * gridSize) / gridSize;
    let tileCenter = tileUV + vec2<f32>(0.5 / gridSize, 0.5 / gridSize);
    let distVec = tileCenter - mousePos;
    let distVecCorrected = vec2<f32>(distVec.x * aspect, distVec.y);
    let dist = length(distVecCorrected);
    let offsetDir = distVecCorrected / max(dist, 0.001);
    let push = smoothstep(0.45 + restitution * 0.1, 0.0, dist) * repulsion * (0.12 + bass * 0.04);

    let curl = curl2D(uv * 2.5, u.config.x * 0.15) * 0.03 * bass_env(bass, mids);
    let uvOffset = vec2<f32>(offsetDir.x / aspect, offsetDir.y) * push + curl;
    let sampleUV = clamp(uv - uvOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let gridLine = fract(uv * gridSize);
    let cellEdge = min(min(gridLine.x, 1.0 - gridLine.x), min(gridLine.y, 1.0 - gridLine.y));
    let lineWeight = 0.015 + (1.0 - viscosity) * 0.035;
    let lineMask = 1.0 - smoothstep(lineWeight, lineWeight + 0.01, cellEdge);

    let flowColor = vec3<f32>(0.05 + treble * 0.1, 0.15 + mids * 0.1, 0.28 + bass * 0.1) * lineMask;
    let finalColor = mix(baseColor.rgb, baseColor.rgb * 0.45 + flowColor, lineMask * 0.7);
    let alpha = clamp(baseColor.a * 0.45 + push * 1.8 + lineMask * 0.12 + bass * 0.05, 0.08, 1.0);

    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + push * 0.2, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
