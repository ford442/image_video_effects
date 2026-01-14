@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;

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

  // Read history (trail)
  let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  let aspect = resolution.x / resolution.y;
  var p = uv * 2.0 - 1.0;
  p.x *= aspect;

  var mouse = vec2<f32>(u.zoom_config.x, u.zoom_config.y) * 2.0 - 1.0;
  mouse.x *= aspect;

  let d = length(p - mouse);

  // Brush
  let brushSize = 0.05;
  let intensity = smoothstep(brushSize, 0.0, d);

  // Color cycle
  let brushColor = 0.5 + 0.5 * vec3<f32>(sin(time), sin(time + 2.0), sin(time + 4.0));

  // Mix history
  // Fade out slowly
  var newColor = history.rgb * 0.98;

  // Add brush
  newColor = max(newColor, brushColor * intensity);

  // Click to explode/clear?
  if (u.zoom_config.z > 0.5) {
     // Mouse Down - maybe expand brush or emit particles
     // For now, just make it brighter
     newColor += brushColor * intensity * 2.0;
  }

  let output = vec4<f32>(newColor, 1.0);

  // Write to Output AND History
  textureStore(writeTexture, global_id.xy, output);
  textureStore(dataTextureA, global_id.xy, output);
}
