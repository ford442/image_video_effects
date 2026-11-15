// ═══════════════════════════════════════════════════════════════════
//  Psychedelic Noise Flow
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17, 2026-11-15
//  Ideas: filament-aligned smear; current trail
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash2(p: vec2<f32>) -> vec2<f32> {
  let p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(dot(hash2(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                 dot(hash2(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
             mix(dot(hash2(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                 dot(hash2(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let speed_param = u.zoom_params.x * (1.0 + bass * 0.3);
  let scale_param = u.zoom_params.y;
  let distort_param = u.zoom_params.z;
  let color_shift = u.zoom_params.w;

  let noise_scale = scale_param * 8.0 + 1.0;
  let strength = distort_param * 0.1 * (1.0 + mids * 0.5);

  let mouse = u.zoom_config.yz;
  let mouse_dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouse_delta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let mouse_dir = mouse_delta / max(length(mouse_delta), 0.001);
  let mouse_influence = smoothstep(0.4, 0.0, mouse_dist);
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = max(time - event.z, 0.0);
    clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
  }

  let t = time * (speed_param * 2.0 + 0.1);
  let vortex = vec2<f32>(-mouse_dir.y, mouse_dir.x) * mouse_influence * held;
  let nArg = uv * noise_scale + vec2<f32>(t, t * 0.5) - mouse_influence * mouse_dir + vortex;
  let n_r = noise(nArg);
  let n_g = noise(uv * noise_scale + vec2<f32>(t + 10.0, t * 0.6 + 10.0) + mouse_influence * mouse_dir * 0.5);
  let n_b = noise(uv * noise_scale + vec2<f32>(t + 20.0, t * 0.7 + 20.0));

  let d_r = vec2<f32>(n_r, noise(uv * noise_scale + vec2<f32>(n_r, t))) * strength;
  let d_g = vec2<f32>(n_g, noise(uv * noise_scale + vec2<f32>(n_g, t + 5.0))) * strength;
  let d_b = vec2<f32>(n_b, noise(uv * noise_scale + vec2<f32>(n_b, t + 10.0))) * strength;

  let final_d_r = d_r;
  let final_d_g = mix(d_r, d_g, color_shift);
  let final_d_b = mix(d_r, d_b, color_shift);

  let filament = sin((n_r + n_g - n_b) * 18.0 + time * 2.0) * 0.5 + 0.5;
  // ── Idea 1: filament-aligned smear ─────────────────────────────────
  // Finite difference of the existing n_r. Colour slides along that tangent,
  // stronger where the filament is already bright.
  let nEps = 0.55;
  let grad = vec2<f32>(noise(nArg + vec2<f32>(nEps, 0.0)) - n_r, noise(nArg + vec2<f32>(0.0, nEps)) - n_r);
  let tangent = vec2<f32>(-grad.y, grad.x) / max(length(grad), 0.0001);
  let along = tangent * strength * (0.35 + filament * 0.9);
  let smearR = final_d_r + along;
  let smearG = final_d_g + along * 0.85;
  let smearB = final_d_b + along * 0.7;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + smearR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + smearG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + smearB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + filament * 5.0 + time * (0.4 + treble));
  var finalRgb = vec3<f32>(r, g, b) + spectral * (filament * 0.08 + clickFront * 0.22 + held * mouse_influence * 0.1);
  // ── Idea 2: current trail ──────────────────────────────────────────
  // Exact C, upstream of the red displacement. Flow Speed sets the step,
  // Distortion sets how much of the trail is kept.
  let wakeUv = clamp(uv - smearR * (0.65 + speed_param * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
  let wakeDims = vec2<i32>(textureDimensions(dataTextureC));
  let wakePx = clamp(vec2<i32>(wakeUv * vec2<f32>(wakeDims)), vec2<i32>(0), wakeDims - vec2<i32>(1));
  let wake = textureLoad(dataTextureC, wakePx, 0);
  finalRgb = mix(finalRgb, wake.rgb, 0.16 + distort_param * 0.14);
  finalRgb = aces(max(finalRgb, vec3<f32>(0.0)));
  let alpha = clamp(baseColor.a * 0.5 + (length(smearR) + length(smearG) + length(smearB)) * 5.0 + filament * 0.18 + mouse_influence * 0.2, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let outCol = vec4<f32>(finalRgb, alpha);
  textureStore(writeTexture, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, outCol);
}
