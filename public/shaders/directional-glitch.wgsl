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
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  // Params
  let intensity = u.zoom_params.x;     // Glitch Strength
  let radius = u.zoom_params.y;        // Radius
  let scatter = u.zoom_params.z;       // Scatter/Noise amount
  let angle_bias = u.zoom_params.w;    // Direction rotation

  // Aspect correct dist
  var uv_corrected = uv;
  uv_corrected.x *= aspect;
  var mouse_corrected = mouse;
  mouse_corrected.x *= aspect;

  let dist = distance(uv_corrected, mouse_corrected);

  // Calculate angle from mouse to pixel
  // atan2(y, x)
  let dy = uv.y - mouse.y;
  let dx = uv.x - mouse.x;
  let angle = atan2(dy, dx) + angle_bias * 6.28;

  // Noise generation for glitch blocks
  // Create blocks based on UV
  let block_size = 50.0; // Fixed block size for now
  let block_id = floor(uv * block_size);
  let noise = fract(sin(dot(block_id, vec2(12.9898, 78.233) + time)) * 43758.5453);

  // Strength calculation
  let mask = smoothstep(radius, 0.0, dist);

  // Threshold noise so only some blocks glitch
  let is_glitch = step(1.0 - scatter, noise); // 0 or 1

  // Displacement vector along the radial angle
  let disp_amt = is_glitch * intensity * mask * 0.1;
  let shift = vec2<f32>(cos(angle), sin(angle)) * disp_amt;

  // RGB Split (Chromatic Aberration)
  let r_shift = shift;
  let g_shift = shift * 1.5;
  let b_shift = shift * 2.0;

  let r = textureSampleLevel(readTexture, u_sampler, uv - r_shift, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv - g_shift, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv - b_shift, 0.0).b;

  // Add some static noise on top
  let static_noise = fract(sin(dot(uv * time, vec2(12.9898, 78.233))) * 43758.5453) * mask * intensity * 0.2;

  let final_color = vec3<f32>(r, g, b) + vec3(static_noise);

  textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));

  // Depth pass
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
