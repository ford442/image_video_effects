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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;

  // Mouse coordinates (0-1)
  let mouse = u.zoom_config.yz;

  // Aspect-corrected distance calculation
  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let d = distance(uv_aspect, mouse_aspect);

  // Parameters
  let radius = u.zoom_params.x;      // Default: 0.3
  let softness = u.zoom_params.y;    // Default: 0.1
  let desat_strength = u.zoom_params.z; // Default: 1.0 (Full gray outside)

  // Calculate mask: 1.0 inside radius, 0.0 outside (with smooth edge)
  // smoothstep(edge0, edge1, x) returns 0 if x < edge0, 1 if x > edge1
  // We want 1 when d < radius.
  // So we use smoothstep(radius, radius - softness, d)
  // If d = radius, val is 0. If d = radius - softness, val is 1.
  let mask = smoothstep(radius, radius - softness, d);

  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let gray_vec = vec3<f32>(gray);

  // Background is desaturated by 'desat_strength'
  let background = mix(color.rgb, gray_vec, desat_strength);

  // Final composite: if mask is 1, show original color. if 0, show background.
  let final_color = mix(background, color.rgb, mask);

  textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));

  // Pass through depth texture
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
