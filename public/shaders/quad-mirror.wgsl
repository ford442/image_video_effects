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
  let mouse = u.zoom_config.yz;

  // Quad Mirror Logic
  // The mouse position defines the center of the coordinate system.
  // We reflect everything around the X and Y axes defined by the mouse.

  // Relative coordinates
  let rel_x = uv.x - mouse.x;
  let rel_y = uv.y - mouse.y;

  // Reflect: absolute distance from center
  let abs_x = abs(rel_x);
  let abs_y = abs(rel_y);

  // Sample Coordinate
  // We want to sample from the "positive" quadrant (or whatever quadrant the source image is best in)
  // relative to the mouse?
  // Let's make it so that the image is mirrored around the mouse lines.

  // Simple Kaleidoscope:
  // sample_uv = mouse + vec2(abs_x, abs_y);
  // This mirrors the bottom-right quadrant to all others.

  // Params
  let mode = u.zoom_params.x; // 0 = Mirror, 1 = Repeat?
  let zoom = u.zoom_params.y; // Zoom into the center? 1.0 = Normal

  // Adjust zoom (avoid divide by zero)
  let z = max(0.1, zoom);

  // Scaled offsets
  let off_x = abs_x / z;
  let off_y = abs_y / z;

  // We need to map these back to valid UV space.
  // If we just use mouse + off, we might sample out of bounds.
  // u_sampler usually repeats or clamps. If repeat, we get tiling.

  // Let's try to make a "Quad Mirror" where the image looks symmetrical.
  // We sample at: mouse - offset (to look "inwards"?) or mouse + offset?

  // Let's try:
  let sample_uv = vec2<f32>(
      mouse.x - off_x,
      mouse.y - off_y
  );

  // If we want 4-way symmetry, we just use the calculated sample_uv.
  // The sign of (uv - mouse) determined which quadrant we are in, but we took abs(), so now we are always sampling from top-left relative to mouse.

  let color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);

  textureStore(writeTexture, global_id.xy, color);

  // Pass depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
