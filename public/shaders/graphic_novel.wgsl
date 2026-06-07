// ═══════════════════════════════════════════════════════════════
//  Graphic Novel - Physical Media Simulation with Alpha
//  Category: artistic
//  Features: ink density → alpha, halftone coverage, paper substrate
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

// Graphic Novel
// Param1: Dot Size (Halftone)
// Param2: Edge Threshold
// Param3: Color Quantization
// Param4: Paper Texture / Ink density

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
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;
  var mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let dotSize = u.zoom_params.x * 20.0 + 2.0;
  let edgeThresh = max(0.01, (1.0 - u.zoom_params.y) * 0.5);
  let levels = floor(u.zoom_params.z * 10.0) + 2.0;
  let inkDensity = u.zoom_params.w; // Controls how heavy the ink is laid down

  // 1. Edge Detection (Sobel)
  let pixelSize = 1.0 / resolution;
  var gx = vec3<f32>(0.0);
  var gy = vec3<f32>(0.0);

  for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
          let offset = vec2<f32>(f32(i), f32(j)) * pixelSize;
          let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
          let l = getLuma(s);

          var wx = 0.0;
          var wy = 0.0;

          if (i == -1) { wx = -1.0; } if (i == 1) { wx = 1.0; }
          if (j == -1) { wy = -1.0; } if (j == 1) { wy = 1.0; }

          if (j == 0) { wx *= 2.0; }
          if (i == 0) { wy *= 2.0; }

          gx += vec3<f32>(l * wx);
          gy += vec3<f32>(l * wy);
      }
  }

  let edge = length(gx + gy);
  let isEdge = select(0.0, 1.0, edge > edgeThresh);

  // 2. Color Quantization & Halftone
  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = getLuma(color);

  // Halftone pattern
  let gridPos = vec2<f32>(global_id.xy) / dotSize;
  let gridCenter = floor(gridPos) + 0.5;
  let dist = length(gridPos - gridCenter);
  let radius = sqrt(luma) * 0.5;

  // Posterize
  color = floor(color * levels) / levels;

  // Inverse halftone logic: Luma 1.0 (White) -> Radius 0.0 -> No black dot
  let dotRadius = (1.0 - luma) * 0.7;
  let isDot = select(0.0, 1.0, dist < dotRadius);

  // GRAPHIC NOVEL ALPHA CALCULATION
  // Comic book printing with physical ink properties
  
  // Ink layers in graphic novels:
  // - Solid blacks (lines/edges): high density, opaque (alpha ~0.95)
  // - Halftone dots: medium density, partial coverage (alpha varies 0.3-0.8)
  // - Paper: no ink, fully transparent substrate (alpha ~0.0)
  
  var finalColor = color;
  var ink_alpha = 0.0;
  
  // Edge/line ink (solid blacks)
  if (isEdge > 0.5) {
      // Solid ink lines are dense and opaque
      let line_density = inkDensity * 0.9 + 0.05;
      ink_alpha = line_density;
      finalColor = mix(finalColor, vec3<f32>(0.02, 0.02, 0.04), isEdge * inkDensity);
  }
  
  // Halftone dot ink
  if (isDot > 0.5) {
      // Dots have varying density based on their size (luma-based)
      // Larger dots (darker areas) = more ink = higher alpha
      let dot_coverage = smoothstep(0.0, 0.7, 1.0 - luma);
      let dot_alpha = dot_coverage * inkDensity * 0.85;
      
      // Ink color for dots (slightly warm black)
      let inkColor = vec3<f32>(0.08, 0.07, 0.09);
      finalColor = mix(finalColor, finalColor * 0.7, isDot * 0.8);
      
      // Accumulate alpha (edges + dots)
      ink_alpha = max(ink_alpha, dot_alpha);
  }
  
  // Base image quantization with alpha
  // Areas without edges or dots still have the posterized image
  // but at lower opacity (allowing paper texture to show)
  if (ink_alpha < 0.01) {
      // Pure color areas - lighter ink application
      ink_alpha = mix(0.15, 0.45, luma * inkDensity);
  }
  
  // Paper texture noise
  let paperNoise = hash12(uv * time * 0.001 + vec2<f32>(100.0));
  let paper_tex = 0.95 + 0.05 * paperNoise;
  
  // Paper affects ink absorption
  // Rough paper = more ink spread = slightly lower alpha but more coverage
  ink_alpha *= paper_tex;
  
  // Interactive Vignette based on Mouse
  if (mousePos.x >= 0.0) {
      let dVec = uv - mousePos;
      var d = length(dVec);
      let vignette = smoothstep(0.8, 0.2, d * 0.5);
      finalColor *= vignette;
      
      // Slight alpha boost at focus point
      ink_alpha = mix(ink_alpha, min(1.0, ink_alpha * 1.2), vignette * 0.5);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, ink_alpha));

  // Store ink density in depth
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(ink_alpha, 0.0, 0.0, ink_alpha));
}
