// ----------------------------------------------------------------
// Psychedelic Layered Time-Stamps
// Category: generative
// ----------------------------------------------------------------

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
  let time = u.config.x;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let mouse = u.zoom_config.yz;

  let layer_count = i32(u.zoom_params.x * 10.0 + 3.0);
  let delay_scale = u.zoom_params.y;
  let distortion_amp = u.zoom_params.z;

  var final_color = vec3<f32>(0.0);

  // Create rippling distortion based on audio and time
  let dist_offset = vec2<f32>(
    sin(uv.y * 10.0 + time) * distortion_amp * (1.0 + bass * 2.0),
    cos(uv.x * 10.0 + time) * distortion_amp * (1.0 + bass * 2.0)
  );

  let distorted_uv = uv + dist_offset;
  let sample_coords = vec2<i32>(distorted_uv * resolution);

  // Fetch delay info
  let delay_info = textureLoad(dataTextureC, coord, 0);
  let current_delay = delay_info.x + (bass * 0.1);

  // Sample base image with distortion
  let base_color = textureLoad(readTexture, clamp(sample_coords, vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1)), 0).rgb;

  // Calculate layer contribution
  for(var i = 0; i < 10; i = i + 1) {
    if (i >= layer_count) { break; }
    let layer_factor = f32(i) / f32(layer_count);

    let color_shift_raw = time * 0.1 + layer_factor;
    let color_shift = color_shift_raw - floor(color_shift_raw);
    let plasma_idx = i32(color_shift * 255.0);
    let plasma_color = plasmaBuffer[plasma_idx].rgb;

    let layer_weight = exp(-current_delay * delay_scale * f32(i));

    final_color += base_color * plasma_color * layer_weight;
  }

  final_color = final_color / f32(layer_count);

  // Mouse interaction - adds local disturbance
  let mouse_dist = distance(uv, mouse);
  let isMouseActive = mouse_dist < 0.1 && u.zoom_config.w > 0.5;
  final_color += vec3<f32>(1.0 - mouse_dist * 10.0) * bass * select(0.0, 1.0, isMouseActive);

  // Update delay texture (simple temporal evolution)
  let delay_track = textureLoad(dataTextureC, coord, 0);
  let delay_raw = delay_track.x + 0.01;
  let new_delay = delay_raw - floor(delay_raw);
  textureStore(dataTextureA, coord, vec4<f32>(new_delay, 0.0, 0.0, 1.0));

  // Alpha: psychedelic layer accumulation brightness drives temporal blend weight
  let luma = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.6 + current_delay * 0.2 + 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(final_color, alpha));

  // Depth pass-through
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
