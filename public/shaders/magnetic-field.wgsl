// ═══════════════════════════════════════════════════════════════════
//  Magnetic Field
//  Category: distortion
//  Features: animated, physics, mouse-driven, audio-reactive, curl-noise, field-lines, upgraded-rgba, temporal
//  Complexity: High
//  Upgraded: 2026-08-16 (Batch 52: Multi-pole magnetic field, Lorentz particle conveyor, exact C load)
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 60)
//
//  BUG FIXED IN THIS PASS — mask-as-colour feedback. dataTextureA stored the
//  FIELD STATE tuple `[b_field.x, b_field.y, line_sharp, b_mag]`, and because
//  dataTextureC is a copy of A, the "smooth temporal history" line
//
//      final_color = mix(final_color, prev_state.rgb, 0.1);
//
//  was blending the magnetic field VECTOR into the displayed colour: red got
//  b_field.x, green got b_field.y, blue got the field-line mask. Field
//  components are signed and unbounded, so this injected sign-flipping garbage
//  into every frame rather than smoothing anything. This is the same class of
//  defect the pool logged for spore-galaxy and neural-resonance.
//
//  The field is recomputed analytically from the dipoles every frame (nothing
//  reads the state back into the simulation), so A now carries DISPLAY RGBA —
//  making the temporal blend actually a temporal blend — and the field
//  diagnostics move to B.
//
//  TWO NEW STRUCTURES
//
//    1. Per-band FFT pole spectrum — the multipole mode's poles each take one of
//       the eight spectrum bins, setting that pole's moment strength, so the
//       field geometry itself reshapes with the music instead of the whole
//       field scaling by one global gain.
//
//    2. Cyclotron drift bands — charged-particle motion in a magnetic field
//       follows helical cyclotron orbits whose radius goes as 1/|B|. Luminous
//       tracer bands now advect ALONG the field lines at a rate set by the local
//       field magnitude, so filings visibly stream faster where the field is
//       strong and stall in the weak regions.
// ═══════════════════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=FieldStrength, y=Radius, z=FieldDensity, w=Mode
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

