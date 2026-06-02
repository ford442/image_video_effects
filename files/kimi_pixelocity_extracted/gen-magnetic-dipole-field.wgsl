// ═══════════════════════════════════════════════════════════════════
//  Magnetic Dipole Field Lines
//  Category: generative
//  Description: Procedurally rendered magnetic dipole field lines
//    with charged particle trajectories. Simulates iron filings
//    aligning to field lines with glowing ionized particles.
//    Mouse moves the dipole position and strength.
//  Complexity: Medium
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

// Smooth palette: blue -> cyan -> green -> yellow -> red
fn field_palette(t: f32, p4: f32) -> vec3<f32> {
  let hue = fract(t * 0.7 + p4);
  let h = hue * 6.0;
  let c = 0.8;
  let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
  let m = 0.1;
  var rgb: vec3<f32>;
  if h < 1.0 { rgb = vec3<f32>(c, x, 0.0); }
  else if h < 2.0 { rgb = vec3<f32>(x, c, 0.0); }
  else if h < 3.0 { rgb = vec3<f32>(0.0, c, x); }
  else if h < 4.0 { rgb = vec3<f32>(0.0, x, c); }
  else if h < 5.0 { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(m);
}

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn hash2f(n: f32) -> vec2<f32> {
  return vec2<f32>(hashf(n), hashf(n + 73.156));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // intensity (field strength)
  let p2 = u.zoom_params.y; // speed (particle animation)
  let p3 = u.zoom_params.z; // scale (line density)
  let p4 = u.zoom_params.w; // color shift

  // Dipole position from mouse
  var dipole: vec2<f32>;
  if mouseDown {
    dipole = (mouse - 0.5) * 2.0;
  } else {
    dipole = vec2<f32>(0.0, sin(time * p2 * 0.15) * 0.1);
  }

  // Calculate field at this point
  let r = uv - dipole;
  let r_sq = dot(r, r);
  let r_len = sqrt(r_sq);

  // Avoid singularity
  let safe_r = max(r_len, 0.01);

  // Magnetic field of dipole (2D approximation)
  // B proportional to (3(m.r)r - m*r^2) / r^5
  // Simplified for 2D with dipole moment along y-axis
  let dipole_moment = 1.0 + p1 * 2.0;
  let my = vec2<f32>(0.0, dipole_moment);
  let m_dot_r = my.y * r.y;

  let B = (3.0 * m_dot_r * r - my * r_sq) / (safe_r * safe_r * safe_r * safe_r * safe_r);
  let B_len = length(B);

  // Field line indicator: high where B aligns with nearby field direction
  let B_dir = B / max(B_len, 0.0001);
  let line_density = 4.0 + p3 * 20.0;

  // Field-aligned pattern using directional derivatives
  let perp_B = vec2<f32>(-B_dir.y, B_dir.x);
  let stream_val = dot(uv, perp_B) * line_density;
  let field_line = exp(-abs(stream_val - round(stream_val)) * 40.0);

  // Intensity falloff from dipole
  let intensity = dipole_moment / (r_sq + 0.02);

  // Particle simulation along field lines
  var particle_glow = 0.0;
  let num_particles = i32(3.0 + p1 * 8.0);

  for (var i = 0; i < num_particles; i++) {
    let p_seed = f32(i) * 157.0 + time * p2;
    let p_angle = hashf(p_seed) * PI * 2.0;
    let p_radius = 0.05 + hashf(p_seed + 1.0) * 0.4;

    // Particle orbit around field lines
    let p_time = time * p2 * (0.5 + hashf(p_seed + 2.0) * 1.5) + f32(i);
    let p_orbit_angle = p_time * 0.3;

    // Follow field line roughly
    let field_angle = atan2(B_dir.y, B_dir.x);
    let perp_angle = field_angle + PI * 0.5;

    let p_pos = dipole + vec2<f32>(
      cos(p_angle) * p_radius + cos(p_orbit_angle) * 0.02,
      sin(p_angle) * p_radius + sin(p_orbit_angle) * 0.02
    );

    let p_diff = uv - p_pos;
    let p_dist = length(p_diff);
    particle_glow += exp(-p_dist * p_dist * 400.0) * 0.3;
  }

  // Combine field lines and particles
  let field_contrib = field_line * intensity * 0.15;
  let total_intensity = field_contrib + particle_glow;

  // Coloring
  let strength_norm = clamp(intensity * 0.3, 0.0, 1.0);
  var color = field_palette(strength_norm + field_line * 0.2, p4) * total_intensity;

  // Background glow near dipole
  let bg_glow = dipole_moment * 0.03 / (r_sq + 0.1);
  color += vec3<f32>(0.05, 0.08, 0.15) * bg_glow;

  // Particle hot spots
  color += vec3<f32>(0.8, 0.9, 1.0) * particle_glow * 0.5;

  // Subtle pulsing
  color *= 1.0 + sin(time * p2 * 0.8) * 0.08;

  textureStore(writeTexture, pixel, vec4<f32>(color, 1.0));
}
