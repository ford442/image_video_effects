// ═══════════════════════════════════════════════════════════════════
//  mouse-voronoi-mosaic
//  Category: interactive-mouse
//  Features: mouse-driven, voronoi, shatter, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-31
//  Ideas: crown-glass bow (§12.2B); dark lead with inner rim; age patina
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

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

fn brownConrady(p: vec2<f32>, k1: f32) -> vec2<f32> {
  let r2 = dot(p, p);
  return p * (1.0 + k1 * r2);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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

  // ── Idea 1: crown-glass bow (§12.2B) ────────────────────────────
  // Shatter strength already scales the pane. A radial bow of that
  // same local vector is the thickness of crown glass.
  let bowed = cellCenter + shift + brownConrady(cellUV - cellCenter - shift, shatterStrength * 6.0);
  cellUV = clamp(bowed, vec2<f32>(0.0), vec2<f32>(1.0));

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

  // ── Idea 2: dark lead plus inner rim ────────────────────────────
  // edgeThickness still sets the band; glassOpacity still scales it.
  // The came is dark metal. A thin bright rim sits just inside it.
  let lead = 1.0 - smoothstep(edgeThickness, edgeThickness * 3.5, distToEdge);
  let rimIn = smoothstep(edgeThickness * 1.1, edgeThickness * 2.2, distToEdge);
  let rimOut = 1.0 - smoothstep(edgeThickness * 2.2, edgeThickness * 4.2, distToEdge);
  let rim = rimIn * rimOut;
  color = mix(color, color * vec3<f32>(0.05, 0.06, 0.08), lead * glassOpacity);
  color = color + vec3<f32>(0.9, 0.95, 1.0) * rim * glassOpacity * 1.6;

  // ── Idea 3: age patina ──────────────────────────────────────────
  // A pane that came from a real click dulls as it ages. No click
  // (cellTime == 0) does not patina the whole frame.
  let hasCell = step(0.001, cellTime);
  let age = clamp(elapsed / 6.0, 0.0, 1.0) * hasCell;
  let paneLuma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  color = mix(color, vec3<f32>(paneLuma) * vec3<f32>(0.72, 0.78, 0.62), age * 0.5);

  // Mouse proximity brightens cells
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseGlow = exp(-mouseDist * mouseDist * 50.0) * 0.3;
  color = color + vec3<f32>(0.6, 0.7, 1.0) * mouseGlow;

  // Alpha: transmission through the pane, opaque on the lead
  let alpha = clamp(mix(0.35, 0.95, smoothstep(0.0, 0.08, distToEdge)) * (0.45 + 0.55 * glassOpacity) + lead * 0.2, 0.0, 1.0);
  let outRgb = aces(max(color, vec3<f32>(0.0)));
  let outCol = vec4<f32>(outRgb, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), outCol);
  textureStore(dataTextureA, vec2<i32>(global_id.xy), outCol);

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
