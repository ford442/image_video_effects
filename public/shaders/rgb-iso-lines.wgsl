// --- COPY PASTE THIS HEADER ---
struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ------------------------------

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Parameters
  let thickness = mix(0.01, 0.45, u.zoom_params.x);
  let freq = mix(5.0, 50.0, u.zoom_params.y);
  let parallax_amt = mix(0.0, 0.1, u.zoom_params.z);

  // Mouse
  let mouse = u.zoom_config.yz;

  // Parallax Offset based on mouse distance from center
  let offset = (mouse - vec2<f32>(0.5)) * parallax_amt;

  // Sample R (Shifted +)
  let uv_r = uv + offset;
  let r_val = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;

  // Sample G (Center)
  let uv_g = uv;
  let g_val = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;

  // Sample B (Shifted -)
  let uv_b = uv - offset;
  let b_val = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

  // Contour Lines
  let dist_r = abs(fract(r_val * freq) - 0.5);
  let dist_g = abs(fract(g_val * freq) - 0.5);
  let dist_b = abs(fract(b_val * freq) - 0.5);

  let line_width = thickness * 0.5; // Scale to 0-0.5 range

  let r_line = smoothstep(0.5 - line_width - 0.02, 0.5 - line_width, dist_r);
  let g_line = smoothstep(0.5 - line_width - 0.02, 0.5 - line_width, dist_g);
  let b_line = smoothstep(0.5 - line_width - 0.02, 0.5 - line_width, dist_b);

  // Composite
  let final_col = vec3<f32>(r_line, g_line, b_line);

  // Add a faint background of original image?
  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb * 0.1;

  textureStore(writeTexture, coord, vec4<f32>(final_col + base, 1.0));
}
