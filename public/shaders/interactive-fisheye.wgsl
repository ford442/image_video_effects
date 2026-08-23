// ═══════════════════════════════════════════════════════════════════
//  Fluid Lens Dynamics — Batch 58E
//  Keeps Kelvin-Voigt droplet + capillary waves + exact C state.
//  Adds held meniscus pinch, oil-slick thin-film rim, traveling
//  caustic runners, bounded splash fronts. A remains [h, v, nx, ny].
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

fn aces_film(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn droplet_shape(p: vec2<f32>, center: vec2<f32>, radius: f32, stretch_dir: vec2<f32>, stretch_mag: f32) -> f32 {
  let d = p - center;
  let len_d = length(d);
  if (len_d > radius * 1.5) { return 0.0; }
  let parallel = dot(d, stretch_dir);
  let perp = length(d - stretch_dir * parallel);
  let eff_r = sqrt(parallel * parallel / max(1.0 + stretch_mag * 1.8, 0.1) + perp * perp);
  let h = max(0.0, 1.0 - (eff_r / max(radius, 0.001)) * (eff_r / max(radius, 0.001)));
  return sqrt(h);
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

  let surface_tension = u.zoom_params.x * (1.0 + bass * 0.35);
  let viscosity = clamp(u.zoom_params.y, 0.05, 0.98);
  let mass = max(u.zoom_params.z * 1.5 + 0.2, 0.1);
  let splash_thresh = mix(0.15, 2.5, u.zoom_params.w);

  let mouse_pos = u.zoom_config.yz;
  let is_down = u.zoom_config.w;
  let held = f32(is_down > 0.5);

  let depth_tex = textureLoad(readDepthTexture, coord, 0).r;
  let depth_mass = mix(0.5, 1.6, depth_tex);

  let prev_state = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);
  let prev_h = prev_state.r;
  let prev_v = prev_state.g;

  let rc = min(u32(u.config.y), 50u);
  var pointer_vel = vec2<f32>(0.0);
  if (rc >= 2u) {
    let r1 = u.ripples[rc - 1u];
    let r2 = u.ripples[rc - 2u];
    let dt = max(r1.z - r2.z, 0.016);
    pointer_vel = (r1.xy - r2.xy) / dt;
  }
  let speed = length(pointer_vel * aspect_vec);
  let stretch_dir = select(vec2<f32>(1.0, 0.0), normalize(pointer_vel * aspect_vec), speed > 0.001);
  let stretch_mag = clamp(speed * 0.12 / mass, 0.0, 1.5) * (1.0 + held * 0.45);

  let lens_radius = mix(0.18, 0.45, surface_tension * 0.5 + 0.25) * (1.0 + bass * 0.2) / depth_mass * mix(1.0, 0.78, held);
  let p_corr = uv * aspect_vec;
  let mouse_corr = mouse_pos * aspect_vec;

  let target_h = droplet_shape(p_corr, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let dist_m = length(p_corr - mouse_corr);
  let capillary = sin(dist_m * 48.0 - t * 6.0) * exp(-dist_m * 8.0) * (0.1 + 0.25 * is_down) * (1.0 + treble * 0.6);
  let runners = pow(max(0.0, sin(dist_m * 28.0 - t * (9.0 + mids * 5.0))), 12.0) * exp(-dist_m * 4.0);

  let spring_k = 12.0 * surface_tension / mass;
  let damp_c = 4.0 * viscosity;
  let accel = spring_k * (target_h + capillary - prev_h) - damp_c * prev_v;
  let dt_sub = 0.016;
  let new_v = prev_v + accel * dt_sub;
  let new_h = clamp(prev_h + new_v * dt_sub, 0.0, 2.0);

  let eps = 1.0 / res.y;
  let h_r = droplet_shape((uv + vec2<f32>(eps, 0.0)) * aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let h_l = droplet_shape((uv - vec2<f32>(eps, 0.0)) * aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let h_u = droplet_shape((uv + vec2<f32>(0.0, eps)) * aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let h_d = droplet_shape((uv - vec2<f32>(0.0, eps)) * aspect_vec, mouse_corr, lens_radius, stretch_dir, stretch_mag);
  let dn_dx = (h_r - h_l) / (2.0 * eps);
  let dn_dy = (h_u - h_d) / (2.0 * eps);
  let normal = normalize(vec3<f32>(-dn_dx * (0.8 + 0.4 * surface_tension), -dn_dy * (0.8 + 0.4 * surface_tension), 1.0));

  var splash_disp = vec2<f32>(0.0);
  var click = 0.0;
  for (var i = 0u; i < rc; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age >= 0.0 && age < 2.5) {
      let r_pos = r.xy * aspect_vec;
      let d_r = length(p_corr - r_pos);
      let front = abs(d_r - age * 0.6);
      let pulse = exp(-front * 30.0) * exp(-age * 1.4);
      let r_dir = select(vec2<f32>(0.0), (p_corr - r_pos) / max(d_r, 0.001), d_r > 0.001);
      splash_disp += r_dir * pulse * 0.04 * sin(d_r * 45.0 - age * 14.0) * (1.0 + splash_thresh * 0.15);
      click = max(click, pulse);
    }
  }

  let refr_vec = normal.xy * (0.12 * new_h) + splash_disp;
  let uv_r = clamp(uv + refr_vec * 1.06, vec2<f32>(0.001), vec2<f32>(0.999));
  let uv_g = clamp(uv + refr_vec, vec2<f32>(0.001), vec2<f32>(0.999));
  let uv_b = clamp(uv + refr_vec * 0.94, vec2<f32>(0.001), vec2<f32>(0.999));
  let c_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
  let c_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
  let c_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;
  let src_alpha = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).a;
  let refracted = vec3<f32>(c_r, c_g, c_b);

  let light_dir = normalize(vec3<f32>(mouse_pos.x - 0.5, mouse_pos.y - 0.5, 0.8));
  let view_dir = vec3<f32>(0.0, 0.0, 1.0);
  let half_v = normalize(light_dir + view_dir);
  let spec = pow(max(dot(normal, half_v), 0.0), 36.0) * (0.6 + 0.8 * is_down);
  let fresnel_term = pow(1.0 - max(dot(normal, view_dir), 0.0), 3.5) * new_h;
  let slick = hsv2rgb(vec3<f32>(fract(0.55 + new_h * 0.35 + mids * 0.2 + t * 0.1), 0.7, 1.0));

  var final_color = refracted + vec3<f32>(1.0) * spec + vec3<f32>(0.85, 0.95, 1.0) * fresnel_term * 0.4;
  final_color = mix(final_color, final_color * slick * 1.25, (0.16 + treble * 0.2) * clamp(fresnel_term + runners, 0.0, 1.0));
  final_color += slick * (runners * 0.22 * new_h + click * 0.35);
  final_color = aces_film(final_color);

  textureStore(writeTexture, coord, vec4<f32>(final_color, src_alpha));
  textureStore(dataTextureA, coord, vec4<f32>(new_h, new_v, normal.x, normal.y));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth_tex + new_h * 0.35, 0.0, 1.0), 0.0, 0.0, 0.0));
}
