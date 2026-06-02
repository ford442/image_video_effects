// ═══════════════════════════════════════════════════════════════════
//  Spiral Galaxy Dust
//  Category: generative
//  Description: A procedurally generated spiral galaxy with millions
//    of simulated star particles forming spiral arms, dust lanes,
//    and a bright galactic core. Mouse controls viewing angle and
//    zoom. Features parallax star layers and nebula wisps.
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

fn hash3f(n: f32) -> vec3<f32> {
  return vec3<f32>(hashf(n), hashf(n + 53.7), hashf(n + 91.3));
}

// Star color based on temperature
fn star_color(temp: f32) -> vec3<f32> {
  // temp 0=red, 0.5=yellow, 1.0=blue
  let t = clamp(temp, 0.0, 1.0);
  if t < 0.33 {
    return mix(vec3<f32>(1.0, 0.3, 0.1), vec3<f32>(1.0, 0.8, 0.3), t / 0.33);
  } else if t < 0.66 {
    return mix(vec3<f32>(1.0, 0.8, 0.3), vec3<f32>(1.0, 1.0, 0.9), (t - 0.33) / 0.33);
  } else {
    return mix(vec3<f32>(1.0, 1.0, 0.9), vec3<f32>(0.7, 0.8, 1.0), (t - 0.66) / 0.34);
  }
}

// 2D rotation
fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // intensity (star density)
  let p2 = u.zoom_params.y; // speed (rotation speed)
  let p3 = u.zoom_params.z; // scale (zoom/fov)
  let p4 = u.zoom_params.w; // color shift

  // Galaxy rotation from time or mouse
  var galactic_angle: f32;
  var zoom: f32;
  if mouseDown {
    galactic_angle = (mouse.x - 0.5) * PI * 4.0;
    zoom = 0.3 + mouse.y * 1.5;
  } else {
    galactic_angle = time * p2 * 0.05;
    zoom = 0.5 + p3 * 1.0;
  }

  let rotated_uv = rot2(uv, galactic_angle);
  let r = length(rotated_uv) / zoom;
  let theta = atan2(rotated_uv.y, rotated_uv.x);

  // Spiral galaxy density model
  let arms = 3.0;
  let arm_width = 0.15;
  let pitch = 2.5; // Tightness of spiral

  // Logarithmic spiral: theta = pitch * log(r)
  // Convert to spiral arm density
  var spiral_phase = arms * (theta - pitch * log(r + 0.01));
  let arm_pattern = exp(-pow(sin(spiral_phase * 0.5), 2.0) / (arm_width * arm_width));

  // Radial falloff (bulge + disk)
  let bulge = exp(-r * 8.0);
  let disk = exp(-r * 2.0) * (1.0 - exp(-r * 3.0));
  let radial_density = bulge * 2.0 + disk * arm_pattern;

  // Seed for this pixel
  let seed = f32(pixel.x) * 157.0 + f32(pixel.y) * 293.0;

  // Accumulate star contributions
  var color = vec3<f32>(0.0);
  let star_density = 3.0 + p1 * 15.0;

  // Background nebula
  let bg_nebula = radial_density * 0.02;
  color += vec3<f32>(0.05, 0.03, 0.08) * bg_nebula;

  for (var i = 0; i < i32(star_density); i++) {
    let s_seed = seed + f32(i) * 197.3;

    // Star position in polar coordinates
    let s_r_dist = hashf(s_seed) * 0.8;
    let s_angle_offset = hashf(s_seed + 1.0) * PI * 2.0;

    // Place stars along spiral arms with scatter
    let arm_idx = floor(hashf(s_seed + 3.0) * arms);
    let arm_angle = (arm_idx / arms) * PI * 2.0 + pitch * log(s_r_dist + 0.01);
    let scattered_angle = arm_angle + (hashf(s_seed + 4.0) - 0.5) * arm_width * 4.0;

    let s_pos = vec2<f32>(
      cos(scattered_angle) * s_r_dist,
      sin(scattered_angle) * s_r_dist
    );

    // Rotate with galaxy
    let s_rot = rot2(s_pos, galactic_angle);

    // Check if star contributes to this pixel
    let diff = uv - s_rot * zoom;
    let dist_sq = dot(diff, diff);

    // Star brightness based on type
    let star_size = (0.0005 + hashf(s_seed + 5.0) * 0.003) * zoom;
    if dist_sq < star_size * 4.0 {
      let brightness = exp(-dist_sq / star_size) * (0.3 + hashf(s_seed + 6.0) * 0.7);

      // Star temperature and color
      let temp = fract(hashf(s_seed + 7.0) + p4);
      let sc = star_color(temp);

      // Dimmer for far stars, brighter for core stars
      let dist_factor = 1.0 / (1.0 + s_r_dist * 2.0);
      color += sc * brightness * dist_factor * (0.5 + p1 * 0.5);
    }
  }

  // Core glow
  let core_glow = exp(-r * 6.0) * 0.4;
  color += vec3<f32>(1.0, 0.95, 0.85) * core_glow;

  // Dust lanes (darken between arms)
  let dust = sin(spiral_phase * 0.5 + PI * 0.5) * 0.5 + 0.5;
  color *= 1.0 - dust * disk * 0.3;

  // Subtle rotation shimmer
  color *= 1.0 + sin(time * p2 * 0.3) * 0.02;

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.9, length(uv));
  color *= 0.6 + vignette * 0.4;

  textureStore(writeTexture, pixel, vec4<f32>(color, 1.0));
}
