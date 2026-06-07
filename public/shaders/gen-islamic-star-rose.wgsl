// ═══════════════════════════════════════════════════════════════════
//  Islamic Geometric Star-Rose
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven,
//    islamic, star, rose, geometric, girih, tessellation
//  Complexity: Very High
//  Wolfram Data: Regular pentagon — interior angle 108° = 3π/5 rad;
//    central angle 72° = 2π/5 rad; diagonal/edge ratio φ = (1+√5)/2 ≈ 1.618;
//    height = √(5+2√5)/2 × s ≈ 1.539s;
//    star polygon {n/k} where k=2 for pentagram
//  Chunks From: gen-islamic-star-rose (original)
//  Created: 2026-05-31
//  Upgraded: 2026-06-07
//  By: Kimi Agent
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

// ═══ CHUNK: acesToneMap (canonical) ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

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

// Signed distance to a star polygon with Wolfram φ ratio
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

// Pentagon-aware star — Wolfram: star points at angle = fi * 72° + 36°
fn sd_pentagram(p: vec2<f32>, outer_r: f32) -> f32 {
  let angle = atan2(p.y, p.x);
  let sector = PI * 2.0 / 5.0;          // central angle 72° = 2π/5
  let half_sector = sector * 0.5;        // 36°
  let a = abs(fract(angle / sector + 0.5) - 0.5) * sector;
  let rp = length(p);
  // Wolfram: diagonal/edge ratio φ ≈ 1.618 determines inner radius
  let PHI: f32 = 1.618033988;
  let inner_r = outer_r / PHI;
  let edge_r = mix(outer_r, inner_r, a / half_sector);
  return rp - edge_r;
}

// Pentagon rosette with 108° interior angle awareness
fn sd_pentagon_rosette(p: vec2<f32>, r: f32) -> f32 {
  let angle = atan2(p.y, p.x);
  let sector = PI * 2.0 / 5.0;
  // Points offset by 36° for pentagram alignment
  let a = abs(fract(angle / sector + 0.5) - 0.5) * sector;
  let rp = length(p);
  // Height ratio ≈ 1.539 from Wolfram
  let heightFactor = 1.539;
  let edge_r = mix(r, r * 0.4, smoothstep(0.0, sector * 0.5, a) * heightFactor / 1.618);
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

  // Audio reads
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Bass rotates the tessellation
  let bassRotation = bass * PI * 0.5;

  // Pattern rotation from mouse or auto + bass
  var rotation: f32;
  var zoom: f32;
  if mouseDown {
    rotation = (mouse.x - 0.5) * PI * 2.0 + bassRotation;
    zoom = 0.5 + mouse.y * 1.5;
  } else {
    rotation = time * p2 * 0.1 + bassRotation;
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

  // Wolfram φ for petal proportions
  let PHI: f32 = 1.618033988;

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
        // Prefer pentagram (5-pointed star) when star is chosen
        let star_points = 4 + i32(hashf(pattern_seed + 1.0) * 6.0);
        if star_points == 5 {
          // Wolfram pentagram: petal length = edge * φ
          let outer = hex_r * 0.7;
          let inner = outer / PHI;
          shape_dist = sd_star(local, outer, inner, 5) / hex_r;
        } else {
          let outer_r = hex_r * 0.7;
          let inner_r = hex_r * 0.3;
          shape_dist = sd_star(local, outer_r, inner_r, star_points) / hex_r;
        }
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

  // Central star rosette — pentagram using Wolfram angles
  let center_dist = length(ruv);
  let rosette = sd_pentagram(ruv, 0.15 * zoom);
  if rosette < 0.0 {
    // Inside central rosette
    color = mix(vec3<f32>(0.12, 0.20, 0.45), vec3<f32>(0.80, 0.70, 0.20), smoothstep(-0.02, 0.02, rosette));
  }
  let rosette_edge = smoothstep(0.03, 0.0, abs(rosette));
  color += vec3<f32>(0.95, 0.88, 0.70) * rosette_edge * 0.6;

  // Mouse morphs between star and rose forms
  let mouseMorph = length(mouse / resolution - vec2<f32>(0.5));
  let roseDist = sd_pentagon_rosette(ruv, 0.12 * zoom * (1.0 + mouseMorph * 2.0));
  let roseEdge = smoothstep(0.04, 0.0, abs(roseDist));
  color += vec3<f32>(0.75, 0.55, 0.15) * roseEdge * 0.4 * mouseMorph;

  // Background pattern (subtle repeating motif)
  let bg_pattern = sin(p_uv.x * 20.0) * sin(p_uv.y * 20.0) * 0.5 + 0.5;
  color += vec3<f32>(0.03, 0.05, 0.08) * bg_pattern * 0.1;

  // Rotation shimmer with treble
  color *= 1.0 + sin(time * p2 * 0.3 + treble * 2.0) * 0.02;

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.8, length(uv));
  color *= 0.75 + vignette * 0.25;

  // Chromatic aberration — bass-reactive
  let caStr = 0.003 * (1.0 + bass);
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  // Temporal feedback
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.5), 0.0);
  color = mix(prev.rgb * 0.96, color, 0.25);

  // ACES tone mapping + semantic alpha
  color = acesToneMap(color * 1.1);
  let alpha = clamp(length(color) * 1.2, 0.2, 0.95);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
}
