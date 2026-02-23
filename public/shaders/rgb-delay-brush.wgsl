struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / u.config.w;

  let mouse = u.zoom_config.yz;

  // Params
  let persistence = u.zoom_params.x; // High = old frame stays longer (global)
  let split = u.zoom_params.y; // Strength of RGB separation (brush)
  let radius = u.zoom_params.z * 0.5;

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Calculate Brush Mask
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = length(uv_corrected - mouse_corrected);

  let mask = smoothstep(radius, radius * 0.5, dist); // 1.0 inside, 0.0 outside

  // Calculate reaction speeds for each channel.
  // Speed 1.0 = Instant update (Current frame).
  // Speed 0.01 = Very slow update (Trails).

  // Base fade speed depends on persistence
  // map persistence 0.5->0.99 to speed 0.5 -> 0.01
  let base_speed = (1.0 - persistence) * 2.0;

  // Apply RGB split based on mask
  // We want the Red channel to be fastest, Blue slowest (or vice versa) to create fringe.

  // Inside brush (mask=1), we slow down G and B significantly more if split is high.

  let s_r = base_speed;
  let s_g = max(0.005, base_speed - (mask * split * 0.05));
  let s_b = max(0.001, base_speed - (mask * split * 0.1));

  var new_color = vec4<f32>(0.0);
  new_color.r = mix(prev.r, current.r, clamp(s_r, 0.0, 1.0));
  new_color.g = mix(prev.g, current.g, clamp(s_g, 0.0, 1.0));
  new_color.b = mix(prev.b, current.b, clamp(s_b, 0.0, 1.0));
  new_color.a = 1.0;

  textureStore(dataTextureA, coord, new_color);
  textureStore(writeTexture, coord, new_color);

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
