// ═══════════════════════════════════════════════════════════════════
//  mouse-voronoi-mosaic
//  Category: interactive-mouse
//  Features: mouse-driven, voronoi, shatter
//  Complexity: High
//  Chunks From: chunk-library.md (hash22)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  Click positions create Voronoi cell centers. Each cell rotates,
//  shifts, and scales independently based on distance from its
//  creating ripple. Stained-glass window effect that evolves.
//  Alpha channel stores cell edge distance for glass highlights.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash22 (from gen_grid.wgsl) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn rot2(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn nearestRippleVoronoi(uv: vec2<f32>, aspect: f32) -> vec4<f32> {
  var minDist = 999.0;
  var secondDist = 999.0;
  var nearest = vec2<f32>(0.0);
  var nearestTime = 0.0;
  var nearestIndex = 0.0;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let d = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    if (d < minDist) {
      secondDist = minDist;
      minDist = d;
      nearest = ripple.xy;
      nearestTime = ripple.z;
      nearestIndex = f32(i);
    } else if (d < secondDist) {
      secondDist = d;
    }
  }

  return vec4<f32>(nearest, nearestTime, nearestIndex);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let shatterStrength = u.zoom_params.x;
  let edgeThickness = mix(0.001, 0.02, u.zoom_params.y);
  let colorShift = u.zoom_params.z;
  let glassOpacity = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;

  // Voronoi lookup
  let voro = nearestRippleVoronoi(uv, aspect);
  let cellCenter = voro.xy;
  let cellTime = voro.z;
  let cellIndex = voro.w;
  let elapsed = time - cellTime;

  // Distance to cell center and edge
  let distToCenter = length((uv - cellCenter) * vec2<f32>(aspect, 1.0));
  let distToEdge = secondDistVoronoi(uv, aspect) - distToCenter;

  // Cell animation: rotate, shift, scale based on elapsed time
  let angle = elapsed * 0.5 * shatterStrength + cellIndex * 0.7;
  let scale = 1.0 + sin(elapsed * 2.0 + cellIndex) * 0.1 * shatterStrength;
  let shift = vec2<f32>(
    cos(elapsed + cellIndex * 1.3),
    sin(elapsed + cellIndex * 1.7)
  ) * 0.05 * shatterStrength;

  // Transform UV within cell
  var cellUV = (uv - cellCenter) * scale;
  cellUV = rot2(angle) * cellUV;
  cellUV = cellUV + cellCenter + shift;

  // Sample image with transformed UV
  var color = textureSampleLevel(readTexture, u_sampler, cellUV, 0.0).rgb;

  // Color tint per cell
  let cellHue = fract(cellIndex * 0.1 + colorShift);
  let tint = vec3<f32>(
    0.5 + 0.5 * cos(cellHue * 6.28318),
    0.5 + 0.5 * cos(cellHue * 6.28318 + 2.094),
    0.5 + 0.5 * cos(cellHue * 6.28318 + 4.189)
  );
  color = mix(color, color * tint, colorShift * 0.5);

  // Stained-glass edge effect
  let edge = smoothstep(edgeThickness * 2.0, edgeThickness, abs(distToEdge));
  let edgeColor = vec3<f32>(0.9, 0.95, 1.0) * edge * glassOpacity * 2.0;
  color = color + edgeColor;

  // Mouse proximity brightens cells
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseGlow = exp(-mouseDist * mouseDist * 50.0) * 0.3;
  color = color + vec3<f32>(0.6, 0.7, 1.0) * mouseGlow;

  // Alpha = cell edge distance (0 at edge, 1 at center)
  let alpha = clamp(smoothstep(0.0, 0.1, distToEdge), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}

fn secondDistVoronoi(uv: vec2<f32>, aspect: f32) -> f32 {
  var minDist = 999.0;
  var secondDist = 999.0;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let d = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    if (d < minDist) {
      secondDist = minDist;
      minDist = d;
    } else if (d < secondDist) {
      secondDist = d;
    }
  }

  return secondDist;
}
