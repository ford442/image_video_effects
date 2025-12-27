struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var u_sampler: sampler;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
  // Simplified HSL to RGB
  let c = (1.0 - abs(2.0 * l - 1.0)) * s;
  let x = c * (1.0 - abs((h * 6.0) % 2.0 - 1.0));
  let m = l - c / 2.0;

  var r = 0.0;
  var g = 0.0;
  var b = 0.0;

  if (h < 1.0/6.0) { r = c; g = x; b = 0.0; }
  else if (h < 2.0/6.0) { r = x; g = c; b = 0.0; }
  else if (h < 3.0/6.0) { r = 0.0; g = c; b = x; }
  else if (h < 4.0/6.0) { r = 0.0; g = x; b = c; }
  else if (h < 5.0/6.0) { r = x; g = 0.0; b = c; }
  else { r = c; g = 0.0; b = x; }

  return vec3<f32>(r+m, g+m, b+m);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Params
  let distortion_amt = u.zoom_params.x * 0.5;
  let smoothness = u.zoom_params.y; // Unused in this simple implementation, maybe controls normal smoothness?
  let specular_pow = mix(10.0, 100.0, u.zoom_params.z);
  let tint_hue = u.zoom_params.w;

  let mouse = u.zoom_config.yz;

  // Calculate Normal from image brightness (emboss style)
  let pixel_size = 1.0 / vec2<f32>(dims);

  // Use a larger step for smoother normals if smoothness is high
  let step = pixel_size * mix(1.0, 5.0, smoothness);

  let l_x1 = getLuma(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(step.x, 0.0), 0.0).rgb);
  let l_x2 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, 0.0), 0.0).rgb);
  let l_y1 = getLuma(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, step.y), 0.0).rgb);
  let l_y2 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, step.y), 0.0).rgb);

  let dx = (l_x1 - l_x2) * 2.0; // Scale height
  let dy = (l_y1 - l_y2) * 2.0;

  var normal = normalize(vec3<f32>(dx, dy, 1.0));

  // Mouse interaction: Add a "blob" or "ripple" normal at mouse pos
  let aspect = u.config.z / u.config.w;
  let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dist_vec);

  let blob_radius = 0.2;
  if (dist < blob_radius) {
     // Create a spherical normal perturbation
     let pct = 1.0 - dist / blob_radius; // 0 to 1 at center
     // Simple bump: gradient away from mouse
     let mouse_dir = normalize(dist_vec);
     // Use sine wave for ripple effect
     let ripple = sin(dist * 50.0 - u.config.x * 5.0) * pct * distortion_amt;

     // Add to normal xy
     normal.x += mouse_dir.x * ripple;
     normal.y += mouse_dir.y * ripple;
     normal = normalize(normal);
  }

  // Environment Mapping (Chrome effect)
  // We use the video itself as the environment map (Spherical or Planar mapping)
  // Let's do simple 2D distortion: offset UV by normal.xy

  let offset = normal.xy * 0.1; // Strength of reflection distortion
  let reflect_uv = uv + offset;

  let base_color = textureSampleLevel(readTexture, u_sampler, reflect_uv, 0.0).rgb;

  // Specular Highlight
  // Light source at mouse position (virtual 3D pos)
  let light_pos = vec3<f32>(mouse.x * aspect, mouse.y, 0.5); // Slightly in front
  let pixel_pos = vec3<f32>(uv.x * aspect, uv.y, 0.0);
  let light_dir = normalize(light_pos - pixel_pos);
  let view_dir = vec3<f32>(0.0, 0.0, 1.0);
  let half_dir = normalize(light_dir + view_dir);

  let spec = pow(max(dot(normal, half_dir), 0.0), specular_pow);

  // Tint
  let tint_col = hslToRgb(tint_hue, 0.5, 0.5);

  // Composite
  // Make it look metallic: Video color * Tint + White Specular
  let metal_look = base_color * mix(vec3<f32>(1.0), tint_col, 0.5) + vec3<f32>(spec);

  textureStore(writeTexture, coord, vec4<f32>(metal_look, 1.0));
}
