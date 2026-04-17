struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = u.config.z / u.config.w;

  var mouse = u.zoom_config.yz;

  // Params
  let strength = u.zoom_params.x * 5.0;
  let radius = u.zoom_params.y;
  let darkness = u.zoom_params.z;
  let audioReact = u.zoom_params.w;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let reactiveStrength = strength * (1.0 + bass * audioReact);

  // Center calc
  let uv_centered = uv - mouse;
  let uv_corrected = vec2<f32>(uv_centered.x * aspect, uv_centered.y);
  let dist = length(uv_corrected);

  // Angle
  let angle = atan2(uv_corrected.y, uv_corrected.x);

  // Twist formula
  let influence = exp(-dist * (10.0 * (1.1 - radius)));
  let twist = reactiveStrength * influence;
  let final_angle = angle + twist;

  // Convert back
  let new_uv_corrected = vec2<f32>(cos(final_angle), sin(final_angle)) * dist;
  let new_uv = vec2<f32>(new_uv_corrected.x / aspect, new_uv_corrected.y) + mouse;

  var color = textureSampleLevel(readTexture, u_sampler, new_uv, 0.0);

  // Apply "Event Horizon" darkness while preserving alpha
  let hole_size = 0.05 * darkness;
  if (dist < hole_size) {
      color = vec4<f32>(0.0);
  } else if (dist < hole_size * 2.0) {
      let edge = smoothstep(hole_size, hole_size * 2.0, dist);
      color = vec4<f32>(color.rgb * edge, color.a);
      color.a *= edge;
  }

  textureStore(writeTexture, coord, color);

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
