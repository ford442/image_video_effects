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
  config: vec4<f32>,              // x=time, y=frame/mouseMode, z=resX, w=resY
  zoom_config: vec4<f32>,         // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,         // User params 1-4
  ripples: array<vec4<f32>, 50>,  // Mouse clicks
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let mousePos = u.zoom_config.yz; // Mouse coordinate 0-1
  // Correct aspect ratio for distance calculation
  let aspect = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
  let dist = distance(uv_corrected, mouse_corrected);

  // Params
  let separation_strength = u.zoom_params.x * 0.1; // 0.0 - 0.1
  let trail_decay = mix(0.5, 0.99, u.zoom_params.y);
  let hue_shift_speed = u.zoom_params.z;
  let mouse_influence = u.zoom_params.w;

  // Calculate RGB offset based on mouse distance and time
  let influence = smoothstep(0.5, 0.0, dist) * mouse_influence;
  let offset_base = vec2<f32>(
    sin(time * 2.0 + dist * 10.0),
    cos(time * 1.5 + dist * 10.0)
  ) * (separation_strength + influence * 0.05);

  let r = textureSampleLevel(readTexture, u_sampler, uv + offset_base, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv - offset_base, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Temporal Persistence (Trails)
  // Read previous frame from dataTextureC (binding 9)
  let prev_color = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;

  // Mix current frame with previous frame
  // If separation is high, we leave more "ghosts"
  color = mix(color, prev_color, trail_decay);

  // Write to output
  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  // Write to persistence buffer (dataTextureA -> binding 7)
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, 1.0));

  // Passthrough depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
