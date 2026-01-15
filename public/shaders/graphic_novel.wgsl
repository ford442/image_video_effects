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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Graphic Novel
// Param1: Dot Size (Halftone)
// Param2: Edge Threshold
// Param3: Color Quantization
// Param4: Paper Texture / Noise

fn getLuma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz; // Not used heavily, maybe for focus?

  let dotSize = u.zoom_params.x * 20.0 + 2.0;
  let edgeThresh = max(0.01, (1.0 - u.zoom_params.y) * 0.5); // Inverse: Higher param = More edges (lower thresh)
  let levels = floor(u.zoom_params.z * 10.0) + 2.0;
  let paperStr = u.zoom_params.w;

  // 1. Edge Detection (Sobel)
  let pixelSize = 1.0 / resolution;
  let gx = vec3<f32>(0.0);
  let gy = vec3<f32>(0.0);

  // 3x3 kernel manual unroll for performance? Or loop. Loop is fine in WGSL.
  for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
          let offset = vec2<f32>(f32(i), f32(j)) * pixelSize;
          let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
          let l = getLuma(s);

          // Sobel kernels
          // X: -1 0 1, -2 0 2, -1 0 1
          // Y: -1 -2 -1, 0 0 0, 1 2 1
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

  let edge = length(gx + gy); // Magnitude
  let isEdge = select(0.0, 1.0, edge > edgeThresh);

  // 2. Color Quantization & Halftone
  // Sample center
  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = getLuma(color);

  // Halftone pattern
  // Grid coordinates
  let gridPos = vec2<f32>(global_id.xy) / dotSize;
  let gridCenter = floor(gridPos) + 0.5;
  let dist = length(gridPos - gridCenter);
  let radius = sqrt(luma) * 0.5; // Dot radius proportional to brightness

  // CMYK style or B&W style? Let's do B&W overlay on posterized color.
  // Posterize
  color = floor(color * levels) / levels;

  // Apply Halftone darkening
  // If we are in the "dot", we keep color. If outside, we darken (or vice versa).
  // Standard halftone: Dark dots on light background.
  // Radius large = Darker (low luma). Radius small = Lighter.
  // Inverse logic:
  // Luma 1.0 (White) -> Radius 0.0 -> No black dot.
  // Luma 0.0 (Black) -> Radius 0.5 -> Full black dot covering cell.

  let dotRadius = (1.0 - luma) * 0.7; // Max radius slightly larger than 0.5 for overlap
  let isDot = select(0.0, 1.0, dist < dotRadius);

  // Blend logic
  // If Edge -> Black
  // If Dot -> Darken (Black ink)
  // Else -> Posterized Color

  var finalColor = color;

  // Apply dots (ink)
  // finalColor = mix(finalColor, vec3<f32>(0.05, 0.05, 0.05), isDot * 0.8); // 80% opacity dots
  // Actually, let's make it look more like print.
  if (isDot > 0.5) {
      finalColor *= 0.7; // Darken
  }

  // Apply Edges
  finalColor = mix(finalColor, vec3<f32>(0.0), isEdge);

  // Paper texture
  if (paperStr > 0.0) {
      // Simple noise
      let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
      finalColor += (noise - 0.5) * paperStr * 0.2;
  }

  // Interactive Vignette based on Mouse
  if (mousePos.x >= 0.0) {
      let dVec = uv - mousePos;
      let d = length(dVec);
      // Slight focus around mouse
      finalColor *= smoothstep(0.8, 0.2, d * 0.5); // Darken edges away from mouse
  }

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

  // Pass depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
