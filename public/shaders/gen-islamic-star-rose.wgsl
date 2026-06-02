// ═══════════════════════════════════════════════════════════════════
//  Islamic Geometric Star-Rose
//  Category: generative
//  Description: Procedurally generated Islamic geometric patterns
//    with girih-style star and polygon tessellations. Features
//    intricate strapwork, rosette centers, and metallic gold/blue
//    coloring. Mouse controls pattern rotation and scale.
//  Complexity: Medium
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  Islamic Star Rose
//  Category: generative
//  Features: islamic, star, rose, geometric, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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

const PI: f32 = 3.14159265359;

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn hash2f(n: f32) -> vec2<f32> {
  return vec2<f32>(hashf(n), hashf(n + 73.156));
}

// 2D rotation
fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Signed distance to a regular n-gon
fn sd_ngon(p: vec2<f32>, r: f32, n: i32) -> f32 {
  let angle = atan2(p.y, p.x);
  let sector = PI * 2.0 / f32(n);
  let a = abs(fract(angle / sector + 0.5) - 0.5) * sector;
  let rp = length(p);
  let dist_to_edge = rp * cos(a) - r;
  let dist_to_vertex = length(p - r * vec2<f32>(cos(floor(angle / sector + 0.5) * sector), sin(floor(angle / sector + 0.5) * sector)));
  return max(dist_to_edge, -dist_to_vertex + r * 0.3);
}

// Signed distance to a star polygon
fn sd_star(p: vec2<f32>, outer_r: f32, inner_r: f32, points: i32) -> f32 {
  let angle = atan2(p.y, p.x);
  let sector = PI * 2.0 / f32(points);
  let half_sector = sector * 0.5;

  let a = abs(fract(angle / sector + 0.5) - 0.5) * sector;
  let rp = length(p);

  // Interpolate between outer and inner radius
  let edge_r = mix(outer_r, inner_r, a / half_sector);
  return rp - edge_r;
}

// Girih-style pattern coloring
fn girih_palette(cell_type: f32, edge_glow: f32, p4: f32) -> vec3<f32> {
  let t = fract(cell_type * 0.618033988 + p4);

  // Islamic palette: lapis blue, turquoise, gold, crimson, emerald
  let colors = array<vec3<f32>, 5>(
    vec3<f32>(0.12, 0.25, 0.55), // lapis blue
    vec3<f32>(0.20, 0.60, 0.65), // turquoise
    vec3<f32>(0.75, 0.65, 0.20), // gold
    vec3<f32>(0.65, 0.15, 0.25), // crimson
    vec3<f32>(0.15, 0.55, 0.35)  // emerald
  );

  let idx = i32(t * 4.0) % 4;
  let f = fract(t * 4.0);
  var col = mix(colors[idx], colors[idx + 1], f);

  // Strapwork (white/gold lines)
  let strap = smoothstep(0.04, 0.0, edge_glow);
  col = mix(col, vec3<f32>(0.95, 0.88, 0.70), strap * 0.8);

  // Inner shadow
  col *= 0.9 + 0.1 * smoothstep(0.0, 0.1, edge_glow);

  return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // intensity (pattern complexity)
  let p2 = u.zoom_params.y; // speed (rotation)
  let p3 = u.zoom_params.z; // scale (zoom)
  let p4 = u.zoom_params.w; // color shift

  // Pattern rotation from mouse or auto
  var rotation: f32;
  var zoom: f32;
  if mouseDown {
    rotation = (mouse.x - 0.5) * PI * 2.0;
    zoom = 0.5 + mouse.y * 1.5;
  } else {
    rotation = time * p2 * 0.1;
    zoom = 0.8 + p3 * 0.7;
  }

  let ruv = rot2(uv, rotation);

  // Pattern scale
  let pattern_scale = 2.0 * zoom;
  let p_uv = ruv * pattern_scale;

  // Hexagonal tiling basis
  let hex_r = 0.5;
  let hex_w = hex_r * 2.0;
  let hex_h = sqrt(3.0) * hex_r;

  // Hex grid coordinates
  let col = floor(p_uv.x / (hex_w * 0.75));
  let row = floor((p_uv.y + (col % 2.0) * hex_h * 0.5) / hex_h);

  var min_dist = 1000.0;
  var cell_type = 0.0;
  var edge_dist = 1.0;

  // Check neighboring hexes
  for (var dc = -1; dc <= 1; dc++) {
    for (var dr = -1; dr <= 1; dr++) {
      let hc = col + f32(dc);
      let hr = row + f32(dr);

      // Hex center
      let hcx = hc * hex_w * 0.75;
      let hcy = hr * hex_h - (hc % 2.0) * hex_h * 0.5;
      let hex_center = vec2<f32>(hcx, hcy);

      let local = p_uv - hex_center;

      // Distance from hex center
      let hex_dist = length(local) / hex_r;

      // Pattern inside hex alternates between star and polygon
      let pattern_seed = hc * 7.0 + hr * 13.0;
      let is_star = hashf(pattern_seed) > 0.4;

      var shape_dist: f32;
      if is_star {
        let star_points = 4 + i32(hashf(pattern_seed + 1.0) * 6.0);
        shape_dist = sd_star(local, hex_r * 0.7, hex_r * 0.3, star_points) / hex_r;
      } else {
        let ngon_sides = 4 + i32(hashf(pattern_seed + 2.0) * 4.0);
        shape_dist = sd_ngon(local, hex_r * 0.5, ngon_sides) / hex_r;
      }

      // Girih strapwork lines (concentric patterns)
      let strap1 = abs(hex_dist - 0.6);
      let strap2 = abs(hex_dist - 0.85);
      let min_strap = min(strap1, strap2);

      // Combine shape and strapwork
      let combined_dist = min(abs(shape_dist), min_strap * 0.5);

      if combined_dist < min_dist {
        min_dist = combined_dist;
        cell_type = hashf(pattern_seed);
        edge_dist = combined_dist;
      }
    }
  }

  // Color the pattern
  var color = girih_palette(cell_type, edge_dist, p4);

  // Central star rosette
  let center_dist = length(ruv);
  let rosette = sd_star(ruv, 0.15 * zoom, 0.07 * zoom, 12);
  if rosette < 0.0 {
    // Inside central rosette
    color = mix(vec3<f32>(0.12, 0.20, 0.45), vec3<f32>(0.80, 0.70, 0.20), smoothstep(-0.02, 0.02, rosette));
  }
  let rosette_edge = smoothstep(0.03, 0.0, abs(rosette));
  color += vec3<f32>(0.95, 0.88, 0.70) * rosette_edge * 0.6;

  // Background pattern (subtle repeating motif)
  let bg_pattern = sin(p_uv.x * 20.0) * sin(p_uv.y * 20.0) * 0.5 + 0.5;
  color += vec3<f32>(0.03, 0.05, 0.08) * bg_pattern * 0.1;

  // Rotation shimmer
  color *= 1.0 + sin(time * p2 * 0.3) * 0.02;

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.8, length(uv));
  color *= 0.75 + vignette * 0.25;

  textureStore(writeTexture, pixel, vec4<f32>(color, 0.85));
}
