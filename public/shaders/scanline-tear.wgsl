struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var u_sampler: sampler;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn rand(n: f32) -> f32 {
  return fract(sin(n) * 43758.5453123);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Params
  let intensity = u.zoom_params.x * 0.5; // Max shift 0.5 screen width
  let strip_count = mix(10.0, 200.0, u.zoom_params.y);
  let noise_speed = u.zoom_params.z * 10.0;
  let rgb_split = u.zoom_params.w * 0.05;

  let mouse = u.zoom_config.yz;
  let time = u.config.x;

  // Strip calculation
  let strip_idx = floor(uv.y * strip_count);

  // Noise per strip
  let noise_val = rand(strip_idx + floor(time * noise_speed));
  let shift_dir = sign(noise_val - 0.5); // -1 or 1

  // Influence based on vertical distance to mouse
  let dist_y = abs(uv.y - mouse.y);
  let influence = smoothstep(0.3, 0.0, dist_y); // Strongest near mouse Y

  // Also modulate by mouse X to control "width" or "scatter" of tear
  // Or simply let mouse X be global intensity multiplier?
  // Let's make mouse X control the horizontal center of the disturbance? No, mouse Y is row.
  // Let's use mouse X for frequency modulation? No.
  // Let's just use influence.

  let tear_offset = (noise_val - 0.5) * intensity * influence;

  // Apply RGB split
  let uv_r = vec2<f32>(uv.x + tear_offset - rgb_split * influence, uv.y);
  let uv_g = vec2<f32>(uv.x + tear_offset, uv.y);
  let uv_b = vec2<f32>(uv.x + tear_offset + rgb_split * influence, uv.y);

  // Sample with clamp-to-edge (default sampler behavior usually)
  // Or handle wrapping. Assuming clamp or repeat.

  let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

  textureStore(writeTexture, coord, vec4<f32>(r, g, b, 1.0));
}
