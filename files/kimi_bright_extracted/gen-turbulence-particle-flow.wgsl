// ═══════════════════════════════════════════════════════════════════
//  Turbulence Particle Flow
//  Category: generative
//  Description: Thousands of particles advected through a time-
//    varying turbulent vector field. Particles leave trails that
//    decay, creating organic flowing ribbons and streams.
//    Mouse injects new particles and affects the flow center.
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

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn hash2f(n: f32) -> vec2<f32> {
  return vec2<f32>(hashf(n), hashf(n + 73.156));
}

// 2D noise (value noise)
fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);

  let n = i.x + i.y * 57.0;
  return mix(
    mix(hashf(n), hashf(n + 1.0), u.x),
    mix(hashf(n + 57.0), hashf(n + 58.0), u.x),
    u.y
  );
}

// Turbulent vector field
fn flow_field(p: vec2<f32>, t: f32, p2: f32) -> vec2<f32> {
  var f = vec2<f32>(0.0);
  let scale = 2.0;

  // Multi-octave turbulence
  f.x += vnoise(p * scale + t * p2 * 0.3) - 0.5;
  f.y += vnoise(p * scale + vec2<f32>(31.7, 17.3) + t * p2 * 0.3) - 0.5;

  f.x += (vnoise(p * scale * 2.0 - t * p2 * 0.15) - 0.5) * 0.5;
  f.y += (vnoise(p * scale * 2.0 + vec2<f32>(31.7, 17.3) - t * p2 * 0.15) - 0.5) * 0.5;

  f.x += (vnoise(p * scale * 4.0 + t * p2 * 0.08) - 0.5) * 0.25;
  f.y += (vnoise(p * scale * 4.0 + vec2<f32>(31.7, 17.3) + t * p2 * 0.08) - 0.5) * 0.25;

  // Add a rotational component
  let r = length(p);
  let swirl = exp(-r * r * 2.0) * 2.0;
  f += vec2<f32>(-p.y, p.x) * swirl;

  return f * 0.3;
}

// Smooth color palette
fn flow_palette(t: f32, p4: f32) -> vec3<f32> {
  let colors = array<vec3<f32>, 5>(
    vec3<f32>(0.05, 0.10, 0.25),
    vec3<f32>(0.10, 0.35, 0.60),
    vec3<f32>(0.25, 0.65, 0.70),
    vec3<f32>(0.70, 0.85, 0.55),
    vec3<f32>(0.95, 0.95, 0.85)
  );
  let shifted = fract(t + p4);
  let idx = shifted * 4.0;
  let i = i32(idx);
  let f = fract(idx);
  if i >= 4 { return colors[4]; }
  return mix(colors[i], colors[i + 1], f);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // intensity (particle count)
  let p2 = u.zoom_params.y; // speed (flow speed)
  let p3 = u.zoom_params.z; // scale (field scale)
  let p4 = u.zoom_params.w; // color shift

  // Flow center from mouse
  var center = vec2<f32>(0.0);
  if mouseDown {
    center = (mouse - 0.5) * 2.0;
  } else {
    center = vec2<f32>(sin(time * 0.2) * 0.15, cos(time * 0.15) * 0.1);
  }

  let seed = f32(pixel.x) * 157.0 + f32(pixel.y) * 293.0;
  let num_particles = i32(2.0 + p1 * 12.0);

  var color = vec3<f32>(0.0);

  for (var i = 0; i < num_particles; i++) {
    let p_seed = seed + f32(i) * 197.3;

    // Particle birth position
    let birth_r = hashf(p_seed) * 0.8;
    let birth_angle = hashf(p_seed + 1.0) * PI * 2.0;
    let birth_pos = vec2<f32>(cos(birth_angle), sin(birth_angle)) * birth_r + center;

    // Particle age and lifetime
    let lifetime = 2.0 + hashf(p_seed + 2.0) * 4.0;
    let age = fract(time * p2 * 0.05 + hashf(p_seed + 3.0)) * lifetime;

    // Advect particle through flow field
    var pos = birth_pos;
    let dt = 0.01 / (1.0 + p3);
    let trail_len = i32(5.0 + p3 * 15.0);

    for (var s = 0; s < trail_len; s++) {
      let t_step = age - f32(s) * dt;
      if t_step < 0.0 { break; }

      // Sample flow field
      let field = flow_field(pos, time * p2, p2);
      pos += field * dt;

      // Check if near current pixel
      let diff = uv - pos;
      let dist_sq = dot(diff, diff);

      // Trail width decreases with age
      let trail_width = (0.0008 + hashf(p_seed + 4.0) * 0.002) * (1.0 - f32(s) / f32(trail_len));

      if dist_sq < trail_width * 4.0 {
        let brightness = exp(-dist_sq / trail_width) * (1.0 - f32(s) / f32(trail_len));
        let flow_strength = length(field);
        let color_idx = flow_strength * 0.5 + f32(i) / f32(num_particles) * 0.3;
        color += flow_palette(color_idx, p4) * brightness * 0.3;
      }
    }
  }

  // Add subtle background flow visualization
  let bg_field = flow_field(uv, time * p2, p2);
  let bg_strength = length(bg_field);
  color += flow_palette(bg_strength * 0.3, p4) * 0.02 * (1.0 - smoothstep(0.0, 0.5, bg_strength));

  // Mouse injection glow
  if mouseDown {
    let m_diff = uv - center;
    let m_dist = length(m_diff);
    color += vec3<f32>(0.5, 0.7, 1.0) * exp(-m_dist * m_dist * 20.0) * 0.2;
  }

  textureStore(writeTexture, pixel, vec4<f32>(color, 1.0));
}
