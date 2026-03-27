// ═══════════════════════════════════════════════════════════════
//  Rotoscope Ink - Physical Media Simulation with Alpha
//  Category: artistic
//  Features: ink line density → alpha, wash transparency, paper grain
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

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = u.config.zw;
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }

  var uv = vec2<f32>(global_id.xy) / dims;
  let texel = 1.0 / dims;

  // Parameters
  let baseThickness = mix(0.5, 3.0, u.zoom_params.x);
  let quantLevels = mix(2.0, 16.0, u.zoom_params.y);
  let threshold = mix(0.01, 0.2, u.zoom_params.z);
  let inkStrength = u.zoom_params.w;

  // Mouse Interaction
  var mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

  // Mouse boosts line thickness and lowers threshold
  let influence = 1.0 - smoothstep(0.0, 0.4, dist);
  let localThickness = baseThickness + influence * 2.0;
  let localThreshold = max(0.001, threshold - influence * 0.1);

  // Sobel Edge Detection
  let t = localThickness * texel;

  let c  = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let cN = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -t.y), 0.0).rgb;
  let cS = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, t.y), 0.0).rgb;
  let cE = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(t.x, 0.0), 0.0).rgb;
  let cW = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-t.x, 0.0), 0.0).rgb;

  let edgeH = getLuma(cE) - getLuma(cW);
  let edgeV = getLuma(cS) - getLuma(cN);
  let edgeMag = sqrt(edgeH*edgeH + edgeV*edgeV);

  let isEdge = step(localThreshold, edgeMag);

  // Color Quantization
  var quantColor = floor(c * quantLevels) / quantLevels;

  // ROTOscope INK ALPHA CALCULATION
  // Traditional rotoscope uses ink lines with varying thickness/density
  
  // Paper texture for absorption variation
  let paperGrain = hash12(uv * 300.0) * 0.1 + 0.9;
  
  // INK THICKNESS → ALPHA MAPPING
  // - Strong edges (ink lines): thick, opaque ink (alpha ~0.9-0.95)
  // - Weak edges: thinner lines, slightly translucent (alpha ~0.6-0.8)
  // - Washes: very thin, highly translucent (alpha ~0.2-0.4)
  // - Paper: no ink (alpha ~0.0)
  
  // Base ink alpha from edge detection
  var ink_alpha = isEdge * (0.7 + inkStrength * 0.25);
  
  // Edge magnitude affects line density
  let edge_density = smoothstep(0.0, 1.0, edgeMag / (localThreshold + 0.1));
  ink_alpha *= mix(0.7, 1.0, edge_density);
  
  // Paper grain creates slight variations in line quality
  // (simulating ink bleed on rough paper)
  let grain_effect = mix(0.92, 1.0, paperGrain);
  ink_alpha *= grain_effect;
  
  // Mouse focus area gets slightly denser ink
  let focus_boost = influence * 0.1;
  ink_alpha = min(1.0, ink_alpha + focus_boost);
  
  // Ink Application
  // Slightly blue-black ink with density variation
  let inkColor = vec3<f32>(0.05, 0.05, 0.12);
  
  // Blend quantized color with ink lines
  var finalColor = mix(quantColor, inkColor, isEdge * inkStrength);
  
  // Add slight paper tint to highlights
  if (getLuma(finalColor) > 0.9) {
      let paper_tint = vec3<f32>(1.0, 0.98, 0.94);
      finalColor = finalColor * paper_tint;
      
      // Very light areas have minimal ink
      ink_alpha *= 0.3;
  }
  
  // Shadow areas get more ink density
  if (getLuma(quantColor) < 0.3) {
      ink_alpha = mix(ink_alpha, min(1.0, ink_alpha * 1.3), inkStrength);
  }
  
  // Edge feathering for brush-like quality
  let edge_quality = smoothstep(0.0, 0.5, isEdge);
  ink_alpha *= mix(0.8, 1.0, edge_quality);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, ink_alpha));
  
  // Store ink density in depth
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(ink_alpha, 0.0, 0.0, ink_alpha));
}
