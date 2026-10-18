// ----------------------------------------------------------------
// Psychedelic Layered Time-Stamps
// Category: generative
// Features: temporal-layering, OkLab-color-mixing, blackbody-palette,
//           chromatic-offset, bass-distortion, feedback-accumulation,
//           upgraded-rgba, Fresnel-rim-glow, audio-reactive, mouse-driven
// Upgraded: 2026-09-27
// Ideas: lagged echo taps (each layer re-samples the video at time - i*lag); postmark rings (dashed, aged, pointer-anchored, distortion-warped); delay wavefront (radial offset on the delay clock)
// A packing: raw pre-ACES accumulated feedback RGB in A.rgb, wrapping delay clock in A.a (C read the same way; ACES only on writeTexture)
// ----------------------------------------------------------------

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
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


const PI:  f32 = 3.14159265358979323846;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── OkLab: perceptual color mixing ───
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

fn linear_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        0.8189330101, 0.3618667424, -0.1288597137,
        0.0329845436, 0.9293118715,  0.0361456387,
        0.0482003018, 0.2643662691,  0.6338517070
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0 / 3.0));
    return mat3x3<f32>(
        0.2104542553,  0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050,  0.4505937099,
        0.0259040371,  0.7827717662, -0.8086757660
    ) * lms_;
}

fn oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        0.2104542553,  0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050,  0.4505937099,
        0.0259040371,  0.7827717662, -0.8086757660
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        1.2270138511, -0.5577992887,  0.2812561490,
       -0.0405801784,  1.1122568696, -0.0716766787,
       -0.0763812845, -0.4214819784,  1.5861632204
    ) * lms;
}

fn oklab_mix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    let a_ok = linear_to_oklab(srgb_to_linear(a));
    let b_ok = linear_to_oklab(srgb_to_linear(b));
    let mixed = mix(a_ok, b_ok, t);
    return linear_to_srgb(oklab_to_linear(mixed));
}

// ─── Blackbody palette: approximate temperature color ───
fn blackbody(t: f32) -> vec3<f32> {
    let temp = clamp(t, 0.0, 1.0);
    let r = 1.0;
    let g = mix(0.3, 1.0, smoothstep(0.0, 0.5, temp));
    let b = mix(0.0, 0.8, smoothstep(0.3, 1.0, temp));
    return vec3<f32>(r, g, b) * (0.5 + temp * 0.5);
}

// ─── Fresnel rim lighting helper ───
fn fresnel_rim(normal: vec3<f32>, viewDir: vec3<f32>, power: f32) -> f32 {
    return pow(1.0 - max(dot(normal, viewDir), 0.0), power);
}

