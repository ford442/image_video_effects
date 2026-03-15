// ═══════════════════════════════════════════════════════════════
//  Stipple Engraving - Physical Media Simulation with Alpha
//  Category: artistic
//  Features: dot density → alpha, ink pooling, paper absorption
// ═══════════════════════════════════════════════════════════════

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

fn hash12(p: vec2<f32>) -> f32 {
	var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn getLuma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  // Params
  let density = u.zoom_params.x * 2.0 + 0.5;
  let contrast = u.zoom_params.y * 2.0 + 0.5;
  let radius = u.zoom_params.z;
  let inkSaturation = u.zoom_params.w; // How saturated the ink is

  // Mouse interaction
  var mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uvCorrected, mouseCorrected);

  // Sample texture
  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Calculate Luminance
  var lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));

  // Apply Contrast
  lum = (lum - 0.5) * contrast + 0.5;

  // Mouse Spotlight: Brighten the area under the mouse
  let spotlight = smoothstep(radius, 0.0, dist) * 0.3;
  lum += spotlight;
  lum = clamp(lum, 0.0, 1.0);

  // Generate Noise for stipple pattern
  let noiseUV = uv * resolution * (0.5 / density);
  let noise = hash12(noiseUV);
  
  // Paper texture for absorption
  let paper_tex = hash12(uv * 150.0) * 0.1 + 0.9;

  // STIPPLE ENGRAVING ALPHA CALCULATION
  // Traditional stippling creates tone through dot density
  // Each dot represents an ink deposit with physical properties
  
  // DOT DENSITY → ALPHA MAPPING
  // - High density (dark areas): many dots, overlapping, opaque (alpha ~0.85-0.95)
  // - Medium density: scattered dots, partial coverage (alpha ~0.4-0.7)
  // - Low density (light areas): sparse dots (alpha ~0.1-0.3)
  // - Paper only: no dots, substrate visible (alpha ~0.0)
  
  // Stipple comparison
  let stipple_threshold = lum;
  let isDot = noise >= stipple_threshold;
  
  // Dot size varies with luminance (darker = larger dots)
  let dot_size = mix(0.8, 1.2, 1.0 - lum);
  let dot_edge = smoothstep(stipple_threshold, stipple_threshold + 0.1, noise);
  
  // Base ink alpha from dot presence
  var ink_alpha = 0.0;
  if (isDot) {
      // Individual dot has varying opacity based on:
      // - Ink saturation (darker ink = more opaque)
      // - Dot edge (anti-aliasing)
      // - Paper absorption
      let base_dot_alpha = mix(0.75, 0.95, inkSaturation);
      ink_alpha = base_dot_alpha * dot_edge;
      
      // Darker areas have denser stippling = higher accumulated alpha
      let density_boost = (1.0 - lum) * 0.2;
      ink_alpha = min(1.0, ink_alpha + density_boost);
  }
  
  // Paper absorption reduces edge sharpness
  ink_alpha *= paper_tex;
  
  // Edge feathering for dots
  ink_alpha *= smoothstep(0.0, 0.3, dot_edge);
  
  // Ink colors
  let ink = vec3<f32>(0.08, 0.08, 0.12); // Dark blue-black ink
  let paper = vec3<f32>(0.96, 0.95, 0.91); // Cream paper

  var finalColor: vec3<f32>;
  if (isDot) {
      // Dot color with slight variation for organic feel
      let dot_variation = hash12(uv * 500.0) * 0.1 + 0.9;
      finalColor = ink * dot_variation;
  } else {
      finalColor = paper * paper_tex;
  }
  
  // Optional: Mix in a bit of original color based on mouse spotlight
  if (spotlight > 0.01) {
      let color_mix = spotlight * 0.5;
      finalColor = mix(finalColor, color, color_mix * 0.3);
      ink_alpha = mix(ink_alpha, 0.5, color_mix * 0.2);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, ink_alpha));
  
  // Store stipple density in depth
  let density_value = select(0.0, 1.0 - lum, isDot);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(density_value, 0.0, 0.0, ink_alpha));
}
