// ----------------------------------------------------------------
// Psychedelic Layered Time-Stamps
// Category: generative
// Features: temporal-layering, OkLab-color-mixing, blackbody-palette,
//           chromatic-offset, bass-distortion, feedback-accumulation,
//           upgraded-rgba, Fresnel-rim-glow, audio-reactive, mouse-driven
// Upgraded: 2026-09-27, 2026-11-08
// Ideas: lagged echo taps (each layer re-samples the video at time - i*lag); postmark rings (dashed, aged, pointer-anchored, distortion-warped); delay wavefront (radial offset on the delay clock); per-channel time lag (chroma delay line, §12.2B); double-circle datestamp postmark with ink dropout
// Rescues 2026-11-08 (not ideas): OkLab pair rebuilt (was a constant-green tint) + ink chroma/hue spread; edge-clamp smear -> mirror fold; rim normal z 0.02 -> 1 (was a constant beige veil)
// A packing: raw pre-ACES accumulated feedback RGB in A.rgb, wrapping delay clock in A.a (C read the same way; ACES only on writeTexture)
// ----------------------------------------------------------------

#include "_prelude.wgsl"

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

// RESCUE 2026-11-08: the previous pair mixed the XYZ M1 with the forward M2 and returned a
// constant green tint for every layer. Standard linear-sRGB OkLab (Ottosson) instead.
fn linear_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    let l_ = pow(max(l, 0.0), 1.0 / 3.0);
    let m_ = pow(max(m, 0.0), 1.0 / 3.0);
    let s_ = pow(max(s, 0.0), 1.0 / 3.0);
    return vec3<f32>(
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    );
}

fn oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    let m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    let s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    let l = l_ * l_ * l_;
    let m = m_ * m_ * m_;
    let s = s_ * s_ * s_;
    return vec3<f32>(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    );
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

// RESCUE 2026-11-08: ping-pong fold instead of clamp — at the default distortion (0.5 -> +-0.5 uv) the clamp
// turned most of the frame into edge-column stripes; the fold keeps the same warp but tiles the picture.
fn mirror01(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(1.0) - abs(fract(p * 0.5) * 2.0 - vec2<f32>(1.0));
}

// ─── Idea 1: lagged echo tap — one layer's distorted, chroma-split video sample ───
// ── Idea 4: per-channel time lag — R, G, B each read the distortion field at their own time-stamp (wob_r/wob_g/wob_b)
fn echo_tap(uv: vec2<f32>, wob_r: vec2<f32>, wob_g: vec2<f32>, wob_b: vec2<f32>, shift_r: f32, shift_b: f32, resolution: vec2<f32>) -> vec3<f32> {
    let hi = vec2<i32>(resolution) - vec2<i32>(1);
    let r_uv = mirror01(uv + wob_r + vec2<f32>(shift_r, 0.0));
    let g_uv = mirror01(uv + wob_g);
    let b_uv = mirror01(uv + wob_b - vec2<f32>(shift_b, 0.0));
    let r = textureLoad(readTexture, clamp(vec2<i32>(r_uv * resolution), vec2<i32>(0), hi), 0).r;
    let g = textureLoad(readTexture, clamp(vec2<i32>(g_uv * resolution), vec2<i32>(0), hi), 0).g;
    let b = textureLoad(readTexture, clamp(vec2<i32>(b_uv * resolution), vec2<i32>(0), hi), 0).b;
    return vec3<f32>(r, g, b);
}

