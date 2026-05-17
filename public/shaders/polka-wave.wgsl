// ═══════════════════════════════════════════════════════════════════
//  Polka Wave
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let density = mix(20.0, 150.0, u.zoom_params.x);
  let amp = u.zoom_params.y * (1.0 + bass * 0.3);
  let freq = mix(5.0, 50.0, u.zoom_params.z);
  let speed = mix(0.5, 5.0, u.zoom_params.w);

  let grid_uv = uv * vec2<f32>(aspect, 1.0) * density;
  let cell_id = floor(grid_uv);
  let cell_uv = fract(grid_uv) - 0.5;

  let center_pos = (cell_id + 0.5) / density;
  let sample_uv = vec2<f32>(center_pos.x / aspect, center_pos.y);

  let texColor = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
  let brightness = dot(texColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(center_pos, mouse_aspect);
  let wave = sin(dist * freq - time * speed);

  var radius = brightness * 0.45;
  radius = radius + wave * 0.2 * amp;
  radius = clamp(radius, 0.05, 0.5);

  let dist_to_center = length(cell_uv);
  let aa = 0.7 / density;
  let circle = 1.0 - smoothstep(radius - aa, radius + aa, dist_to_center);

  let finalColor = vec4<f32>(texColor.rgb * circle, texColor.a * circle + (1.0 - circle) * 0.1 + mids * 0.1);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalColor);
}
