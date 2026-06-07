// ═══════════════════════════════════════════════════════════════════
//  Hyperbolic Tessellation
//  Category: generative
//  Description: Real-time hyperbolic tiling in the Poincare disk
//    model. Generates regular tessellations {p,q} with configurable
//    parameters, rendered with metallic coloring and smooth edge
//    transitions. Mouse controls the viewpoint within hyperbolic
//    space and morphs between different tilings.
//  Complexity: High
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

// Complex operations for hyperbolic geometry
fn c_mul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn c_div(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let denom = dot(b, b);
  return vec2<f32>(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / denom;
}

fn c_abs(a: vec2<f32>) -> f32 {
  return length(a);
}

// Hyperbolic translation (Mobius transformation)
fn hyperbolic_translate(z: vec2<f32>, a: vec2<f32>) -> vec2<f32> {
  let a_conj = vec2<f32>(a.x, -a.y);
  let num = z - a;
  let den = c_mul(a_conj, z) * -1.0 + vec2<f32>(1.0, 0.0);
  return c_div(num, den);
}

// Reflect in a hyperbolic line through origin at angle theta
fn reflect(z: vec2<f32>, theta: f32) -> vec2<f32> {
  let c = cos(2.0 * theta);
  let s = sin(2.0 * theta);
  return vec2<f32>(z.x * c + z.y * s, z.x * s - z.y * c);
}

// Distance in hyperbolic disk
fn hyperbolic_dist(z: vec2<f32>) -> f32 {
  let r = length(z);
  if r >= 1.0 { return 1000.0; }
  return atanh(r) * 2.0;
}

// Edge of regular polygon in hyperbolic plane
fn polygon_edge_dist(angle: f32, p: i32, q: i32) -> f32 {
  // Edge of regular {p,q} polygon centered at origin
  let p_f = f32(p);
  let q_f = f32(q);

  // Interior angle
  let interior = PI * 2.0 / q_f;

  // Central angle
  let central = PI * 2.0 / p_f;

  // Distance from center to edge (apothem)
  let cos_interior = cos(interior * 0.5);
  let sin_central = sin(central * 0.5);

  // Circumradius in hyperbolic terms
  let sin_ratio = sin_central / cos_interior;
  let r = sqrt((sin_ratio - 1.0) / (sin_ratio + 1.0));

  // Distance from edge as function of angle
  let edge_angle = floor(angle / central + 0.5) * central;
  let da = angle - edge_angle;

  // Approximate distance to edge
  return r * abs(cos(da));
}

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn tiling_palette(cell_id: f32, edge_dist: f32, p4: f32) -> vec3<f32> {
  let t = fract(cell_id * 0.618033988 + p4);

  let colors = array<vec3<f32>, 6>(
    vec3<f32>(0.15, 0.25, 0.55),
    vec3<f32>(0.25, 0.15, 0.55),
    vec3<f32>(0.55, 0.15, 0.35),
    vec3<f32>(0.55, 0.35, 0.15),
    vec3<f32>(0.25, 0.55, 0.45),
    vec3<f32>(0.45, 0.55, 0.25)
  );

  let idx = i32(t * 5.0) % 5;
  let f = fract(t * 5.0);
  var col = mix(colors[idx], colors[idx + 1], f);

  // Metallic edge highlighting
  let edge_glow = smoothstep(0.05, 0.0, edge_dist);
  col = mix(col, vec3<f32>(0.9, 0.85, 0.75), edge_glow * 0.5);

  // Inner shading
  col *= 0.8 + 0.2 * (1.0 - smoothstep(0.0, 0.5, edge_dist));

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

  let p1 = u.zoom_params.x; // intensity (tiling density)
  let p2 = u.zoom_params.y; // speed (animation)
  let p3 = u.zoom_params.z; // scale (zoom)
  let p4 = u.zoom_params.w; // color shift

  // Poincare disk coordinate
  let disk_r = length(uv);
  if disk_r > 0.99 {
    // Outside disk: dark border
    textureStore(writeTexture, pixel, vec4<f32>(0.02, 0.02, 0.03, 1.0));
    return;
  }

  // Map to complex plane (Poincare disk)
  var z = uv;

  // Hyperbolic navigation with mouse
  var translate = vec2<f32>(0.0);
  if mouseDown {
    translate = mouse - 0.5;
    translate = translate * 0.8;
  } else {
    let auto_time = time * p2 * 0.05;
    translate = vec2<f32>(sin(auto_time) * 0.2, cos(auto_time * 0.7) * 0.15);
  }

  // Apply hyperbolic translation
  z = hyperbolic_translate(z, translate);

  // Tessellation parameters morph over time
  let morph_t = time * p2 * 0.02;
  let p_sides = 3 + i32(abs(sin(morph_t * 0.3)) * 5.0);       // 3 to 8
  let q_around = 3 + i32(abs(cos(morph_t * 0.4)) * 4.0);       // 3 to 7

  // Zoom into hyperbolic space
  let zoom_factor = 0.2 + p3 * 0.8;
  z = z * zoom_factor;

  // Polar coordinates
  let r = length(z);
  let angle = atan2(z.y, z.x);

  // Build tiling pattern
  let p_f = f32(p_sides);
  let central_angle = PI * 2.0 / p_f;

  // Which sector
  let sector = floor((angle + PI) / central_angle);
  let in_sector = (angle + PI) - sector * central_angle;
  let sector_t = in_sector / central_angle;

  // Distance from origin as hyperbolic measure
  let hyp_r = hyperbolic_dist(z);

  // Approximate cell boundaries
  let ring_spacing = 0.8 * zoom_factor;
  let ring = floor(hyp_r / ring_spacing);
  let in_ring = fract(hyp_r / ring_spacing);

  // Cell ID for coloring
  let cell_id = sector + ring * p_f;

  // Edge distance for highlighting
  let edge_sector = min(sector_t, 1.0 - sector_t);
  let edge_ring = min(in_ring, 1.0 - in_ring);
  let edge_dist = min(edge_sector * 0.3, edge_ring * 0.5);

  // Color the cell
  var color = tiling_palette(cell_id, edge_dist, p4);

  // Disk boundary glow
  let boundary = 1.0 - disk_r;
  color += vec3<f32>(0.1, 0.08, 0.15) * smoothstep(0.05, 0.0, boundary) * 0.5;

  // Zoom-dependent intensity
  color *= 0.7 + zoom_factor * 0.3;

  // Subtle shimmer
  color *= 1.0 + sin(time * p2 * 0.5 + cell_id) * 0.03;

  textureStore(writeTexture, pixel, vec4<f32>(color, 1.0));
}
