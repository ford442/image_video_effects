// ═══════════════════════════════════════════════════════════════════
//  Swirling Void
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal, relativistic
//  Complexity: High
//  Upgraded: 2026-08-16 (Batch 52: Kerr metric frame dragging, Doppler beaming, exact C load, 16x16x1)
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
  zoom_params: vec4<f32>,  // x=VortexStrength, y=EventHorizon, z=VoidDarkness, w=AudioReactivity
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

fn blackbody_rgb(temp_kelvin: f32) -> vec3<f32> {
  let t = clamp(temp_kelvin, 1000.0, 35000.0) / 100.0;
  let r = select(clamp(329.698727446 * pow(max(t - 60.0, 0.001), -0.1332047592) / 255.0, 0.0, 1.0), 1.0, t <= 66.0);
  let g_low = clamp((99.4708025861 * log(max(t, 1.0)) - 161.1195681661) / 255.0, 0.0, 1.0);
  let g_high = clamp(288.1221695283 * pow(max(t - 60.0, 0.001), -0.0755148492) / 255.0, 0.0, 1.0);
  let g = select(g_high, g_low, t <= 66.0);
  let b_mid = clamp((138.5177312231 * log(max(t - 10.0, 1.0)) - 305.0447927307) / 255.0, 0.0, 1.0);
  let b_low = select(b_mid, 0.0, t <= 19.0);
  let b = select(1.0, b_low, t < 66.0);
  return vec3<f32>(r, g, b);
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

  let strength = u.zoom_params.x * 6.0;
  let horizon_r = max(u.zoom_params.y * 0.35 + 0.04, 0.01);
  let darkness = u.zoom_params.z;
  let audio_react = u.zoom_params.w;

  let mouse_pos = u.zoom_config.yz;
  let is_down = u.zoom_config.w;

  let depth_tex = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth_drag = mix(0.7, 1.4, depth_tex);

  // Exact load of previous photon accumulation from dataTextureC
  let prev_state = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);

  let p_corr = uv * aspect_vec;
  let mouse_corr = mouse_pos * aspect_vec;
  let rel_pos = p_corr - mouse_corr;
  let dist = length(rel_pos);
  let angle = atan2(rel_pos.y, rel_pos.x);

  // Kerr metric relativistic frame-dragging angular velocity
  let effective_strength = strength * (1.0 + bass * audio_react * 0.8 + 0.4 * is_down);
  let r_norm = dist / max(horizon_r, 0.001);
  let omega_kerr = effective_strength / (r_norm * r_norm * r_norm + 0.25) * depth_drag;
  let frame_drag_twist = omega_kerr * 0.25 + t * 0.4;

  // Photon sphere deflection
  let photon_sphere = horizon_r * 1.5;
  let photon_ring_width = horizon_r * 0.12;
  let photon_ring_dist = abs(dist - photon_sphere);
  let photon_ring = exp(-photon_ring_dist * photon_ring_dist / (photon_ring_width * photon_ring_width * 2.0));

  // Event horizon shadow mask
  let horizon_mask = smoothstep(horizon_r * 0.85, horizon_r * 1.15, dist);

  // Relativistic Doppler beaming on accretion flow
  let orbit_angle = angle + frame_drag_twist;
  let doppler_factor = 1.0 + 0.65 * sin(orbit_angle) * smoothstep(horizon_r * 3.5, horizon_r, dist);

  // Click gravitational wave ripples (capped at 50)
  var gw_pulse = 0.0;
  let ripple_count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < ripple_count; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age >= 0.0 && age < 3.0) {
      let r_pos = (uv - r.xy) * aspect_vec;
      let d_r = length(r_pos);
      let front = abs(d_r - age * 0.55);
      let pulse = exp(-front * 35.0) * exp(-age * 1.2);
      gw_pulse += pulse * sin(d_r * 40.0 - age * 12.0) * 0.35;
    }
  }

  // Warped sampling coordinates
  let warped_angle = angle + frame_drag_twist + gw_pulse;
  let warped_rel = vec2<f32>(cos(warped_angle), sin(warped_angle)) * dist;
  let warped_p = mouse_corr + warped_rel;
  let warped_uv = clamp(warped_p / aspect_vec, vec2<f32>(0.001), vec2<f32>(0.999));

  // Chromatic gravitational shear
  let chroma_offset = (vec2<f32>(-sin(warped_angle), cos(warped_angle)) * 0.015 * (1.0 + treble * 0.5)) / max(r_norm, 0.5);
  let s_r = textureSampleLevel(readTexture, u_sampler, clamp(warped_uv + chroma_offset, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let s_g = textureSampleLevel(readTexture, u_sampler, warped_uv, 0.0).g;
  let s_b = textureSampleLevel(readTexture, u_sampler, clamp(warped_uv - chroma_offset, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  let src_alpha = textureSampleLevel(readTexture, u_sampler, warped_uv, 0.0).a;
  let warped_color = vec3<f32>(s_r, s_g, s_b);

  // Blackbody accretion disk temperature gradient: T ~ r^(-3/4)
  let t_kelvin = mix(2500.0, 18000.0, clamp(pow(horizon_r / max(dist, horizon_r * 0.5), 0.75), 0.0, 1.0)) * (1.0 + mids * 0.3);
  let thermal_color = blackbody_rgb(t_kelvin) * doppler_factor;

  // Accretion disk emission profile
  let disk_intensity = exp(-dist * 4.5 / horizon_r) * (0.8 + 0.6 * is_down) * (1.0 + bass * 0.4);
  let photon_ring_emission = vec3<f32>(1.2, 1.35, 1.6) * photon_ring * (1.5 + treble * 0.8);

  var final_color = warped_color * horizon_mask;
  final_color = mix(final_color, thermal_color, clamp(disk_intensity, 0.0, 0.85));
  final_color += photon_ring_emission;
  final_color = mix(final_color, vec3<f32>(0.0), (1.0 - horizon_mask) * darkness);
  final_color = mix(final_color, prev_state.rgb, 0.12); // smooth temporal history

  final_color = aces_film(final_color);

  let out_rgba = vec4<f32>(final_color, src_alpha);
  let out_state = vec4<f32>(warped_rel.x, warped_rel.y, photon_ring, disk_intensity);
  let out_depth = clamp(depth_tex * horizon_mask, 0.0, 1.0);

  textureStore(writeTexture, coord, out_rgba);
  textureStore(dataTextureA, coord, out_state);
  textureStore(writeDepthTexture, coord, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
}
