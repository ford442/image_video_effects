// ═══════════════════════════════════════════════════════════════════
//  Velocity Field — Vorticity Confinement
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal, fluid-dynamics
//  Complexity: High
//  Upgraded: 2026-08-16 (Batch 52: 2D Navier-Stokes momentum advection, vorticity confinement, exact C load)
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
  zoom_params: vec4<f32>,  // x=Dissipation, y=BrushSize, z=Force, w=VortConfinement
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

fn simplex_flow(p: vec2<f32>, t: f32) -> vec2<f32> {
  let k1 = vec2<f32>(cos(t * 0.4 + p.y * 1.8), sin(t * 0.35 + p.x * 1.6));
  let k2 = vec2<f32>(-sin(t * 0.55 + p.y * 3.2), cos(t * 0.45 + p.x * 3.0));
  return k1 * 0.6 + k2 * 0.4;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let aspect_vec = vec2<f32>(aspect, 1.0);
  let t = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let dissipation = mix(0.92, 0.995, 1.0 - u.zoom_params.x * 0.8);
  let brush_size = max(u.zoom_params.y * 0.25 + 0.02, 0.01);
  let force = u.zoom_params.z * (1.5 + bass * 0.8);
  let vort_confinement = u.zoom_params.w * (2.0 + mids * 1.2);

  let mouse_pos = u.zoom_config.yz;
  let is_down = u.zoom_config.w;

  let depth_tex = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth_viscosity = mix(0.6, 1.5, depth_tex);

  // Exact load of previous velocity state from dataTextureC
  let prev_raw = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);
  var prev_vel = prev_raw.xy;
  var prev_dye = prev_raw.zw;

  // 4-neighbor velocity stencil for discrete vorticity and laplace diffusion
  let c_r = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).xy;
  let c_l = textureLoad(dataTextureC, clamp(coord - vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).xy;
  let c_u = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).xy;
  let c_d = textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).xy;

  // Discrete curl: omega = dv_y/dx - dv_x/dy
  let omega = ((c_r.y - c_l.y) - (c_u.x - c_d.x)) * 0.5;
  let lap_vel = (c_r + c_l + c_u + c_d - 4.0 * prev_vel) * 0.25;

  // Vorticity confinement force: f_conf = epsilon * (nabla |omega| x omega / |omega|)
  let omega_r = abs(c_r.y - c_r.x);
  let omega_l = abs(c_l.y - c_l.x);
  let omega_u = abs(c_u.y - c_u.x);
  let omega_d = abs(c_d.y - c_d.x);
  let grad_omega = vec2<f32>(omega_r - omega_l, omega_u - omega_d) * 0.5;
  let len_grad = length(grad_omega);
  let conf_dir = select(vec2<f32>(0.0), vec2<f32>(grad_omega.y, -grad_omega.x) / max(len_grad, 0.001), len_grad > 0.001);
  let conf_force = conf_dir * omega * vort_confinement * 0.15;

  // Pointer drag vortex injection
  let d_pos = (uv - mouse_pos) * aspect_vec;
  let dist_mouse = length(d_pos);
  let brush_weight = smoothstep(brush_size, 0.0, dist_mouse);
  let vortex_dir = select(vec2<f32>(0.0), vec2<f32>(-d_pos.y, d_pos.x) / max(dist_mouse, 0.001), dist_mouse > 0.001);
  let mouse_force = vortex_dir * (force * brush_weight * (0.8 + 1.2 * is_down));

  // Background conveyor stream
  let bg_stream = simplex_flow(uv * 3.5, t) * 0.004 * (1.0 + treble * 0.4);

  // Click shock fronts (capped at 50)
  var click_force = vec2<f32>(0.0);
  let ripple_count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < ripple_count; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age >= 0.0 && age < 2.5) {
      let r_pos = (uv - r.xy) * aspect_vec;
      let d_r = length(r_pos);
      let front = abs(d_r - age * 0.45);
      let pulse = exp(-front * 30.0) * exp(-age * 1.5);
      let r_dir = select(vec2<f32>(0.0), r_pos / max(d_r, 0.001), d_r > 0.001);
      click_force += r_dir * pulse * 0.06 * sin(d_r * 35.0 - age * 10.0);
    }
  }

  // Momentum integration
  var new_vel = (prev_vel + lap_vel * 0.35 + conf_force + mouse_force + bg_stream + click_force) * dissipation;
  new_vel /= depth_viscosity;

  // Dye transport and dispersion
  let advect_coord = uv - new_vel * 0.02;
  let dye_sample = textureSampleLevel(readTexture, u_sampler, clamp(advect_coord, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let src_alpha = dye_sample.a;

  // Chromatic shear sampling along velocity vector
  let shear_mag = length(new_vel) * 0.04;
  let shear_dir = select(vec2<f32>(0.0), normalize(new_vel), length(new_vel) > 0.0001);
  let s_r = textureSampleLevel(readTexture, u_sampler, clamp(advect_coord + shear_dir * shear_mag, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let s_g = textureSampleLevel(readTexture, u_sampler, clamp(advect_coord, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).g;
  let s_b = textureSampleLevel(readTexture, u_sampler, clamp(advect_coord - shear_dir * shear_mag, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  let sheared_color = vec3<f32>(s_r, s_g, s_b);

  // Vorticity kinetic luminescence
  let speed = length(new_vel);
  let kinetic_glow = 0.5 + 0.5 * cos(vec3<f32>(0.0, 1.8, 3.6) + abs(omega) * 12.0 + t * 0.5);
  var final_color = mix(sheared_color, kinetic_glow, clamp(speed * 4.0, 0.0, 0.65));

  final_color = aces_film(final_color);

  let out_rgba = vec4<f32>(final_color, src_alpha);
  let out_state = vec4<f32>(new_vel.x, new_vel.y, omega, speed);
  let out_depth = clamp(depth_tex + speed * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, out_rgba);
  textureStore(dataTextureA, coord, out_state);
  textureStore(writeDepthTexture, coord, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
}