// Value noise for the stamp-ink dropout (Idea 5).
fn ink_hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn ink_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(ink_hash(i), ink_hash(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(ink_hash(i + vec2<f32>(0.0, 1.0)), ink_hash(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

// ─── Per-layer ink hue on the layer's age phase (replaces dead plasmaBuffer[1..255] colour read) ───
fn stamp_ink(phase: f32) -> vec3<f32> {
    let h = phase * 2.0 * PI;
    // chroma 0.10 -> 0.17: the old 0.10 was never seen (the broken OkLab pair returned green); at 0.10 the working pair is beige mush
    let lab = vec3<f32>(0.72, 0.17 * cos(h), 0.17 * sin(h));
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
    // ink hue spread across layers 360 deg -> 180 deg: eight inks 45 deg apart averaged to neutral beige; the age phase
    // (color_shift) is untouched, so ring radius/envelope are exactly HEAD's
    let ink_phase_raw = time * 0.1 + layer_factor * 0.5;
    let ink_color = stamp_ink(ink_phase_raw - floor(ink_phase_raw));

    // OkLab mix with blackbody temperature
    let temp = layer_factor + bass * 0.3;
    let bb = blackbody(temp);
    let mixed = oklab_mix(ink_color, bb, 0.5 + bass * 0.2);

    let layer_weight = exp(-current_delay * delay_scale * f32(i));

    // Idea 1: lagged echo tap — this layer sees the distortion field as it was i*lag ago
    let t_i = time - lag_dt * f32(i);
    let wob = vec2<f32>(sin(uv.y * 10.0 + t_i) * amp, cos(uv.x * 10.0 + t_i) * amp);
    // ── Idea 4: chroma delay line — R reads the warp tau_i later, B tau_i earlier; layer 0 (tau=0) is HEAD's sample,
    // older layers spread further apart in time, so the RGB fringe grows with layer age
    let tau_i = 0.04 * lag_dt * f32(i);
    let wob_r = vec2<f32>(sin(uv.y * 10.0 + t_i + tau_i) * amp, cos(uv.x * 10.0 + t_i + tau_i) * amp);
    let wob_b = vec2<f32>(sin(uv.y * 10.0 + t_i - tau_i) * amp, cos(uv.x * 10.0 + t_i - tau_i) * amp);
    let echo = echo_tap(uv, wob_r, wob, wob_b, chromatic_shift * (1.0 + bass), chromatic_shift * (1.0 + treble), resolution);
    final_color += echo * mixed * layer_weight;

    // Idea 2: postmark ring — radius = layer age, born/dies invisibly, dashed, warped by the distortion
    let ring_env = sin(PI * color_shift);
    let rp = (uv + wob - anchor) * asp;
    let ring_r = 0.06 + color_shift * 0.6;
    let ring_d = abs(length(rp) - ring_r);
    let ang = atan2(rp.y, rp.x);
    let dash_f = fract(ang * (16.0 / (2.0 * PI)) + f32(i) * 0.37 + time * 0.05);
    let dash = 0.35 + 0.65 * smoothstep(0.3, 0.6, abs(dash_f - 0.5) * 2.0);
    // ── Idea 5: double-circle datestamp — a thin inner circle at 0.84 r (the classic CDS postmark) and uneven
    // rubber-stamp ink: a value-noise dropout mask over both circles
    let ring_d2 = abs(length(rp) - ring_r * 0.84);
    let ink = smoothstep(0.30, 0.55, ink_noise(rp * 60.0 + vec2<f32>(f32(i) * 7.3, 3.1)));
    let ring_both = (1.0 - smoothstep(0.0, 0.007, ring_d)) * dash + (1.0 - smoothstep(0.0, 0.0035, ring_d2)) * 0.6;
    ring_acc += mixed * ring_both * ink * ring_env * layer_weight;
  }

  final_color = final_color / f32(layer_count);
  final_color += ring_acc * 0.45;

  let mouse_dist = distance(uv, mouse);
  let isMouseActive = mouse_dist < 0.1 && u.zoom_config.w > 0.5;
  final_color += vec3<f32>(1.0 - mouse_dist * 10.0) * bass * select(0.0, 1.0, isMouseActive);

  // Fresnel rim glow on distortion edges
  // RESCUE 2026-11-08: z was 0.02, so the normal lay flat for any offset and rim ~= 1 everywhere — a constant beige veil
  // with dark dots where the sines cross zero. With z = 1 the rim follows the distortion slope and edges glow.
  let edgeNormal = normalize(vec3<f32>(r_dist_offset.x, b_dist_offset.y, 1.0));
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
