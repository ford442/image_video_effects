// ═══════════════════════════════════════════════════════════════════
//  Stipple Render v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: stipple-render
//  Created: 2026-05-10
//  Upgraded: 2026-05-30
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: blue_noise21 (from stipple-render) ═══
fn blue_noise21(p: vec2<f32>) -> f32 {
  var n = fract(p * vec2<f32>(5.3987, 5.4421));
  n += dot(n, n.yx + 19.19);
  return fract(n.x * n.y);
}

fn aces_tone_map(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn paper_texture(uv: vec2<f32>) -> f32 {
  let grain = blue_noise21(uv * 400.0) * 0.5 + blue_noise21(uv * 200.0 + 13.7) * 0.5;
  return 0.92 + grain * 0.08;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / resolution;

  let bass = plasmaBuffer[0].x;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let dotScale = u.zoom_params.x;
  let contrast = u.zoom_params.y;
  let wetRadius = u.zoom_params.z;
  let detailMix = u.zoom_params.w;

  let aspect = resolution.x / max(resolution.y, 1.0);
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let wetFactor = smoothstep(wetRadius, 0.0, mouseDist);

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgba;
  let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let adjustedLuma = (luma - 0.5) * (contrast * 2.0) + 0.5;

  // Depth-driven dot size perspective
  let depthScale = mix(0.6, 1.6, depth);
  let audioScale = 1.0 + bass * 0.3;
  let cellScale = mix(20.0, 120.0, dotScale) * depthScale * audioScale;

  // Grid cell with jitter for Voronoi approximation
  let cellUV = uv * resolution / cellScale;
  let cellId = floor(cellUV);
  let cellFract = fract(cellUV);

  // Approximate Lloyd's relaxation: offset cell center by local luminance
  let cellCenter = vec2<f32>(0.5) + (blue_noise21(cellId) - 0.5) * 0.6;
  let lumaOffset = (1.0 - adjustedLuma) * 0.35;
  let offsetCenter = cellCenter + vec2<f32>(lumaOffset * 0.3, lumaOffset * 0.2);

  // Dot size matches local luminance (darker = bigger dot)
  let dotSize = mix(0.15, 0.55, 1.0 - adjustedLuma);
  let distToCenter = length(cellFract - offsetCenter);
  let dotMask = 1.0 - smoothstep(dotSize * 0.6, dotSize, distToCenter);

  // Wet ink: dots bleed together near mouse
  let bleed = mix(1.0, 2.5, wetFactor);
  let wetDot = 1.0 - smoothstep(dotSize * 0.4 * bleed, dotSize * bleed, distToCenter);

  // Cross-hatching in dark regions
  let hatchAngle = uv.x * 300.0 + uv.y * 300.0;
  let hatch = sin(hatchAngle) * sin(hatchAngle * 0.7 + 1.0);
  let hatchMask = smoothstep(0.3, 0.0, adjustedLuma) * smoothstep(0.0, 0.3, hatch);

  // Ink and paper colors
  let inkColor = vec3<f32>(0.04, 0.035, 0.06);
  let hatchColor = vec3<f32>(0.08, 0.07, 0.09);
  let paperBase = vec3<f32>(0.96, 0.94, 0.90) * paper_texture(uv);

  var stippleColor = paperBase;
  stippleColor = mix(stippleColor, hatchColor, hatchMask * 0.45);
  stippleColor = mix(stippleColor, inkColor, dotMask * 0.9);
  stippleColor = mix(stippleColor, inkColor, wetDot * 0.7);

  // Mix with original for color reveal
  let inkSaturation = clamp(dotMask + wetDot * 0.5 + hatchMask * 0.3, 0.0, 1.0);
  var finalColor = mix(stippleColor, baseColor.rgb, detailMix * wetFactor * 0.6);

  // ACES tone mapping for ink richness
  finalColor = aces_tone_map(finalColor * 1.1);

  // Alpha: Dot density * ink_saturation * depth
  let alpha = clamp((dotMask + wetDot * 0.5 + hatchMask * 0.2) * inkSaturation * depth, 0.05, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
}
