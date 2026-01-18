@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let aspect = resolution.x / resolution.y;
  var p = uv * 2.0 - 1.0;
  p.x *= aspect;

  var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
  mouse.x *= aspect;

  // Distort space near mouse
  let d = length(p - mouse);
  let force = 0.5 * smoothstep(0.5, 0.0, d);
  p += (p - mouse) * force * sin(time * 2.0);

  // Grid
  let gridSize = 10.0;
  // Simple thickness without derivatives
  let thickness = 0.05;
  let grid = abs(fract(p * gridSize - 0.5) - 0.5);
  let line = min(grid.x, grid.y);
  let gridIntensity = 1.0 - smoothstep(0.0, thickness, line);

  var color = vec3<f32>(0.0);

  // Neon Blue/Pink
  let neon = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(time + p.x)*0.5 + 0.5);

  color = neon * gridIntensity;

  // Glow
  color += neon * 0.2 * (1.0 - smoothstep(0.0, 0.5, line));

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
