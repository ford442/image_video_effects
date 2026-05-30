// ═══════════════════════════════════════════════════════════════════
//  Buddhabrot Aura
//  Category: generative
//  Description: Renders the Buddhabrot - a density plot of Mandelbrot
//    trajectories. Points are iterated and their paths accumulate
//    into a glowing density field, creating the iconic Buddha-like
//    silhouette with ethereal aura. Mouse controls orbit threshold.
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

// Density-to-color mapping with ethereal tones
fn aura_color(density: f32, p4: f32) -> vec3<f32> {
  let d = clamp(density, 0.0, 1.0);
  // Ethereal palette: deep purple -> blue -> cyan -> white
  let c0 = vec3<f32>(0.02, 0.01, 0.05);
  let c1 = vec3<f32>(0.08, 0.03, 0.15);
  let c2 = vec3<f32>(0.15, 0.05, 0.30);
  let c3 = vec3<f32>(0.20, 0.10, 0.50);
  let c4 = vec3<f32>(0.25, 0.20, 0.70);
  let c5 = vec3<f32>(0.30, 0.45, 0.85);
  let c6 = vec3<f32>(0.50, 0.70, 0.95);
  let c7 = vec3<f32>(0.75, 0.88, 1.00);
  let c8 = vec3<f32>(0.90, 0.95, 1.00);

  let shifted = fract(d + p4);
  if shifted < 0.111 { return mix(c0, c1, shifted / 0.111); }
  if shifted < 0.222 { return mix(c1, c2, (shifted - 0.111) / 0.111); }
  if shifted < 0.333 { return mix(c2, c3, (shifted - 0.222) / 0.111); }
  if shifted < 0.444 { return mix(c3, c4, (shifted - 0.333) / 0.111); }
  if shifted < 0.555 { return mix(c4, c5, (shifted - 0.444) / 0.111); }
  if shifted < 0.666 { return mix(c5, c6, (shifted - 0.555) / 0.111); }
  if shifted < 0.777 { return mix(c6, c7, (shifted - 0.666) / 0.111); }
  if shifted < 0.888 { return mix(c7, c8, (shifted - 0.777) / 0.111); }
  return mix(c8, vec3<f32>(1.0), (shifted - 0.888) / 0.112);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // intensity (sample count)
  let p2 = u.zoom_params.y; // speed (temporal flow)
  let p3 = u.zoom_params.z; // scale (zoom)
  let p4 = u.zoom_params.w; // color shift

  // Zoom
  let zoom = 2.5 * exp(-p3 * 2.0);

  // View bounds
  let view_min = vec2<f32>(-2.5, -2.0) * zoom + vec2<f32>(-0.5, 0.0);
  let view_max = vec2<f32>(1.5, 2.0) * zoom + vec2<f32>(-0.5, 0.0);

  // Pixel seed
  let seed = f32(pixel.x) * 197.0 + f32(pixel.y) * 293.0 + time * p2 * 10.0;
  let num_samples = i32(5.0 + p1 * 30.0);

  var density_r: f32 = 0.0;
  var density_g: f32 = 0.0;
  var density_b: f32 = 0.0;

  // Threshold from mouse Y
  let orbit_thresh_low = i32(20.0 + (mouseDown ? mouse.y : 0.3) * 100.0);
  let orbit_thresh_high = orbit_thresh_low + i32(50.0 + p1 * 150.0);

  for (var s = 0; s < num_samples; s++) {
    // Random point in the complex plane (in the cardioid/bulb region)
    var c: vec2<f32>;
    let sample_seed = seed + f32(s) * 53.7;

    // Sample from a region likely to produce orbits
    c = vec2<f32>(
      hashf(sample_seed) * 3.0 - 2.0,
      hashf(sample_seed + 1.0) * 2.5 - 1.25
    );

    // Quick reject: check if in main cardioid or period-2 bulb
    let q = (c.x - 0.25) * (c.x - 0.25) + c.y * c.y;
    let in_cardioid = q * (q + (c.x - 0.25)) < 0.25 * c.y * c.y;
    let in_bulb = (c.x + 1.0) * (c.x + 1.0) + c.y * c.y < 0.0625;
    if in_cardioid || in_bulb { continue; }

    // Iterate and store orbit
    var z = vec2<f32>(0.0);
    var orbit_r: f32 = 0.0;
    var orbit_g: f32 = 0.0;
    var orbit_b: f32 = 0.0;
    var escaped = false;

    // Collect orbit points
    var orbit_points: array<vec2<f32>, 20>;
    var orbit_len = 0;

    for (var i = 0; i < orbit_thresh_high && i < 500; i++) {
      z = vec2<f32>(z.x * z.x - z.y * z.y + c.x, 2.0 * z.x * z.y + c.y);

      if dot(z, z) > 4.0 {
        escaped = true;
        break;
      }

      if i >= orbit_thresh_low && orbit_len < 20 {
        orbit_points[orbit_len] = z;
        orbit_len++;
      }
    }

    if !escaped || orbit_len == 0 { continue; }

    // Accumulate orbit into density
    for (var i = 0; i < orbit_len; i++) {
      let zp = orbit_points[i];

      // Map to screen
      let sp = (zp - view_min) / (view_max - view_min) - 0.5;
      let diff = uv - sp;
      let dist_sq = dot(diff, diff);

      // Gaussian splat
      let splat = exp(-dist_sq * 8000.0 * zoom);

      if i < 7 { density_r += splat; }
      else if i < 14 { density_g += splat; }
      else { density_b += splat; }
    }
  }

  // Tone mapping
  let exposure = 2.0;
  density_r = 1.0 - exp(-density_r * exposure);
  density_g = 1.0 - exp(-density_g * exposure);
  density_b = 1.0 - exp(-density_b * exposure);

  // Color with aura palette
  let total_dens = (density_r + density_g + density_b) / 3.0;
  var color = aura_color(total_dens, p4);

  // Channel-specific coloring for ethereal effect
  color = mix(color, vec3<f32>(density_r * 1.2, density_g * 0.9, density_b * 1.5) * 0.5, 0.3);

  // Subtle temporal pulse
  color *= 1.0 + sin(time * p2 * 0.5) * 0.05;

  textureStore(writeTexture, pixel, vec4<f32>(color, 1.0));
}
