// ═══════════════════════════════════════════════════════════════════
//  Magnetic Storm
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Alfvén-wave kinks travelling along field lines at v_A ∝ √|B|; storm-expanded auroral oval (557.7 nm green base, 630 nm red crown) with ray striations
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // x=Time, y=rippleCount, zw=resolution
  zoom_config: vec4<f32>,  // x=Time, yz=mouse uv, w=mouse down
  zoom_params: vec4<f32>,  // x=Field Scale, y=Flow Speed, z=Line Density, w=Storm Power
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv    = vec2<f32>(global_id.xy) / vec2<f32>(dims);

  let t      = u.config.x;
  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let held   = clamp(u.zoom_config.w, 0.0, 1.0);

  // Parameters
  let field_scale  = mix(1.0, 8.0,  u.zoom_params.x); // spatial zoom for field
  let flow_speed   = mix(0.1, 2.0,  u.zoom_params.y) * (1.0 + bass * 0.4);
  let line_density = mix(2.0, 20.0, u.zoom_params.z) * (1.0 + mids * 0.2);
  let storm_power  = mix(0.5, 4.0,  u.zoom_params.w) * (1.0 + bass * 0.35);

  // Aspect-corrected screen coords
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);

  // Mouse = magnetic pole position; holding the mouse strengthens the pole
  let pole = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  let to_pole = pole - p;
  let pole_dist = max(length(to_pole), 0.001);
  let pole_strength = 1.0 + held * 1.2;

  // Dipole field: 1/r^2 force away from pole
  let dipole = to_pole / (pole_dist * pole_dist) * pole_strength;

  // Field coords for curl noise
  let fc = p * field_scale * 0.3 + vec2<f32>(t * flow_speed * 0.05);

  // Curl noise for turbulent storm flow
  let curl_v = curl(fc, 0.01) * storm_power;

  // FBM energy field
  let energy = fbm(fc + curl_v * 0.5);

  // Click ripples: sudden-storm-commencement shock fronts compress field lines
  var shock = 0.0;
  var shock_shift = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = t - rp.z;
    if (age >= 0.0 && age < 2.0) {
      let rpos = (rp.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
      let front = length(p - rpos) - age * 0.9;
      let env = exp(-age * 1.6);
      shock = max(shock, exp(-abs(front) * 30.0) * env);
      // behind the front the magnetosphere is compressed (bands squeezed)
      shock_shift += smoothstep(0.25, 0.0, abs(front)) * sign(front) * env * 0.6;
    }
  }

  // Field-line visualization: sin bands along the curl direction
  let field_vec = curl_v + dipole * 0.3 + vec2<f32>(0.0001);
  let field_dir = normalize(field_vec);
  let perp = vec2<f32>(-field_dir.y, field_dir.x);

  // ── IDEA 1: Alfvén-wave kinks ──
  // Transverse Alfvén waves ride along B with phase speed v_A = B/√(μ0ρ) ∝ √|B|:
  // lines near the pole (strong B) ripple fast, lines in weak gaps crawl.
  let b_mag = length(field_vec);
  let v_alfven = clamp(sqrt(b_mag), 0.2, 3.0);
  let along = dot(p, field_dir);
  let k_par = line_density * 0.6;
  let kink_amp = (0.08 + mids * 0.12) * (0.4 + u.zoom_params.w * 0.6);
  let kink = sin(along * k_par * 6.2831 - t * flow_speed * v_alfven * 3.0) * kink_amp;

  let band_coord = dot(p, perp) * line_density + t * flow_speed * 0.3 + kink + shock_shift;
  let field_line = smoothstep(0.3, 0.0, abs(fract(band_coord) - 0.5));

  // Corona glow around the pole
  let corona = exp(-pole_dist * 3.0) * (1.0 + bass * 0.5) * (0.8 + held * 0.5);

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

  // ── IDEA 2: storm-expanded auroral oval ──
  // Precipitating particles light an oval around the pole; storm intensity
  // pushes it equatorward (larger radius). The sharp inner edge glows oxygen
  // 557.7 nm green, the diffuse outer crown 630 nm red; curtains fold with the
  // curl flow and carry field-aligned ray striations.
  let rel = -to_pole;
  let theta = atan2(rel.y, rel.x);
  let oval_r = 0.28 + storm_power * 0.06 + bass * 0.05 + held * 0.05;
  let fold = (fbm(vec2<f32>(theta * 2.0, t * flow_speed * 0.15)) - 0.5) * 0.18 + dot(curl_v, rel / pole_dist) * 0.01;
  let radial = pole_dist - (oval_r + fold);
  let green_edge = exp(-max(-radial, 0.0) * 60.0) * smoothstep(0.12, 0.0, radial) * step(-0.06, radial);
  let red_crown = exp(-abs(radial - 0.09) * 14.0);
  let rays = 0.45 + 0.55 * pow(vnoise(vec2<f32>(theta * 38.0, t * (0.6 + treble * 3.0))), 2.0);
  let aurora_gain = (0.35 + u.zoom_params.w * 0.5) * (1.0 + bass * 0.4) * (1.0 + held * 0.8);
  let aurora = (green_edge + red_crown * 0.35) * rays * aurora_gain;
  col += (vec3<f32>(0.25, 1.0, 0.45) * green_edge + vec3<f32>(0.9, 0.12, 0.2) * red_crown * 0.35) * rays * aurora_gain;

  // Shock fronts
  col += vec3<f32>(0.6, 0.7, 1.3) * shock * (0.7 + bass * 0.5);

  // Vignette
  let r = length(p / vec2<f32>(aspect, 1.0));
  col *= 1.0 - smoothstep(0.7, 1.3, r);

  // Single ACES tonemap
  col = aces(col * 1.1);

  // Alpha: field-line brightness + corona + aurora + shock, boosted while held
  let click_burst = 1.0 + held * 0.8;
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp((luma * 0.55 + field_line * 0.3 + corona * 0.1 + aurora * 0.2 + shock * 0.3) * click_burst, 0.0, 1.0);

  // Depth: pole proximity = near (depth ~1), edges = far
  let depth = clamp(1.0 - pole_dist * 0.4, 0.0, 1.0);

  let final_color = vec4<f32>(col, alpha);
  textureStore(writeTexture,      coord, final_color);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, final_color);
}
