@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // mouseX, mouseY, isMouseDown, padding
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Aspect ratio correction
  let aspect = resolution.x / resolution.y;
  var p = uv * 2.0 - 1.0;
  p.x *= aspect;

  var mouse = vec2<f32>(u.zoom_config.x, u.zoom_config.y) * 2.0 - 1.0;
  mouse.x *= aspect;

  // Background
  var color = vec3<f32>(0.05, 0.05, 0.1);

  // Orb
  let dist = length(p - mouse);
  let radius = 0.3 + 0.05 * sin(time * 3.0);
  let glow = 0.02 / (dist * dist + 0.001);

  // Core
  let core = smoothstep(radius, radius - 0.05, dist);

  // Dynamic color
  let orbColor = 0.5 + 0.5 * vec3<f32>(sin(time), cos(time * 1.3), sin(time * 0.7));

  color += orbColor * glow;
  color = mix(color, vec3<f32>(1.0), core);

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
