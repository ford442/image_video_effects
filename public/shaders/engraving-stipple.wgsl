// ═══════════════════════════════════════════════════════════════
//  Engraving Stipple - Physical Media Simulation with Alpha
//  Category: artistic
//  Features: engraving depth → alpha, burr texture, ink retention
// ═══════════════════════════════════════════════════════════════

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

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12(p: vec2<f32>) -> f32 {
	var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Params
  let density = mix(1.0, 4.0, u.zoom_params.x);
  let threshold_bias = u.zoom_params.y;
  let mouse_light_strength = u.zoom_params.z;
  let burrTexture = u.zoom_params.w; // Engraving burr/texture amount

  var mouse = u.zoom_config.yz;
  let aspect = u.config.z / u.config.w;

  // Sample Image
  let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var luma = getLuma(color);

  // Mouse Interaction: Flashlight / Reveal
  let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dist_vec);

  let light_radius = 0.3;
  let light = smoothstep(light_radius, 0.0, dist);

  // Modify luma based on light (engraving reveal)
  luma = luma + light * mouse_light_strength * 0.3;

  // Generate Noise for stipple pattern
  let noise = hash12(uv * vec2<f32>(dims) * density);
  
  // Plate texture (copper/zinc engraving plate)
  let plate_tex = hash12(uv * 80.0) * 0.08 + 0.92;

  // ENGRAVING STIPPLE ALPHA CALCULATION
  // Traditional engraving creates physical grooves in metal plate
  // When inked, grooves hold ink and create printed marks
  
  // ENGRAVING DEPTH → ALPHA MAPPING
  // - Deep grooves (dark areas): hold more ink, opaque marks (alpha ~0.9-0.98)
  // - Shallow grooves: hold less ink, semi-opaque (alpha ~0.5-0.8)
  // - Burr (raised metal): captures extra ink, slightly higher alpha
  // - Plate surface: wiped clean, no ink (alpha ~0.0)
  
  // Adjust threshold with bias
  let threshold = luma + (threshold_bias - 0.5);
  
  // Stipple mark presence
  let isMark = threshold < noise;
  
  // Mark depth based on how far below threshold
  let mark_depth = smoothstep(0.0, 0.3, noise - threshold);
  
  // ENGRAVING BURR EFFECT
  // Engraving tools create a burr (raised ridge) along grooves
  // Burr captures additional ink, creating characterisic fuzzy lines
  let burr_noise = hash12(uv * vec2<f32>(dims) * density * 2.0);
  let burr_effect = smoothstep(0.4, 0.6, burr_noise) * burrTexture;
  
  // Base ink alpha from mark presence
  var ink_alpha = 0.0;
  if (isMark) {
      // Deep marks hold more ink
      let depth_alpha = mix(0.6, 0.95, mark_depth);
      
      // Burr adds extra ink at edges
      let burr_alpha = burr_effect * 0.3;
      
      ink_alpha = depth_alpha + burr_alpha;
      ink_alpha = min(1.0, ink_alpha);
  }
  
  // Plate texture affects ink transfer
  // Smoother plate areas transfer ink more evenly
  ink_alpha *= plate_tex;
  
  // Edge feathering for engraved marks
  let edge_feather = smoothstep(0.0, 0.2, mark_depth);
  ink_alpha *= mix(0.85, 1.0, edge_feather);
  
  // Ink colors
  let ink = vec3<f32>(0.06, 0.06, 0.08); // Deep black ink
  let paper = vec3<f32>(0.94, 0.92, 0.87); // Aged paper

  var final_col: vec3<f32>;
  if (isMark) {
      // Mark color with depth variation
      let depth_darken = mix(0.85, 1.0, mark_depth);
      final_col = ink * depth_darken;
      
      // Burr adds slight variation
      final_col = mix(final_col, final_col * 1.1, burr_effect);
  } else {
      final_col = paper * plate_tex;
  }
  
  // Add subtle vignette from the mouse light
  final_col = mix(final_col * 0.6, final_col, 0.5 + 0.5 * light);
  
  // Light areas can slightly tint with original color
  if (luma > 0.7) {
      let tint_strength = (luma - 0.7) * 0.3;
      final_col = mix(final_col, color, tint_strength);
  }

  textureStore(writeTexture, coord, vec4<f32>(final_col, ink_alpha));
  
  // Store engraving depth in depth texture
  let depth_val = select(0.0, mark_depth + burr_effect * 0.2, isMark);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth_val, 0.0, 0.0, ink_alpha));
}
