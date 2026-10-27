// ═══════════════════════════════════════════════════════════════════
//  Motion Revealer
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, optical-flow, motion-trails, depth-aware, upgraded-rgba, temporal
//  Complexity: High
//  Upgraded: 2026-08-16, 2026-10-27
//  Ideas: coherence-gated streak (§12.2A); motion hold from C.a
//  A packing: (live RGB, low-passed motion) — C.rgb is previous colour, C.a is previous motion
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Sensitivity, y=TrailLen, z=GlowStr, w=ChromaSep

fn aces_film(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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

  let sensitivity = max(u.zoom_params.x * (1.5 + bass * 0.8), 0.05);
  let trail_len = u.zoom_params.y * (1.0 + mids * 0.4);
  let glow_str = u.zoom_params.z * (1.5 + treble * 0.8);
  let chroma_sep = u.zoom_params.w * 0.05;

  let mouse_pos = u.zoom_config.yz;
  let is_down = u.zoom_config.w;

  let depth_tex = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth_factor = mix(0.4, 1.4, depth_tex);

  // Exact load of previous frame RGB from dataTextureC (hardware-safe)
  let prev_raw = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);
  let prev_color = prev_raw.rgb;

  let live_sample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let live_color = live_sample.rgb;
  let src_alpha = live_sample.a;

  // Discrete spatial derivatives (4-tap Sobel/central differences)
  let eps = 1.0 / res.y;
  let s_r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(eps, 0.0), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
  let s_l = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(eps, 0.0), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
  let s_u = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, eps), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
  let s_d = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, eps), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;

  let gx = (s_r - s_l) * 0.5;
  let gy = (s_u - s_d) * 0.5;

  // Structure tensor components: J = [[E, F], [F, G]]
  let E = dot(gx, gx);
  let G = dot(gy, gy);
  let F = dot(gx, gy);
  let lambda_diff = sqrt((E - G) * (E - G) + 4.0 * F * F);
  let theta = atan2(2.0 * F, E - G + lambda_diff) * 0.5;
  let flow_dir = vec2<f32>(cos(theta), sin(theta));
  // ── Idea: coherence gate (§12.2A) — isotropic patches do not invent a streak direction.
  let coherence = lambda_diff / max(E + G, 1e-4);
  let flow_use = flow_dir * smoothstep(0.18, 0.55, coherence);

  // Temporal frame difference motion magnitude
  let diff_mag = length(live_color - prev_color);
  let motion_raw = diff_mag * sensitivity;

  // Pointer drag motion influence
  let d_mouse = (uv - mouse_pos) * aspect_vec;
  let dist_mouse = length(d_mouse);
  let mouse_mask = smoothstep(0.4, 0.0, dist_mouse) * (0.6 + 1.2 * is_down);

  // Click shock fronts (capped at 50)
  var click_motion = 0.0;
  let ripple_count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < ripple_count; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age >= 0.0 && age < 2.5) {
      let r_pos = (uv - r.xy) * aspect_vec;
      let d_r = length(r_pos);
      let front = abs(d_r - age * 0.5);
      let pulse = exp(-front * 30.0) * exp(-age * 1.4);
      click_motion += pulse * 0.6;
    }
  }

  let total_motion = clamp(motion_raw + mouse_mask * 0.3 + click_motion, 0.0, 3.0);
  // ── Idea: motion hold — C.a low-passes the difference so a patch stays open after it stops.
  let prev_motion = select(0.0, prev_raw.a, prev_raw.a <= 3.0);
  let motion_lp = mix(prev_motion, total_motion, 0.38);
  let reveal_mask = smoothstep(0.04, 0.35, motion_lp);

  // Spectral streaklines integration along optical flow
  var trail_r = 0.0;
  var trail_g = 0.0;
  var trail_b = 0.0;
  let steps = 6;
  let max_offset = flow_use * (trail_len * 0.06 * depth_factor);

  for (var k = 0; k < steps; k += 1) {
    let weight = f32(steps - k) / f32(steps);
    let sample_uv = uv + max_offset * (f32(k) / f32(steps));
    let uvr = clamp(sample_uv + flow_use * chroma_sep * weight, vec2<f32>(0.001), vec2<f32>(0.999));
    let uvg = clamp(sample_uv, vec2<f32>(0.001), vec2<f32>(0.999));
    let uvb = clamp(sample_uv - flow_use * chroma_sep * weight, vec2<f32>(0.001), vec2<f32>(0.999));

    trail_r += textureSampleLevel(readTexture, u_sampler, uvr, 0.0).r * weight;
    trail_g += textureSampleLevel(readTexture, u_sampler, uvg, 0.0).g * weight;
    trail_b += textureSampleLevel(readTexture, u_sampler, uvb, 0.0).b * weight;
  }
  let total_weight = f32(steps * (steps + 1)) / (2.0 * f32(steps));
  let trail_color = vec3<f32>(trail_r, trail_g, trail_b) / max(total_weight, 1.0);

  // Bioluminescent motion glow
  let glow_tint = 0.5 + 0.5 * cos(vec3<f32>(0.0, 1.8, 3.6) + total_motion * 6.0 + t * 1.2);
  let glow = glow_tint * (total_motion * glow_str * 1.4);

  // Composite: reveal live/trails on moving regions, subtle ghosting on static
  var final_color = mix(live_color * 0.15, trail_color + glow, reveal_mask);
  final_color = aces_film(final_color);

  let out_alpha = clamp(src_alpha * 0.25 + reveal_mask * 0.62 + coherence * 0.13, 0.0, 1.0);
  let out_rgba = vec4<f32>(final_color, out_alpha);
  let out_depth = clamp(depth_tex + reveal_mask * 0.25, 0.0, 1.0);

  textureStore(writeTexture, coord, out_rgba);
  textureStore(dataTextureA, coord, vec4<f32>(live_color, motion_lp));
  textureStore(writeDepthTexture, coord, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
}
