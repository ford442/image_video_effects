// ═══════════════════════════════════════════════════════════════════
//  Phoenix Fractal Flame
//  Category: generative
//  Description: The Phoenix fractal set with flame-like coloring.
//    Iterates z = z^2 + c + p*z_prev creating intricate fractal
//    patterns with fiery orange-red coloring. Mouse controls the
//    Julia seed parameter. Supports zoom and pan exploration.
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

// Smooth palette interpolation for flame colors
fn flame_palette(t: f32) -> vec3<f32> {
  let c0 = vec3<f32>(0.02, 0.02, 0.05);
  let c1 = vec3<f32>(0.15, 0.05, 0.15);
  let c2 = vec3<f32>(0.55, 0.10, 0.08);
  let c3 = vec3<f32>(0.95, 0.45, 0.08);
  let c4 = vec3<f32>(1.0, 0.75, 0.15);
  let c5 = vec3<f32>(1.0, 0.95, 0.60);
  let c6 = vec3<f32>(1.0, 1.0, 0.95);

  if t < 0.15 { return mix(c0, c1, t / 0.15); }
  if t < 0.30 { return mix(c1, c2, (t - 0.15) / 0.15); }
  if t < 0.45 { return mix(c2, c3, (t - 0.30) / 0.15); }
  if t < 0.60 { return mix(c3, c4, (t - 0.45) / 0.15); }
  if t < 0.80 { return mix(c4, c5, (t - 0.60) / 0.20); }
  return mix(c5, c6, (t - 0.80) / 0.20);
}

fn hash2(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // intensity (zoom level)
  let p2 = u.zoom_params.y; // speed (animation speed)
  let p3 = u.zoom_params.z; // scale (fractal detail)
  let p4 = u.zoom_params.w; // color shift

  // Zoom and pan controls
  let zoom = 2.0 * exp(-p1 * 3.0);
  let pan = mouseDown ? (mouse - 0.5) * 2.0 : vec2<f32>(0.0);

  // Julia-like seed from mouse (when clicked) or animated
  var julia_c: vec2<f32>;
  if mouseDown {
    julia_c = (mouse - 0.5) * 2.0;
  } else {
    let angle = time * p2 * 0.3;
    julia_c = vec2<f32>(cos(angle * 0.7) * 0.4, sin(angle * 0.5) * 0.3);
  }

  let p_phoenix = sin(time * p2 * 0.2) * 0.3; // Phoenix parameter

  // Screen coordinate mapping
  let c = uv * zoom + vec2<f32>(-0.25, 0.0) + pan * 0.3;
  let px_size = zoom / min(resolution.x, resolution.y);

  // Supersampling offset
  let aa_offset = hash2(vec2<f32>(pixel) + time * 100.0) * px_size - px_size * 0.5;

  // Phoenix iteration: z = z^2 + c + p*z_prev
  var z = c + aa_offset;
  var z_prev = z;
  var iter = 0;
  let max_iter = i32(20.0 + p3 * 180.0);

  for (var i = 0; i < max_iter; i++) {
    let z_new = vec2<f32>(
      z.x * z.x - z.y * z.y + c.x + p_phoenix * z_prev.x,
      2.0 * z.x * z.y + c.y + p_phoenix * z_prev.y
    );
    z_prev = z;
    z = z_new;
    iter++;
    if dot(z, z) > 16.0 { break; }
  }

  // Smooth coloring
  let smooth_iter = f32(iter);
  let escape_radius = dot(z, z);
  var color_val: f32;
  if iter < max_iter {
    color_val = smooth_iter - log2(log2(escape_radius)) + 4.0;
    color_val = color_val / f32(max_iter) * 3.0;
  } else {
    color_val = 0.0;
  }

  // Color shift from parameter
  color_val = fract(color_val + p4);

  // Base coloring
  var color = flame_palette(color_val);

  // Inner glow
  let inner_dist = length(uv * zoom + vec2<f32>(-0.25, 0.0));
  let glow = exp(-inner_dist * 4.0) * 0.2;
  color += flame_palette(fract(time * 0.05 + p4 + 0.5)) * glow;

  // Add subtle periodic shimmer
  color += vec3<f32>(0.02) * sin(time * 2.0 + color_val * 20.0) * p2;

  textureStore(writeTexture, pixel, vec4<f32>(color, 1.0));
}
