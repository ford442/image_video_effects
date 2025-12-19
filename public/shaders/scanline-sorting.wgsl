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
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Params
  let sort_threshold = u.zoom_params.x; // Luma threshold
  let scan_width = u.zoom_params.y * 0.2; // Width of the sorting band
  let scan_speed = u.zoom_params.z;
  let direction_toggle = u.zoom_params.w; // < 0.5 horizontal, >= 0.5 vertical

  // Scanline position
  var scan_pos = 0.0;
  if (scan_speed > 0.01) {
    scan_pos = fract(time * scan_speed);
  } else {
    // If speed is 0, control with mouse Y
    scan_pos = u.zoom_config.z;
  }

  // Determine if this pixel is inside the sort band
  var dist_to_scan = abs(uv.y - scan_pos);
  if (direction_toggle >= 0.5) {
     dist_to_scan = abs(uv.x - scan_pos); // Vertical sort scan moving horizontally
  }

  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  if (dist_to_scan < scan_width) {
    // Pixel Sort Logic (Simplified for shader)
    // True pixel sorting requires iterative passes or bitonic sort buffers.
    // Here we simulate it by sampling a neighbor based on luma difference.
    // If we are "brighter" than neighbor, swap (drift).

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));

    // Sample "previous" pixel in sort direction
    var offset = vec2<f32>(0.0, -1.0/resolution.y);
    if (direction_toggle >= 0.5) {
        offset = vec2<f32>(-1.0/resolution.x, 0.0);
    }

    // Scale offset by brightness to simulate "falling" pixels
    let sort_strength = smoothstep(sort_threshold, 1.0, luma) * 20.0;
    let sample_pos = uv + offset * sort_strength;

    // If the sampled position is valid, blend
    if (sample_pos.x >= 0.0 && sample_pos.x <= 1.0 && sample_pos.y >= 0.0 && sample_pos.y <= 1.0) {
       let neighbor = textureSampleLevel(readTexture, u_sampler, sample_pos, 0.0).rgb;
       let neighbor_luma = dot(neighbor, vec3<f32>(0.299, 0.587, 0.114));

       if (luma > neighbor_luma) {
         color = neighbor; // "Swap" (actually just copy, creating a trail)
       }
    }
  }

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
