// ═══════════════════════════════════════════════════════════════════
//  Elastic Chromatic Explosion
//  Category: advanced-hybrid
//  Features: chromatic-lag, prism-explosion, mouse-driven, temporal, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-23 (Batch 68: sprung prism focus, bounded shocks, semantic alpha)
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
  zoom_params: vec4<f32>,  // x=BaseLagR, y=BaseLagB, z=PrismStrength, w=SaturationBoost
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn prism_displace(uv: vec2<f32>, mouse_pos: vec2<f32>, wavelength_offset: f32, strength: f32, aspect_vec: vec2<f32>) -> vec2<f32> {
  let to_mouse = (uv - mouse_pos) * aspect_vec;
  let dist = length(to_mouse);
  let prism_angle = atan2(to_mouse.y, to_mouse.x);
  let deflection = wavelength_offset * strength / max(dist, 0.02);
  let perp = vec2<f32>(-sin(prism_angle), cos(prism_angle)) / aspect_vec;
  return uv + perp * deflection;
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

  let base_lag_r = clamp(u.zoom_params.x * 0.95, 0.0, 0.98);
  let base_lag_b = clamp(u.zoom_params.y * 0.95, 0.0, 0.98);
  let prism_str = mix(0.02, 0.16, u.zoom_params.z) * (1.0 + bass * 0.5);
  let sat_boost = u.zoom_params.w * (1.5 + treble * 0.8);

  let raw_mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let is_down = u.zoom_config.w;

  // Guarded critically damped prism focus. Only invocation (0,0) persists it.
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var mouse_pos = raw_mouse;
  var spring_vel = vec2<f32>(0.0);
  var last_time = t;
  var initialized = false;
  if (hasSpring) {
    mouse_pos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    spring_vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    last_time = extraBuffer[137];
    initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { mouse_pos = raw_mouse; spring_vel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(t - last_time, 0.0, 0.05), initialized);
  let omega = 10.0;
  let spring_decay = exp(-omega * dt);
  let spring_delta = mouse_pos - raw_mouse;
  let spring_temp = (spring_vel + omega * spring_delta) * dt;
  spring_vel = (spring_vel - omega * spring_temp) * spring_decay;
  mouse_pos = raw_mouse + (spring_delta + spring_temp) * spring_decay;
  if (hasSpring && global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = mouse_pos.x; extraBuffer[134] = mouse_pos.y;
    extraBuffer[135] = spring_vel.x; extraBuffer[136] = spring_vel.y;
    extraBuffer[137] = t; extraBuffer[138] = 1.0;
  }

  let depth_tex = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth_factor = mix(0.5, 1.5, depth_tex);

  // Exact load of previous chromatic history from dataTextureC
  let prev_state = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);

  // Pointer distance influence
  let d_mouse = (uv - mouse_pos) * aspect_vec;
  let dist_mouse = length(d_mouse);
  let mouse_pull = smoothstep(0.45, 0.0, dist_mouse) * (0.5 + 1.2 * is_down);

  let effective_lag_r = clamp(base_lag_r + mouse_pull * 0.25, 0.0, 0.98);
  let effective_lag_b = clamp(base_lag_b + mouse_pull * 0.35, 0.0, 0.98);

  // Click chromatic shockwaves (capped at 50)
  var r_shock = vec2<f32>(0.0);
  var g_shock = vec2<f32>(0.0);
  var b_shock = vec2<f32>(0.0);
  let ripple_count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < ripple_count; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age >= 0.0 && age < 2.8) {
      let r_pos = (uv - r.xy) * aspect_vec;
      let d_r = length(r_pos);
      let front = abs(d_r - age * 0.6);
      let pulse = exp(-front * 34.0) * exp(-age * 1.05) * (1.0 + bass * 0.35);
      let dir = select(vec2<f32>(0.0), (uv - r.xy) / max(d_r, 0.001), d_r > 0.001);
      r_shock += dir * pulse * 0.045 * sin(d_r * 36.0 - age * 12.0 - 0.4);
      g_shock += dir * pulse * 0.045 * sin(d_r * 36.0 - age * 12.0);
      b_shock += dir * pulse * 0.045 * sin(d_r * 36.0 - age * 12.0 + 0.4);
    }
  }

  // Prismatic dispersion coordinates
  let uv_r = clamp(prism_displace(uv, mouse_pos, -1.2, prism_str, aspect_vec) + r_shock, vec2<f32>(0.001), vec2<f32>(0.999));
  let uv_g = clamp(prism_displace(uv, mouse_pos, 0.0, prism_str, aspect_vec) + g_shock, vec2<f32>(0.001), vec2<f32>(0.999));
  let uv_b = clamp(prism_displace(uv, mouse_pos, 1.2, prism_str, aspect_vec) + b_shock, vec2<f32>(0.001), vec2<f32>(0.999));

  let live_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
  let live_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
  let live_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;
  let src_alpha = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).a;

  // EMA temporal lag integration per channel
  let out_r = mix(live_r, prev_state.r, effective_lag_r);
  let out_g = mix(live_g, prev_state.g, 0.35);
  let out_b = mix(live_b, prev_state.b, effective_lag_b);
  var col = vec3<f32>(out_r, out_g, out_b);

  // Saturation & chromatic explosion boost
  let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
  col = mix(vec3<f32>(luma), col, 1.0 + sat_boost * 1.5);

  // Prismatic caustic highlight
  let caustic = max(0.0, length(vec3<f32>(out_r - live_g, 0.0, out_b - live_g))) * 2.5;
  col += vec3<f32>(1.0, 0.85, 0.95) * caustic * (0.3 + 0.7 * is_down) * (1.0 + mids * 0.4);

  col = acesToneMap(max(col, vec3<f32>(0.0)));

  let effect_energy = clamp(caustic * 1.5 + length(r_shock + g_shock + b_shock) * 4.0 + mouse_pull * is_down * 0.4, 0.0, 1.0);
  let out_alpha = clamp(src_alpha + (1.0 - src_alpha) * effect_energy, 0.0, 1.0);
  let out_rgba = vec4<f32>(col, out_alpha);

  textureStore(writeTexture, coord, out_rgba);
  textureStore(dataTextureA, coord, out_rgba);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth_tex, 0.0, 0.0, 0.0));
}
