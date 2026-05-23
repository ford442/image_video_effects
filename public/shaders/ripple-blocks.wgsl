// --- Ripple Blocks — upgraded-rgba ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let grid_param = u.zoom_params.x;
  let amp_param = u.zoom_params.y;
  let freq_param = u.zoom_params.z;
  let speed_param = u.zoom_params.w;

  let cells = grid_param * 40.0 + 5.0;

  // Grid coords
  let grid_uv = uv * vec2<f32>(cells, cells / aspect);
  let cell_id = floor(grid_uv);
  let cell_center_uv = (cell_id + 0.5) / vec2<f32>(cells, cells / aspect);

  // Distance from cell center to mouse
  let mouse = u.zoom_config.yz;
  let d_vec = (cell_center_uv - mouse);
  let d = length(vec2<f32>(d_vec.x * aspect, d_vec.y));

  // Wave
  let wave_time = time * (speed_param * 5.0);
  let freq = freq_param * 50.0;

  // Wave moves outwards
  let wave = sin(d * freq - wave_time);

  // Amp falls off with distance, modulated by bass
  let falloff = 1.0 / (1.0 + d * 5.0);
  let scale_mod = wave * amp_param * falloff * (1.0 + bass * 0.5);

  let scale = 1.0 - scale_mod * 0.8;

  // Scale UVs relative to cell center
  let uv_centered = uv - cell_center_uv;
  let uv_scaled = uv_centered / max(0.01, scale) + cell_center_uv;

  // Calculate bounds of current cell
  let cell_min = cell_id / vec2<f32>(cells, cells / aspect);
  let cell_max = (cell_id + 1.0) / vec2<f32>(cells, cells / aspect);

  let in_bounds = uv_scaled.x >= cell_min.x && uv_scaled.x <= cell_max.x &&
                  uv_scaled.y >= cell_min.y && uv_scaled.y <= cell_max.y;

  let sampled_color = textureSampleLevel(readTexture, u_sampler, clamp(uv_scaled, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  var color = select(vec4<f32>(0.0, 0.0, 0.0, 1.0), sampled_color, in_bounds);

  // Add shading based on scale/wave
  let light = wave * 0.1;
  color += vec4<f32>(light, light, light, 0.0);

  // Semantic alpha: block edge visibility + wave intensity
  let alpha = select(0.3, 0.9 + abs(scale_mod) * 0.1, in_bounds);

  let finalRGB = color.rgb;

  textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
