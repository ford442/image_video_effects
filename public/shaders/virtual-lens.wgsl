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
  let mouse = u.zoom_config.yz;

  // Params
  let magnification = u.zoom_params.x * 0.8; // 0.0 to 0.8
  let radius = u.zoom_params.y;              // Lens size
  let aberration = u.zoom_params.z * 0.05;   // Chromatic sep
  let softness = u.zoom_params.w * 0.2;      // Edge blending

  // Aspect correct calculation for circular lens
  var uv_corrected = uv;
  uv_corrected.x *= aspect;
  var mouse_corrected = mouse;
  mouse_corrected.x *= aspect;

  let dist = distance(uv_corrected, mouse_corrected);

  // Mask: 1.0 at center, 0.0 outside radius
  let mask = smoothstep(radius + softness, radius, dist);

  // Bulge Function
  // We want to pull pixels closer to center.
  // Sample coord = uv - (dir * amount)
  let dir = uv - mouse;

  // Parabolic falloff for bulge
  // At center (dist=0), deformation is max?
  // Actually, magnification means we see a smaller area of the source texture stretched to fill the lens.
  // So we sample closer to the mouse position.
  // sample_pos = mouse + (uv - mouse) / zoom

  // Let's interpret 'magnification' as the 'strength of the lens curvature'.
  // Simple displacement:
  let distortion = sin(mask * 1.57) * magnification;

  // Apply chromatic aberration
  let r_uv = uv - dir * distortion * (1.0 + aberration);
  let g_uv = uv - dir * distortion;
  let b_uv = uv - dir * distortion * (1.0 - aberration);

  // Read texture
  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

  // Add a subtle glass shine/specular
  let specular = smoothstep(radius - 0.02, radius, dist) * smoothstep(radius, radius - 0.02, dist);
  // This just makes a ring.
  // Let's make a rim.
  let rim = smoothstep(radius * 0.9, radius, dist) * mask * 0.2;

  var color = vec3<f32>(r, g, b) + vec3(rim);

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  // Depth pass
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
