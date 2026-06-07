// ═══════════════════════════════════════════════════════════════════
//  Magnetic Storm
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-06-06
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Hash functions
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

// Value noise
fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i),                 hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// Curl noise — approximates a divergence-free vector field for smooth flow lines
fn curl(p: vec2<f32>, eps: f32) -> vec2<f32> {
  let dx = vec2<f32>(eps, 0.0);
  let dy = vec2<f32>(0.0, eps);
  // dF/dy, -dF/dx gives divergence-free field
  let dFdy = (vnoise(p + dy) - vnoise(p - dy)) / (2.0 * eps);
  let dFdx = (vnoise(p + dx) - vnoise(p - dx)) / (2.0 * eps);
  return vec2<f32>(dFdy, -dFdx);
}

// FBM for field texture
fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var amp = 0.5;
  var pp = p;
  for (var i = 0u; i < 5u; i++) {
    v += amp * vnoise(pp);
    pp *= 2.0;
    amp *= 0.5;
  }
  return v;
}

// ACES tonemap
fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// HSV to RGB
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let hh = h * 6.0;
  let x = c * (1.0 - abs(fract(hh * 0.5) * 2.0 - 1.0));
  let m = v - c;
  let idx = u32(hh) % 6u;
  var rgb = vec3<f32>(0.0);
  if (idx == 0u) { rgb = vec3<f32>(c, x, 0.0); }
  else if (idx == 1u) { rgb = vec3<f32>(x, c, 0.0); }
  else if (idx == 2u) { rgb = vec3<f32>(0.0, c, x); }
  else if (idx == 3u) { rgb = vec3<f32>(0.0, x, c); }
  else if (idx == 4u) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + m;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv    = vec2<f32>(global_id.xy) / vec2<f32>(dims);

  let t      = u.config.x;
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let field_scale  = mix(1.0, 8.0,  u.zoom_params.x); // spatial zoom for field
  let flow_speed   = mix(0.1, 2.0,  u.zoom_params.y) * (1.0 + bass * 0.5);
  let line_density = mix(2.0, 20.0, u.zoom_params.z) * (1.0 + mids * 0.2);
  let storm_power  = mix(0.5, 4.0,  u.zoom_params.w) * (1.0 + bass * 0.4);

  // Aspect-corrected screen coords
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);

  // Mouse = magnetic pole position
  let pole = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  let to_pole = pole - p;
  let pole_dist = max(length(to_pole), 0.001);

  // Dipole field: 1/r^2 force away from pole
  let dipole = to_pole / (pole_dist * pole_dist);

  // Field coords for curl noise
  let fc = p * field_scale * 0.3 + vec2<f32>(t * flow_speed * 0.05);

  // Curl noise for turbulent storm flow
  let curl_v = curl(fc, 0.01) * storm_power;

  // FBM energy field
  let energy = fbm(fc + curl_v * 0.5);

  // Field-line visualization: sin bands along the curl direction
  let field_dir = normalize(curl_v + dipole * 0.3 + vec2<f32>(0.0001));
  let perp = vec2<f32>(-field_dir.y, field_dir.x);
  let band_coord = dot(p, perp) * line_density + t * flow_speed * 0.3;
  let field_line = smoothstep(0.3, 0.0, abs(fract(band_coord) - 0.5));

  // Corona glow around the pole
  let corona = exp(-pole_dist * 3.0) * (1.0 + bass * 0.6);

  // Energy rings radiating from pole
  let ring = sin(pole_dist * 12.0 - t * flow_speed * 2.0) * 0.5 + 0.5;
  let ring_band = smoothstep(0.4, 0.0, abs(ring - 0.5)) * exp(-pole_dist * 1.5);

  // Color: cyan/blue magnetic lines, orange/red near the pole
  let hue_lines = 0.55 + mids * 0.1;               // blue-cyan
  let hue_corona = 0.05 + bass * 0.05;             // red-orange
  let hue_ring   = fract(0.7 + t * 0.04);          // shifting purple

  let line_col   = hsv2rgb(hue_lines,  0.8, field_line * energy * 2.0);
  let corona_col = hsv2rgb(hue_corona, 0.9, corona);
  let ring_col   = hsv2rgb(hue_ring,   0.7, ring_band);

  // Treble sparkle at field-line intersections
  let spark = hash12(uv + fract(vec2<f32>(t * 0.003))) * treble * 0.2 * field_line;

  var col = line_col + corona_col * 0.6 + ring_col * 0.5 + spark;

  // Vignette
  let r = length(p / vec2<f32>(aspect, 1.0));
  col *= 1.0 - smoothstep(0.7, 1.3, r);

  // Tonemap
  col = aces(col);

  // Alpha: field-line brightness + corona + click burst
  let click_burst = select(1.0, 1.8, u.zoom_config.w > 0.5);
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp((luma * 0.6 + field_line * 0.3 + corona * 0.1) * click_burst, 0.0, 1.0);

  // Depth: pole proximity = near (depth ~1), edges = far
  let depth = clamp(1.0 - pole_dist * 0.4, 0.0, 1.0);

  let final_color = vec4<f32>(acesToneMap(col * 1.1), alpha);
  textureStore(writeTexture,      coord, final_color);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, final_color);
}