// ─── Idea 1: lagged echo tap — one layer's distorted, chroma-split video sample ───
fn echo_tap(uv: vec2<f32>, wob: vec2<f32>, shift_r: f32, shift_b: f32, resolution: vec2<f32>) -> vec3<f32> {
    let hi = vec2<i32>(resolution) - vec2<i32>(1);
    let r_uv = clamp(uv + wob + vec2<f32>(shift_r, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let g_uv = clamp(uv + wob, vec2<f32>(0.0), vec2<f32>(1.0));
    let b_uv = clamp(uv + wob - vec2<f32>(shift_b, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureLoad(readTexture, clamp(vec2<i32>(r_uv * resolution), vec2<i32>(0), hi), 0).r;
    let g = textureLoad(readTexture, clamp(vec2<i32>(g_uv * resolution), vec2<i32>(0), hi), 0).g;
    let b = textureLoad(readTexture, clamp(vec2<i32>(b_uv * resolution), vec2<i32>(0), hi), 0).b;
    return vec3<f32>(r, g, b);
}

// ─── Per-layer ink hue on the layer's age phase (replaces dead plasmaBuffer[1..255] colour read) ───
fn stamp_ink(phase: f32) -> vec3<f32> {
    let h = phase * 2.0 * PI;
    let lab = vec3<f32>(0.72, 0.10 * cos(h), 0.10 * sin(h));
    return linear_to_srgb(oklab_to_linear(lab));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let mouse = u.zoom_config.yz;

  let layer_count = i32(u.zoom_params.x * 10.0 + 3.0);
  let delay_scale = u.zoom_params.y;
  let distortion_amp = u.zoom_params.z;
  let chromatic_shift = u.zoom_params.w * 0.01;

  var final_color = vec3<f32>(0.0);

  // Chromatic distortion: R/B channels offset differently
  let r_dist_offset = vec2<f32>(
    sin(uv.y * 10.0 + time) * distortion_amp * (1.0 + bass * 2.0) + chromatic_shift * (1.0 + bass),
    cos(uv.x * 10.0 + time) * distortion_amp * (1.0 + bass * 2.0)
  );
  let b_dist_offset = vec2<f32>(
    sin(uv.y * 10.0 + time) * distortion_amp * (1.0 + bass * 2.0) - chromatic_shift * (1.0 + treble),
    cos(uv.x * 10.0 + time) * distortion_amp * (1.0 + bass * 2.0)
  );

  let asp = vec2<f32>(resolution.x / resolution.y, 1.0);
  let anchor = mouse;
  let hue_gain = 1.0 + bass * 2.0;
  let amp = distortion_amp * hue_gain;
  // Idea 1: seconds of distortion-phase lag per layer (delay slider); layer 0 has zero lag = HEAD's base sample
  let lag_dt = 0.12 + delay_scale * 0.5;

  // Idea 3: delay clock lives in C.a; radial phase makes the wrap edge sweep outward from the anchor
  let delay_info = textureLoad(dataTextureC, coord, 0);
  let clock = delay_info.a;
  let wave = 0.35 * length((uv - anchor) * asp);
  let delay_here = fract(clock - wave + 1.0);
  let current_delay = delay_here + (bass * 0.1);

  var ring_acc = vec3<f32>(0.0);

  for(var i = 0; i < 10; i = i + 1) {
    if (i >= layer_count) { break; }
    let layer_factor = f32(i) / f32(layer_count);

    let color_shift_raw = time * 0.1 + layer_factor;
    let color_shift = color_shift_raw - floor(color_shift_raw);
    let ink_color = stamp_ink(color_shift);

    // OkLab mix with blackbody temperature
    let temp = layer_factor + bass * 0.3;
    let bb = blackbody(temp);
    let mixed = oklab_mix(ink_color, bb, 0.5 + bass * 0.2);

    let layer_weight = exp(-current_delay * delay_scale * f32(i));

    // Idea 1: lagged echo tap — this layer sees the distortion field as it was i*lag ago
    let t_i = time - lag_dt * f32(i);
    let wob = vec2<f32>(sin(uv.y * 10.0 + t_i) * amp, cos(uv.x * 10.0 + t_i) * amp);
    let echo = echo_tap(uv, wob, chromatic_shift * (1.0 + bass), chromatic_shift * (1.0 + treble), resolution);
    final_color += echo * mixed * layer_weight;

    // Idea 2: postmark ring — radius = layer age, born/dies invisibly, dashed, warped by the distortion
    let ring_env = sin(PI * color_shift);
    let rp = (uv + wob - anchor) * asp;
    let ring_d = abs(length(rp) - (0.06 + color_shift * 0.6));
    let ang = atan2(rp.y, rp.x);
    let dash_f = fract(ang * (16.0 / (2.0 * PI)) + f32(i) * 0.37 + time * 0.05);
    let dash = 0.35 + 0.65 * smoothstep(0.3, 0.6, abs(dash_f - 0.5) * 2.0);
    ring_acc += mixed * (1.0 - smoothstep(0.0, 0.007, ring_d)) * ring_env * dash * layer_weight;
  }

  final_color = final_color / f32(layer_count);
  final_color += ring_acc * 0.45;

  let mouse_dist = distance(uv, mouse);
  let isMouseActive = mouse_dist < 0.1 && u.zoom_config.w > 0.5;
  final_color += vec3<f32>(1.0 - mouse_dist * 10.0) * bass * select(0.0, 1.0, isMouseActive);

  // Fresnel rim glow on distortion edges
  let edgeNormal = normalize(vec3<f32>(r_dist_offset.x, b_dist_offset.y, 0.02));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let rim = fresnel_rim(edgeNormal, viewDir, 2.0 + bass * 3.0);
  let rimCol = blackbody(0.6 + bass * 0.4) * rim * 0.3;
  final_color += rimCol;

  // Feedback accumulation with chromatic boost
  let prev_frame = delay_info.rgb;
  let fbMix = 0.1 + mids * 0.15;
  final_color = mix(final_color, prev_frame * vec3<f32>(1.0 + bass * 0.1, 1.0, 1.0 + treble * 0.1), fbMix);

  let new_clock = fract(clock + 0.01);
  textureStore(dataTextureA, coord, vec4<f32>(clamp(final_color, vec3<f32>(0.0), vec3<f32>(8.0)), new_clock));

  let luma = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.6 + current_delay * 0.2 + 0.15 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture, coord, applyGenerativePrimaryControls(vec4<f32>(final_color, alpha)));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
