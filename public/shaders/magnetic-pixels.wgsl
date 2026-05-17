// ═══════════════════════════════════════════════════════════════════
//  Magnetic Pixels
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Upgraded: 2026-05-17
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let strength = max(u.zoom_params.x * 0.5, 0.0) * (1.0 + bass * 0.4);
  let radius = max(u.zoom_params.y * 0.5, 0.01);
  let hardness = u.zoom_params.z * 10.0 + 1.0;
  let chaos = u.zoom_params.w;

  let hasMouse = mousePos.x >= 0.0 && strength > 0.0;
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
  let isInside = dist < radius;

  let t = dist / max(radius, 0.001);
  let force = pow(1.0 - t, hardness);
  let dir = normalize(dVec + vec2<f32>(0.0001));
  let noise = select(0.0, (hash12(uv * 100.0 + u.config.x) - 0.5) * chaos * 0.1, chaos > 0.0);

  let distortion = select(vec2<f32>(0.0), dir * force * strength + vec2<f32>(noise), hasMouse && isInside);
  let sampleUV = clamp(uv - distortion, vec2<f32>(0.0), vec2<f32>(1.0));

  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let dispMag = length(distortion);
  let tint = vec3<f32>(1.0 + mids * 0.2, 1.0, 1.0 - mids * 0.2);
  let final_rgb = color.rgb * tint;
  let alpha = clamp(color.a + dispMag * 2.0, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(final_rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(final_rgb, alpha));
}
