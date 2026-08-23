// ═══════════════════════════════════════════════════════════════════
//  Digital Mold
//  Category: interactive-mouse
//  Features: animated, reaction-diffusion, spore-noise, depth-humidity, upgraded-rgba, temporal
//  Complexity: High
//  Upgraded: 2026-08-23 (Batch 64)
//
//  This shader was already at the pool standard (real Gray-Scott, exact
//  dataTextureC loads, guarded ripple loop, ACES, chemical state in A). This
//  pass adds two structures and fixes two smaller issues: the spore noise used
//  `hash22(uv * 80.0 + fract(t))`, reseeded every frame so it strobed rather
//  than reading as settled spores; and the output alpha was the SOURCE image's
//  alpha passed straight through, which says nothing about where the mold
//  actually is — it is now derived from colony density.
//
//  TWO NEW STRUCTURES
//
//    1. Nutrient-gradient chemotaxis — real mycelium forages: hyphae extend
//       preferentially up the nutrient gradient rather than diffusing
//       isotropically. Image luminance is the nutrient field, and the
//       diffusion of the autocatalyst is now biased along its gradient, so
//       colonies visibly crawl toward bright regions and starve in dark ones.
//
//    2. Per-band sporulation regimes — the Gray-Scott parameter plane has
//       distinct morphologies (spots, stripes, mitosis, chaos) at different
//       feed/kill values. Each of the eight FFT bins now owns a spatial zone
//       and pushes its feed/kill into a different regime, so the colony grows
//       visibly different structures in response to different frequencies.
// ═══════════════════════════════════════════════════════════════════════════════ (Batch 52: Gray-Scott reaction-diffusion, hyphal growth, exact C load)
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
  zoom_params: vec4<f32>,  // x=FeedRate, y=KillRate, z=DiffusionA, w=DiffusionB
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
  return fract((p3.xx + p3.yz) * p3.zy);
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

  let feed_rate = mix(0.018, 0.082, u.zoom_params.x) * (1.0 + bass * 0.25);
  let kill_rate = mix(0.045, 0.072, u.zoom_params.y);
  let diff_a = mix(0.6, 1.4, u.zoom_params.z);
  let diff_b = mix(0.3, 0.7, u.zoom_params.w);

  let mouse_pos = u.zoom_config.yz;
  let is_down = u.zoom_config.w;

  let depth_tex = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let humidity = mix(0.6, 1.4, depth_tex);

  // Exact load of previous (u, v, filament, age) chemical state from dataTextureC
  let prev_raw = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);
  var u_chem = select(1.0, prev_raw.r, prev_raw.r > 0.0001 || prev_raw.g > 0.0001);
  var v_chem = prev_raw.g;

  // 4-neighbor Laplace stencil on chemical concentrations
  let c_r = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rg;
  let c_l = textureLoad(dataTextureC, clamp(coord - vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rg;
  let c_u = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rg;
  let c_d = textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rg;

  let lap_u = (c_r.r + c_l.r + c_u.r + c_d.r - 4.0 * u_chem) * 0.25;
  let lap_v = (c_r.g + c_l.g + c_u.g + c_d.g - 4.0 * v_chem) * 0.25;

  // ── Structure 1: nutrient-gradient chemotaxis ─────────────────────────────
  // Image luminance is the nutrient field. Hyphae extend UP that gradient
  // instead of diffusing isotropically, which is how mycelium actually forages.
  let px = 1.0 / vec2<f32>(res);
  let nutC = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let nutR = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let nutL = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(px.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let nutU = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let nutD = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, px.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
  let nutrientGrad = vec2<f32>(nutR - nutL, nutU - nutD);
  // Directional derivative of v along the nutrient gradient: the advective
  // chemotaxis term.
  let vGrad = vec2<f32>(c_r.g - c_l.g, c_u.g - c_d.g) * 0.5;
  let chemotaxis = dot(vGrad, nutrientGrad) * 6.0 * (0.4 + nutC);

  // ── Structure 2: per-band sporulation regimes ─────────────────────────────
  // Each FFT bin owns a zone and pushes feed/kill into a different region of
  // the Gray-Scott parameter plane (spots / stripes / mitosis).
  let zoneIdx = u32(clamp((uv.x * 0.5 + uv.y * 0.5) * 8.0, 0.0, 7.999));
  let zoneE = plasmaBuffer[zoneIdx + 1u].x;
  let feed_zone = feed_rate + zoneE * 0.014;
  let kill_zone = kill_rate + zoneE * 0.006 - f32(zoneIdx) * 0.0009;

  // Gray-Scott Reaction-Diffusion kinetics
  let uv2 = u_chem * v_chem * v_chem;
  let du = diff_a * lap_u - uv2 + feed_zone * (1.0 - u_chem);
  let dv = diff_b * lap_v + uv2 - (feed_zone + kill_zone) * v_chem + chemotaxis * 0.02;

  let dt = 0.95 * humidity;
  u_chem = clamp(u_chem + du * dt, 0.0, 1.0);
  v_chem = clamp(v_chem + dv * dt, 0.0, 1.0);

  // Spore inoculation from pointer
  let d_mouse = (uv - mouse_pos) * aspect_vec;
  let dist_m = length(d_mouse);
  let spore_brush = smoothstep(0.06 + 0.08 * is_down, 0.0, dist_m);
  // Spatially coherent and slowly drifting; the previous
  // `hash22(uv * 80.0 + fract(t))` reseeded every frame and strobed.
  let sporeCell = floor(uv * 80.0 + vec2<f32>(t * 0.07, t * 0.05));
  let noise_spores = hash22(sporeCell).x;
  if (spore_brush > 0.05 && noise_spores > 0.6) {
    v_chem = max(v_chem, spore_brush * (0.6 + 0.4 * is_down));
    u_chem = min(u_chem, 1.0 - spore_brush * 0.5);
  }

  // Click spore bursts (capped at 50)
  let ripple_count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < ripple_count; i = i + 1u) {
    let r = u.ripples[i];
    let age = t - r.z;
    if (age >= 0.0 && age < 2.0) {
      let r_pos = (uv - r.xy) * aspect_vec;
      let d_r = length(r_pos);
      let front = abs(d_r - age * 0.35);
      if (front < 0.03) {
        v_chem = max(v_chem, (1.0 - front / 0.03) * exp(-age * 2.0) * 0.8);
      }
    }
  }

  // Hyphal branching filament structure
  let hyphae = sin(v_chem * 28.0 + t * 0.8) * cos(u_chem * 24.0);
  let mold_density = smoothstep(0.12, 0.65, v_chem);

  // Read base image sample
  let image_sample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let src_alpha = image_sample.a;

  // Bioluminescent mold color palette
  let biolum_tint = 0.5 + 0.5 * cos(vec3<f32>(1.2, 0.2, 2.8) + v_chem * 8.0 + t * 0.6);
  let moss_color = mix(vec3<f32>(0.05, 0.18, 0.08), vec3<f32>(0.2, 0.65, 0.35), hyphae * 0.5 + 0.5);
  let mold_final_glow = mix(moss_color, biolum_tint * 1.5, clamp(v_chem * (1.0 + treble), 0.0, 1.0));

  var final_color = mix(image_sample.rgb, mold_final_glow, mold_density * 0.85);
  final_color = aces_film(final_color);

  // Semantic alpha: the colony is the content, the plate behind it is not.
  let colony = clamp(mold_density * 0.85 + v_chem * 0.4, 0.0, 1.0);
  let out_alpha = clamp(mix(src_alpha * 0.6 + 0.15, 1.0, colony), 0.0, 1.0);
  let out_rgba = vec4<f32>(final_color, out_alpha);
  let out_state = vec4<f32>(u_chem, v_chem, hyphae, mold_density);
  let out_depth = clamp(depth_tex + mold_density * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, out_rgba);
  textureStore(dataTextureA, coord, out_state);
  textureStore(writeDepthTexture, coord, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
}
