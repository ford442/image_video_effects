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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Parameters
  let teeth_size = mix(20.0, 100.0, u.zoom_params.x); // Frequency of teeth
  let opening_width = mix(0.1, 1.0, u.zoom_params.y); // How wide the V opens
  // let fabric_darkness = u.zoom_params.z;

  // Mouse
  let mouse = u.zoom_config.yz;
  let aspect = u.config.z / u.config.w;

  // Zipper Logic
  let dx = (uv.x - mouse.x) * aspect;
  let dy = uv.y - mouse.y; // Negative if above mouse

  var width = 0.0;
  if (dy < 0.0) {
      width = -dy * opening_width; // Linear V shape
  }

  // Zipper Teeth
  let teeth_pattern = step(0.5, fract(uv.y * teeth_size));

  let tooth_amp = 0.02;
  let jagged_width = width + tooth_amp * sin(uv.y * teeth_size * 6.28);

  // Mask
  let edge_dist = abs(dx) - jagged_width;
  let mask = 1.0 - smoothstep(0.0, 0.01, edge_dist); // 1 inside, 0 outside

  // Zipper Slider (The Metal Piece)
  let slider_dist = distance(vec2<f32>((uv.x - mouse.x) * aspect, uv.y), vec2<f32>(0.0, mouse.y));
  let slider_mask = 1.0 - smoothstep(0.03, 0.035, slider_dist);

  // Fabric Texture
  let noise_val = noise(uv * 50.0);
  let fabric_col = vec3<f32>(0.1, 0.1, 0.15) + vec3<f32>(noise_val * 0.05);
  // Add a seam line
  let seam = 1.0 - smoothstep(0.0, 0.005, abs(dx));
  let fabric_final = mix(fabric_col, vec3<f32>(0.05), seam * step(0.0, dy)); // Darker seam below slider

  // Image Texture
  let img_col = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Metal Color
  let metal_col = vec3<f32>(0.7, 0.7, 0.8) + vec3<f32>(noise_val * 0.1);

  // Teeth Color (Gold/Silver)
  let teeth_region = smoothstep(0.0, 0.02, abs(edge_dist));
  let tooth_col = vec3<f32>(0.6, 0.5, 0.2); // Gold

  // Final Mix
  var final_col = mix(fabric_final, img_col, mask);

  // Draw Teeth (The edge)
  let border = smoothstep(0.01, 0.0, abs(edge_dist));
  let tooth_vis = step(0.4, fract(uv.y * teeth_size));

  if (abs(edge_dist) < 0.015 && tooth_vis > 0.5) {
      final_col = tooth_col;
  }

  // Draw Slider
  final_col = mix(final_col, metal_col, slider_mask);

  textureStore(writeTexture, coord, vec4<f32>(final_col, 1.0));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
