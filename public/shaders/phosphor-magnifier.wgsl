// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ZoomLevel, y=PhosphorDensity, z=Glow, w=LensSize
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Params
  let zoom_level = mix(1.0, 10.0, u.zoom_params.x); // 1x to 10x
  let density = mix(50.0, 500.0, 1.0 - u.zoom_params.y); // Resolution of the simulated screen
  let glow = u.zoom_params.z;
  let lens_size = mix(0.1, 0.8, u.zoom_params.w);

  // Mouse setup
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;

  // Correct for aspect ratio for distance calculation
  let dist_uv = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y);
  let dist = length(dist_uv);

  // Lens smoothstep
  let lens_mask = smoothstep(lens_size, lens_size - 0.05, dist);

  // Variable Zoom Factor based on mask
  // Inside lens: zoomed. Outside: 1.0.
  let current_zoom = mix(1.0, zoom_level, lens_mask);

  // Calculate sampled UV
  // We want to zoom relative to the MOUSE position.
  let centered_uv = uv - mouse;
  let zoomed_uv = centered_uv / current_zoom + mouse;

  // Simulate Pixel Grid (Quantization)
  // The virtual screen has 'density' pixels across.
  let grid_uv = floor(zoomed_uv * density) / density;

  // We sample the image at the pixelated coordinate to get the "color of the pixel"
  let color_sample = textureSampleLevel(readTexture, u_sampler, grid_uv, 0.0).rgb;

  // Subpixel Analysis
  // Calculate position within the virtual pixel (0.0 to 1.0)
  let subpixel_pos = fract(zoomed_uv * density);

  // Phosphor Mask (Aperture Grille style: Vertical stripes R, G, B)
  var mask = vec3<f32>(0.0);

  // Hard edges
  if (subpixel_pos.x < 0.333) {
      mask.r = 1.0;
  } else if (subpixel_pos.x < 0.666) {
      mask.g = 1.0;
  } else {
      mask.b = 1.0;
  }

  // Add black gaps between phosphors (scanlines logic)
  let gap_x = smoothstep(0.3, 0.333, subpixel_pos.x) * (1.0 - smoothstep(0.333, 0.366, subpixel_pos.x));
  // Actually simpler: darken edges of each strip
  let strip_pos = fract(subpixel_pos.x * 3.0);
  let strip_mask = smoothstep(0.1, 0.2, strip_pos) * (1.0 - smoothstep(0.8, 0.9, strip_pos));

  // Scanlines (Horizontal)
  let scanline_pos = fract(subpixel_pos.y);
  let scanline_mask = smoothstep(0.1, 0.2, scanline_pos) * (1.0 - smoothstep(0.8, 0.9, scanline_pos));

  // Combine geometric mask
  let phosphor_geom = strip_mask * scanline_mask;

  // Final phosphor color
  // We multiply the sampled color (which is the signal) by the mask (which is the physical screen)
  // But wait, R phosphor only emits R light.
  var phosphor_color = vec3<f32>(0.0);
  phosphor_color.r = color_sample.r * mask.r;
  phosphor_color.g = color_sample.g * mask.g;
  phosphor_color.b = color_sample.b * mask.b;

  // Apply geometric darkening (gaps)
  phosphor_color *= phosphor_geom;

  // Boost brightness because masking removes a lot of light
  phosphor_color *= 3.0;

  // Add Glow / Bloom (simulate light bleeding)
  let bloom = color_sample * glow * 0.5;
  phosphor_color += bloom;

  // Mix between Normal Image and Phosphor View based on lens
  let normal_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  let final_color = mix(normal_color, phosphor_color, lens_mask);

  // Store
  textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));

  // Depth pass
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
