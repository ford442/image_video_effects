// ═══════════════════════════════════════════════════════════════════
//  Magnetic Dipole Field Lines
//  Category: generative
//  Description: Procedurally rendered magnetic dipole field lines
//    with charged particle trajectories. Simulates iron filings
//    aligning to field lines with glowing ionized particles.
//    Mouse moves the dipole position and strength.
//  Complexity: Medium
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  Magnetic Dipole Field
//  Category: generative
//  Features: magnetic, dipole, field, audio-reactive, mouse-interactive, semantic-alpha
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Branchless hue-to-RGB via array lookup
fn field_palette(t: f32, p4: f32) -> vec3<f32> {
  let hue = fract(t * 0.7 + p4);
  let h = hue * 6.0;
  let c = 0.8;
  let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
  let m = 0.1;
  let rgb_table = array<vec3<f32>, 6>(
    vec3<f32>(c, x, 0.0), vec3<f32>(x, c, 0.0), vec3<f32>(0.0, c, x),
    vec3<f32>(0.0, x, c), vec3<f32>(x, 0.0, c), vec3<f32>(c, 0.0, x)
  );
  return rgb_table[clamp(i32(h), 0, 5)] + vec3<f32>(m);
}

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn hash2f(n: f32) -> vec2<f32> {
  return vec2<f32>(hashf(n), hashf(n + 73.156));
}

