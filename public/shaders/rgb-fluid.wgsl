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
  let flow_speed = u.zoom_params.x * 0.01;  // Speed of advection
  let decay = u.zoom_params.y;              // Viscosity/Persistence (0.9 - 0.99)
  let mouse_force = u.zoom_params.z;        // Strength of mouse push
  let color_shift = u.zoom_params.w;        // Hue rotation speed

  // Generate a pseudo-random flow field using sines
  let scale = 5.0;
  let field_x = sin(uv.y * scale + time) + cos(uv.x * scale * 2.0);
  let field_y = cos(uv.x * scale + time) + sin(uv.y * scale * 2.0);
  var velocity = vec2<f32>(field_x, field_y) * flow_speed;

  // Mouse Repulsion
  // Aspect correct vector
  var uv_corrected = uv;
  uv_corrected.x *= aspect;
  var mouse_corrected = mouse;
  mouse_corrected.x *= aspect;

  let dist = distance(uv_corrected, mouse_corrected);
  let to_pixel = normalize(uv_corrected - mouse_corrected); // Direction FROM mouse

  // Force falls off with distance
  let push = to_pixel * smoothstep(0.4, 0.0, dist) * mouse_force * 0.05;

  if (dist > 0.001) {
    velocity += push;
  }

  // Advection: Sample history backwards along velocity
  // dataTextureC is the history buffer (read-only this frame)
  // We offset UV by velocity
  let advect_uv = uv - velocity;
  let history = textureSampleLevel(dataTextureC, u_sampler, advect_uv, 0.0).rgb;

  // Current input
  let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Mix input into history
  // If decay is 0.0, we see mostly input. If decay is 1.0, we see mostly history.
  // We want to continuously inject input.
  // Formula: New = History * Decay + Input * (1 - Decay)
  // But for "fluid", we want accumulation.

  // Let's interpret 'decay' as persistence.
  let persistence = 0.9 + (decay * 0.09); // Map 0..1 to 0.9..0.99

  var new_color = mix(input, history, persistence);

  // Color Shift (Hue rotation approx)
  if (color_shift > 0.0) {
      let shift_amt = color_shift * 0.01;
      // Simple RGB rotation
      let r = new_color.r;
      let g = new_color.g;
      let b = new_color.b;
      new_color.r = r * cos(shift_amt) - g * sin(shift_amt) + 0.001; // prevent 0
      new_color.g = g * cos(shift_amt) - b * sin(shift_amt) + 0.001;
      new_color.b = b * cos(shift_amt) - r * sin(shift_amt) + 0.001;
      new_color = abs(new_color); // Keep positive
  }

  textureStore(writeTexture, global_id.xy, vec4<f32>(new_color, 1.0));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(new_color, 1.0));

  // Depth pass
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