fn dipole_b(p: vec2<f32>, pole_pos: vec2<f32>, moment: vec2<f32>) -> vec2<f32> {
  let r_vec = p - pole_pos;
  let r2 = dot(r_vec, r_vec);
  let r = sqrt(max(r2, 0.0001));
  let r_hat = r_vec / r;
  let m_dot_r = dot(moment, r_hat);
  let b = (3.0 * m_dot_r * r_hat - moment) / max(r * r2, 0.005);
  return b;
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

  let strength = u.zoom_params.x * (1.2 + bass * 0.6);
  let radius = max(u.zoom_params.y * 0.6 + 0.1, 0.05);
  let density = max(u.zoom_params.z * 60.0 + 10.0, 5.0);
  let mode_val = u.zoom_params.w;

  let mouse_pos = u.zoom_config.yz;
  let is_down = u.zoom_config.w;

  let depth_tex = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth_factor = mix(0.4, 1.5, depth_tex);

  // Exact load of accumulated magnetic flux state from dataTextureC
  let prev_state = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);

  let p_corr = uv * aspect_vec;
  let mouse_corr = mouse_pos * aspect_vec;

  // Multi-pole configuration
  var b_field = vec2<f32>(0.0);
  let pole_dist = 0.12 * (1.0 + mids * 0.3);

  if (mode_val < 0.25) {
    // Mode 0: Monopole radial field
    let r_v = p_corr - mouse_corr;
    let r_len = length(r_v);
    b_field = select(vec2<f32>(0.0), r_v / max(r_len * r_len * r_len, 0.005), r_len > 0.001);
  } else if (mode_val < 0.5) {
    // Mode 1: Dipole (+ / - pair)
    let m1 = vec2<f32>(cos(t * 0.8), sin(t * 0.8));
    let pos_north = mouse_corr + vec2<f32>(-sin(t * 0.5), cos(t * 0.5)) * pole_dist;
    let pos_south = mouse_corr - vec2<f32>(-sin(t * 0.5), cos(t * 0.5)) * pole_dist;
    b_field = dipole_b(p_corr, pos_north, m1) - dipole_b(p_corr, pos_south, m1);
  } else if (mode_val < 0.75) {
    // Mode 2: Quadrupole (4 orbiting poles)
    for (var k = 0.0; k < 4.0; k += 1.0) {
      let angle = t * 0.6 + k * 1.5707963;
      let pos_k = mouse_corr + vec2<f32>(cos(angle), sin(angle)) * pole_dist * 1.2;
      let sign_k = select(-1.0, 1.0, k % 2.0 < 0.5);
      // Structure 1: pole k draws its moment strength from FFT bin k.
      let pole_band = plasmaBuffer[(u32(k) % 8u) + 1u].x;
      let m_k = vec2<f32>(-sin(angle), cos(angle)) * sign_k * (0.55 + pole_band * 1.6);
      b_field += dipole_b(p_corr, pos_k, m_k);
    }
  } else {
    // Mode 3: Solenoid helical vortex field
    let r_v = p_corr - mouse_corr;
    let r_len = length(r_v);
    let rot_v = vec2<f32>(-r_v.y, r_v.x) / max(r_len * r_len, 0.005);
    let rad_v = r_v / max(r_len * r_len, 0.005) * sin(r_len * density - t * 3.0);
    b_field = rot_v * 0.7 + rad_v * 0.3;
  }

  // Click pulse fronts (capped at 50)
  var click_flux = 0.0;
  let ripple_count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < ripple_count; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age >= 0.0 && age < 2.5) {
      let r_pos = r.xy * aspect_vec;
      let d_r = length(p_corr - r_pos);
      let front = abs(d_r - age * 0.5);
      let pulse = exp(-front * 35.0) * exp(-age * 1.3);
      click_flux += pulse * sin(d_r * 40.0 - age * 12.0) * 0.35;
    }
  }

  // B-field magnitude and field line potential function
  let b_mag = length(b_field);
  let b_dir = select(vec2<f32>(0.0), b_field / max(b_mag, 0.0001), b_mag > 0.0001);
  let dist_to_center = length(p_corr - mouse_corr);
  let field_envelope = smoothstep(radius, 0.0, dist_to_center) * (0.8 + 1.2 * is_down);

  // Field line caustic ridges: cos(density * magnetic_potential)
  let potential = atan2(b_dir.y, b_dir.x) + log(max(b_mag, 0.001)) * 0.35 - t * 0.4;
  let line_val = cos(potential * density) * 0.5 + 0.5;
  let line_sharp = pow(line_val, 8.0) * field_envelope;

  // Lorentz displacement of image pixels along field lines
  let lorentz_disp = b_dir * (strength * 0.06 * field_envelope * (1.0 + click_flux) / depth_factor);
  let uv_displaced = clamp(uv - lorentz_disp, vec2<f32>(0.001), vec2<f32>(0.999));

  // Chromatic dispersion along magnetic flux
  let disp_mag = length(lorentz_disp) * 0.35 * (1.0 + treble * 0.8);
  let r_samp = textureSampleLevel(readTexture, u_sampler, clamp(uv_displaced + b_dir * disp_mag, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let g_samp = textureSampleLevel(readTexture, u_sampler, uv_displaced, 0.0).g;
  let b_samp = textureSampleLevel(readTexture, u_sampler, clamp(uv_displaced - b_dir * disp_mag, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  let src_alpha = textureSampleLevel(readTexture, u_sampler, uv_displaced, 0.0).a;
  let base_color = vec3<f32>(r_samp, g_samp, b_samp);

  // Luminous iron-filing field line illumination
  let aurora_phase = potential * 3.0 + t * 1.5;
  let aurora_tint = 0.5 + 0.5 * cos(vec3<f32>(0.0, 1.6, 3.2) + aurora_phase);
  var final_color = mix(base_color, aurora_tint * 1.4, line_sharp * 0.65);

  // ── Structure 2: cyclotron drift bands ───────────────────────────────────
  // Cyclotron radius goes as 1/|B|, so tracers stream fast where the field is
  // strong and stall where it is weak. The band phase advects along b_dir.
  let cyclotron_rate = clamp(b_mag * 6.0, 0.05, 12.0);
  let along = dot(p_corr, b_dir);
  let drift = sin(along * (14.0 + density * 6.0) - t * cyclotron_rate * (1.0 + mids * 0.6));
  let tracer = pow(max(drift, 0.0), 6.0) * field_envelope * (0.35 + treble * 0.9);
  final_color += aurora_tint * tracer * 0.55;
  final_color += vec3<f32>(0.85, 0.92, 1.0) * abs(click_flux) * 0.4;

  // Temporal history — now a real colour history (see header: this used to
  // blend the raw B-field vector into RGB).
  final_color = mix(final_color, prev_state.rgb, 0.1);

  final_color = aces_film(final_color);

  // Semantic alpha: field lines and tracers are the content.
  let substance = clamp(line_sharp * 0.8 + tracer * 0.7 + abs(click_flux) * 0.5, 0.0, 1.0);
  let out_alpha = clamp(mix(src_alpha, 1.0, substance), 0.0, 1.0);
  let out_rgba = vec4<f32>(final_color, out_alpha);
  let out_depth = clamp(depth_tex + line_sharp * 0.25, 0.0, 1.0);

  textureStore(writeTexture, coord, out_rgba);
  // A carries DISPLAY RGBA so the history blend above is meaningful; the field
  // state tuple that used to live here moves to B.
  textureStore(dataTextureA, coord, out_rgba);
  textureStore(dataTextureB, coord, vec4<f32>(b_field.x, b_field.y, line_sharp, b_mag));
  textureStore(writeDepthTexture, coord, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
}