// Evaluate field and particles at a given UV, returning color + particle density in alpha
fn sampleField(uv: vec2<f32>, time: f32, p1: f32, p2: f32, p3: f32, p4: f32, dipole: vec2<f32>, bass: f32) -> vec4<f32> {
  let r = uv - dipole;
  let r_sq = dot(r, r);
  let r_len = sqrt(r_sq);
  let safe_r = max(r_len, 0.01);
  let dipole_moment = 1.0 + p1 * 2.0;
  let my = vec2<f32>(0.0, dipole_moment);
  let m_dot_r = my.y * r.y;
  let B = (3.0 * m_dot_r * r - my * r_sq) / (safe_r * safe_r * safe_r * safe_r * safe_r);
  let B_len = length(B);
  let B_dir = B / max(B_len, 0.0001);
  let line_density = 4.0 + p3 * 20.0;
  let perp_B = vec2<f32>(-B_dir.y, B_dir.x);
  let stream_val = dot(uv, perp_B) * line_density;
  let field_line = exp(-abs(stream_val - round(stream_val)) * 40.0);
  let intensity = dipole_moment / (r_sq + 0.02);

  // Primary particle layer
  var particle_glow = 0.0;
  let num_particles = i32(3.0 + p1 * 8.0);
  for (var i = 0; i < num_particles; i++) {
    let p_seed = f32(i) * 157.0 + time * p2;
    let p_angle = hashf(p_seed) * PI * 2.0;
    let p_radius = 0.05 + hashf(p_seed + 1.0) * 0.4;
    let p_time = time * p2 * (0.5 + hashf(p_seed + 2.0) * 1.5) + f32(i);
    let p_orbit_angle = p_time * 0.3;
    let p_pos = dipole + vec2<f32>(
      cos(p_angle) * p_radius + cos(p_orbit_angle) * 0.02,
      sin(p_angle) * p_radius + sin(p_orbit_angle) * 0.02
    );
    let p_dist = length(uv - p_pos);
    particle_glow += exp(-p_dist * p_dist * 400.0) * 0.3;
  }

  // Secondary fast ion population (audio-excited)
  let fast_count = i32(bass * 8.0);
  for (var i = 0; i < fast_count; i++) {
    let p_seed = f32(i) * 293.0 + time * p2 * 3.0;
    let p_angle = hashf(p_seed) * PI * 2.0;
    let p_radius = 0.03 + hashf(p_seed + 1.0) * 0.15;
    let p_time = time * p2 * 4.0 + f32(i);
    let p_pos = dipole + vec2<f32>(
      cos(p_angle + p_time) * p_radius,
      sin(p_angle + p_time * 1.3) * p_radius
    );
    let p_dist = length(uv - p_pos);
    particle_glow += exp(-p_dist * p_dist * 600.0) * 0.25 * (1.0 + bass);
  }

  let field_contrib = field_line * intensity * 0.15;
  let total_intensity = field_contrib + particle_glow;
  let strength_norm = clamp(intensity * 0.3, 0.0, 1.0);
  var color = field_palette(strength_norm + field_line * 0.2, p4) * total_intensity;
  let bg_glow = dipole_moment * 0.03 / (r_sq + 0.1);
  color += vec3<f32>(0.05, 0.08, 0.15) * bg_glow;
  color += vec3<f32>(0.8, 0.9, 1.0) * particle_glow * 0.5;
  return vec4<f32>(color, particle_glow);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;

  // Branchless dipole selection
  let auto_dipole = vec2<f32>(0.0, sin(time * p2 * 0.15) * 0.1);
  let mouse_dipole = (mouse - 0.5) * 2.0;
  let dipole = select(auto_dipole, mouse_dipole, mouseDown);

  let dipole_moment = 1.0 + p1 * 2.0;
  let r = uv - dipole;
  let r_sq = dot(r, r);
  let field_intensity = dipole_moment / (r_sq + 0.02);

  // Chromatic aberration split by field strength
  let caStrength = 0.003 * field_intensity * (1.0 + bass);
  let caDir = normalize(vec2<f32>(r.y, -r.x) + vec2<f32>(0.001));
  let rResult = sampleField(uv + caDir * caStrength, time, p1, p2, p3, p4, dipole, bass);
  let gResult = sampleField(uv, time, p1, p2, p3, p4, dipole, bass);
  let bResult = sampleField(uv - caDir * caStrength, time, p1, p2, p3, p4, dipole, bass);
  var color = vec3<f32>(rResult.r, gResult.g, bResult.b);

  // Ghost dipole orbiting for topological complexity
  let ghost_angle = time * p2 * 0.12 + bass * 3.0;
  let ghost_dipole = dipole + vec2<f32>(cos(ghost_angle), sin(ghost_angle)) * 0.12;
  let ghostResult = sampleField(uv, time, p1 * 0.4, p2, p3, p4 + 0.3, ghost_dipole, bass);
  color += ghostResult.rgb * 0.12 * (1.0 + bass * 0.6);

  // Field magnitude contours
  let contour = abs(fract(log(field_intensity + 1.0) * 3.0) - 0.5) * 2.0;
  let contour_glow = exp(-contour * contour * 30.0) * 0.08 * depth;
  color += field_palette(fract(field_intensity * 0.05 + p4), p4) * contour_glow;

  // Magnetic storm shimmer (bass-driven)
  let stormNoise = hashf(dot(uv, vec2<f32>(50.0, 30.0)) + time * 8.0);
  color += vec3<f32>(0.3, 0.5, 0.8) * bass * 0.2 * stormNoise * field_intensity * 0.1;

  // Aurora-like background glow
  let aurora = sin(uv.x * 3.0 + time * p2 * 0.2) * exp(-abs(uv.y) * 2.0);
  color += vec3<f32>(0.1, 0.4, 0.3) * aurora * 0.05 * (1.0 + bass);

  // Subtle pulsing
  color *= 1.0 + sin(time * p2 * 0.8) * 0.08;

  // Depth-based intensity falloff
  let depthFalloff = 0.5 + 0.5 * depth;
  color *= depthFalloff;

  // Bass modulation
  let bassMod = 1.0 + bass * 0.4;
  color *= bassMod;

  // Temporal persistence for glow trails
  let persistence = 0.92 - bass * 0.04;
  let temporal = prev * persistence * (0.6 + depth * 0.4);
  color = max(color, temporal);

  // ACES tone mapping
  color = acesToneMap(color * 1.5);

  let particle_density = clamp(gResult.w, 0.0, 1.0);
  let f_intensity = clamp(field_intensity * 0.5, 0.0, 1.0);
  let alpha = f_intensity * particle_density * depth;

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(f_intensity, 0.0, 0.0, 0.0));
}
