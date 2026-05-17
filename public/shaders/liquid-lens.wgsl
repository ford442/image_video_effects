// ═══════════════════════════════════════════════════════════════════
//  Liquid Lens
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let strength = u.zoom_params.x * (1.0 + bass * 0.2);
  let radius = u.zoom_params.y;
  let abberation = u.zoom_params.z;
  let edgeDarken = u.zoom_params.w;

  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uvCorrected, mouseCorrected);

  let lensMask = smoothstep(radius, radius * 0.8, dist);
  let h = sqrt(max(0.0, radius*radius - dist*dist));
  let nd = dist / max(radius, 0.001);
  let distortion = pow(nd, 2.0) * strength * 0.5 * (1.0 - smoothstep(radius*0.9, radius, dist));

  var dir = normalize(uv - mouse + vec2<f32>(0.0001));
  let baseOffset = -dir * distortion * lensMask;
  let ca = abberation * 0.02 * lensMask * nd;

  let uvR = clamp(uv + baseOffset * (1.0 + ca), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv + baseOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + baseOffset * (1.0 - ca), vec2<f32>(0.0), vec2<f32>(1.0));

  let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
  var color = vec3<f32>(r, g, b);

  let rim = smoothstep(radius * 0.8, radius, dist);
  let isInside = dist < radius;
  color = select(color, color * (1.0 - rim * edgeDarken), isInside);

  let N = vec3<f32>((uvCorrected - mouseCorrected)/max(radius, 0.001), h/max(radius, 0.001));
  let spec = pow(max(0.0, dot(normalize(N), vec3<f32>(-0.2, -0.2, 1.0))), 20.0);
  color += select(vec3<f32>(0.0), vec3<f32>(spec * 0.2), isInside);

  let alpha = clamp(lensMask * 0.7 + (1.0 - lensMask) * 0.5 + mids * 0.1, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
