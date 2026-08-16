// ═══════════════════════════════════════════════════════════════════
//  Interactive Fresnel
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, chromatic-aberration, depth-mass, upgraded-rgba, temporal
//  Complexity: High
//  Upgraded: 2026-08-16 (Batch 52: 2.5D Fresnel lens curvature, Cauchy dispersion, exact C load)
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=LensingPower, y=RingCount, z=RingThickness, w=Dispersion
  ripples: array<vec4<f32>, 50>,
};

fn aces_film(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn fresnel_height(p: vec2<f32>, center: vec2<f32>, ring_spacing: f32, depth_val: f32, t: f32, bass: f32) -> f32 {
  let d = length(p - center);
  let phase = d / max(ring_spacing, 0.005) - t * 1.5;
  let ring_local = fract(phase);
  let saw = ring_local * (1.0 - ring_local) * 4.0;
  let envelope = exp(-d * mix(1.8, 3.5, 1.0 - depth_val));
  let dynamic_ripple = sin(d * 42.0 - t * 4.0) * 0.15 * (1.0 + bass);
  return (saw + dynamic_ripple) * envelope;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let t = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let lensing_power = u.zoom_params.x * (1.0 + bass * 0.45);
  let ring_count = max(u.zoom_params.y * 14.0 + 2.0, 1.0);
  let ring_thickness = max(u.zoom_params.z * 0.15, 0.005);
  let dispersion = u.zoom_params.w * 0.04 * (1.0 + treble * 0.5);

  let mouse_pos = u.zoom_config.yz;
  let is_down = u.zoom_config.w;

  let depth_tex = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth_factor = mix(0.4, 1.4, depth_tex);

  // Aspect-corrected UV space centered at pointer
  let aspect_vec = vec2<f32>(aspect, 1.0);
  let p_corr = uv * aspect_vec;
  let mouse_corr = mouse_pos * aspect_vec;
  let dist_to_mouse = length(p_corr - mouse_corr);

  let ring_spacing = (1.0 / ring_count) * (0.8 + 0.4 * ring_thickness);

  // 2.5D surface normal evaluation via 4-tap central differences
  let eps = 1.0 / res.y;
  let h_c = fresnel_height(p_corr, mouse_corr, ring_spacing, depth_tex, t, bass);
  let h_r = fresnel_height(p_corr + vec2<f32>(eps, 0.0), mouse_corr, ring_spacing, depth_tex, t, bass);
  let h_l = fresnel_height(p_corr - vec2<f32>(eps, 0.0), mouse_corr, ring_spacing, depth_tex, t, bass);
  let h_u = fresnel_height(p_corr + vec2<f32>(0.0, eps), mouse_corr, ring_spacing, depth_tex, t, bass);
  let h_d = fresnel_height(p_corr - vec2<f32>(0.0, eps), mouse_corr, ring_spacing, depth_tex, t, bass);

  let dh_dx = (h_r - h_l) / (2.0 * eps);
  let dh_dy = (h_u - h_d) / (2.0 * eps);
  let normal = normalize(vec3<f32>(-dh_dx * lensing_power, -dh_dy * lensing_power, 1.0));

  // Click shockwave fronts (capped at 50)
  var click_disp = vec2<f32>(0.0);
  let ripple_count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < ripple_count; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age >= 0.0 && age < 3.0) {
      let r_pos = r.xy * aspect_vec;
      let d_r = length(p_corr - r_pos);
      let speed = 0.55;
      let front = abs(d_r - age * speed);
      let pulse = exp(-front * 35.0) * exp(-age * 1.2);
      let dir_r = select(vec2<f32>(0.0), (p_corr - r_pos) / max(d_r, 0.001), d_r > 0.001);
      click_disp += dir_r * pulse * 0.035 * sin(d_r * 40.0 - age * 12.0);
    }
  }

  // Cauchy chromatic dispersion refraction
  let base_disp = normal.xy * (0.05 * lensing_power * depth_factor) + click_disp;
  let uv_r = clamp(uv + base_disp * (1.0 + dispersion * 2.5), vec2<f32>(0.001), vec2<f32>(0.999));
  let uv_g = clamp(uv + base_disp, vec2<f32>(0.001), vec2<f32>(0.999));
  let uv_b = clamp(uv + base_disp * (1.0 - dispersion * 2.5), vec2<f32>(0.001), vec2<f32>(0.999));

  let col_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
  let col_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
  let col_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;
  let base_sample = vec3<f32>(col_r, col_g, col_b);
  let src_alpha = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).a;

  // Exact float32 history read from dataTextureC
  let prev_state = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);

  // Fresnel specular highlight & annular caustic bands
  let view_dir = vec3<f32>(0.0, 0.0, 1.0);
  let light_dir = normalize(vec3<f32>(mouse_pos.x - 0.5, mouse_pos.y - 0.5, 0.7));
  let half_vec = normalize(light_dir + view_dir);
  let n_dot_h = max(dot(normal, half_vec), 0.0);
  let specular = pow(n_dot_h, 32.0) * (0.4 + 0.6 * is_down) * (1.0 + mids * 0.5);

  let n_dot_v = max(dot(normal, view_dir), 0.0);
  let fresnel_term = pow(1.0 - n_dot_v, 4.0) * (0.3 + lensing_power * 0.4);

  // Prismatic iridescent tint along gradient normal
  let irid_phase = h_c * 12.0 + t * 0.8;
  let irid_color = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.0, 4.0) + irid_phase);

  var final_color = mix(base_sample, irid_color, fresnel_term * 0.35);
  final_color += vec3<f32>(1.0, 0.95, 0.85) * specular;
  final_color = mix(final_color, prev_state.rgb, 0.12); // smooth temporal persistence

  final_color = aces_film(final_color);

  let out_rgba = vec4<f32>(final_color, src_alpha);
  let out_depth = clamp(depth_tex + h_c * 0.25 * lensing_power, 0.0, 1.0);

  textureStore(writeTexture, coord, out_rgba);
  textureStore(dataTextureA, coord, out_rgba);
  textureStore(writeDepthTexture, coord, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
}
