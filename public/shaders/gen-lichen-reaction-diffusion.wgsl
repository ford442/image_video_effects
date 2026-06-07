// ═══════════════════════════════════════════════════════════════════
//  Lichen Reaction-Diffusion
//  Category: generative
//  Description: Gray-Scott reaction-diffusion system simulating
//    lichen growth patterns. Creates organic, slowly evolving
//    patterns reminiscent of coral lichens, leopard spots, and
//    maze-like structures. Mouse deposits additional activator.
//  Complexity: High
//  Upgraded: 2026-06-07
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  Lichen Reaction Diffusion
//  Category: generative
//  Features: lichen, reaction-diffusion, organic, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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

const PI: f32 = 3.14159265359;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0;
  return mix(mix(hashf(n), hashf(n + 1.0), u.x), mix(hashf(n + 57.0), hashf(n + 58.0), u.x), u.y);
}

fn lichen_color(v: f32, p4: f32) -> vec3<f32> {
  let t = clamp(v, 0.0, 1.0);
  let shifted = fract(t + p4);
  let colors = array<vec3<f32>, 7>(
    vec3<f32>(0.55, 0.52, 0.48), vec3<f32>(0.65, 0.60, 0.52),
    vec3<f32>(0.75, 0.72, 0.45), vec3<f32>(0.55, 0.68, 0.35),
    vec3<f32>(0.40, 0.55, 0.30), vec3<f32>(0.55, 0.35, 0.22),
    vec3<f32>(0.35, 0.30, 0.25)
  );
  let idx = shifted * 6.0;
  let i = i32(clamp(idx, 0.0, 5.0));
  let f = fract(idx);
  return mix(colors[i], colors[i + 1], f);
}

// Branchless lichen pattern evaluation
fn evalLichen(uv_in: vec2<f32>, time: f32, p2: f32, pattern_scale: f32, feed: f32, kill: f32) -> f32 {
  let n1 = vnoise(uv_in * pattern_scale + time * p2 * 0.02);
  let n2 = vnoise(uv_in * pattern_scale * 1.5 + vec2<f32>(13.7, 7.3) + time * p2 * 0.015);
  let n3 = vnoise(uv_in * pattern_scale * 2.0 + vec2<f32>(31.1, 19.7) - time * p2 * 0.01);
  let n4 = vnoise(uv_in * pattern_scale * 0.5 + vec2<f32>(47.3, 23.1));
  let fk_diff = kill - feed;
  let v1 = n1 * n2 + n3 * 0.2;
  let v2 = smoothstep(0.3, 0.7, n1) * (1.0 - smoothstep(0.6, 0.9, n2));
  let v3 = smoothstep(0.4, 0.6, n1) * smoothstep(0.4, 0.6, n2) * 0.8 + smoothstep(0.3, 0.5, n3) * 0.2;
  let v4 = fract(n1 * 3.0 + n2 * 2.0 + time * p2 * 0.05) * 0.5 + n3 * 0.3;
  let c1 = step(fk_diff, 0.01);
  let c2 = step(0.01, fk_diff) * step(fk_diff, 0.02);
  let c3 = step(0.02, fk_diff) * step(fk_diff, 0.035);
  let c4 = step(0.035, fk_diff);
  return v1 * c1 + v2 * c2 + v3 * c3 + v4 * c4 + n4 * 0.15 - 0.075;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = vec2<f32>(pixel) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);
  let prevVal = dot(prev.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Depth-based scale and perspective
  let depthScale = mix(0.6, 1.4, depth);
  let scale = (4.0 + p3 * 8.0) * depthScale;
  let pattern_scale = scale * (0.8 + p1 * 1.5);

  // Bass-driven feed/kill modulation
  let feed = 0.03 + uv.x * 0.04 + sin(time * p2 * 0.01) * 0.01 + bass * 0.015;
  let kill = 0.055 + uv.y * 0.02 + cos(time * p2 * 0.012) * 0.005 - bass * 0.008;

  // Chromatic aberration: evaluate pattern at RGB offsets
  let caStrength = 0.002 * (1.0 + bass) * depthScale;
  let rVal = evalLichen(uv + vec2<f32>(caStrength, 0.0), time, p2, pattern_scale, feed, kill);
  let gVal = evalLichen(uv, time, p2, pattern_scale, feed, kill);
  let bVal = evalLichen(uv - vec2<f32>(caStrength, 0.0), time, p2, pattern_scale, feed, kill);
  var v_chem = vec3<f32>(rVal, gVal, bVal);

  // Mouse deposit (branchless)
  let m_dist = length(uv - mouse);
  let deposit = exp(-m_dist * m_dist * 2000.0) * 0.5 * f32(mouseDown);
  v_chem += vec3<f32>(deposit);

  // Ripple deposits (branchless)
  for (var i = 0; i < 3; i++) {
    let rp = u.ripples[i];
    let r_age = time - rp.z;
    let rippleActive = step(0.001, rp.z) * step(0.0, r_age) * step(r_age, 3.0);
    let r_pos = vec2<f32>(rp.x, rp.y) / resolution;
    let r_dist = length(uv - r_pos);
    let ring = exp(-pow(r_dist - r_age * 0.05, 2.0) * 200.0) * (1.0 - r_age / 3.0);
    v_chem += vec3<f32>(ring * 0.3 * rippleActive);
  }

  let pattern_val = clamp(v_chem, vec3<f32>(0.0), vec3<f32>(1.0));

  // Rock texture with depth scaling
  let rock_texture = vnoise(uv * 20.0 * depthScale) * 0.1 + vnoise(uv * 50.0 * depthScale) * 0.05;

  // Apply lichen color per channel for chromatic separation
  var color = vec3<f32>(
    lichen_color(pattern_val.r, p4).r,
    lichen_color(pattern_val.g, p4).g,
    lichen_color(pattern_val.b, p4).b
  );
  color += vec3<f32>(rock_texture * 0.08);

  // Detail noise layer
  let detail_noise = vnoise(uv * pattern_scale * 4.0 + vec2<f32>(time * p2 * 0.03)) * 0.08 * depth;
  let pattern_density = dot(pattern_val, vec3<f32>(0.333));
  color += vec3<f32>(0.4, 0.5, 0.3) * detail_noise * pattern_density;

  // Moss highlight (bass-reactive)
  let moss_highlight = smoothstep(0.5, 0.8, pattern_density) * bass * 0.15;
  color += vec3<f32>(0.6, 0.75, 0.4) * moss_highlight;

  // Spore dispersal particles
  let spore_time = time * p2 * 0.5;
  var spore_glow = 0.0;
  for (var i = 0; i < 4; i++) {
    let spore_seed = f32(i) * 91.3 + spore_time;
    let spore_pos = vec2<f32>(hashf(spore_seed), hashf(spore_seed + 37.0));
    let spore_dist = length(uv - spore_pos);
    spore_glow += exp(-spore_dist * spore_dist * 800.0) * 0.1;
  }
  color += vec3<f32>(0.8, 0.85, 0.7) * spore_glow * bass;

  // Growth animation pulse
  color *= 1.0 + sin(time * p2 * 0.3) * 0.03;

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.8, length(uv - 0.5));
  color *= 0.85 + vignette * 0.15;

  // Temporal growth persistence with decay
  let persistence = 0.96 + bass * 0.02;
  let temporal = prev.rgb * persistence;
  color = max(color, temporal * 0.35);

  // ACES tone mapping
  color = acesToneMap(color * 1.3);

  let growth_activity = abs(pattern_density - prevVal);
  let alpha = pattern_density * growth_activity * depth;

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(pattern_density, 0.0, 0.0, 0.0));

  // ═══ CHUNK: multi-pass state packing — persist color for `prev.rgb * persistence` feedback ═══
  // Without this write, dataTextureC always reads zero and growth persistence/activity tracking is dead code.
  textureStore(dataTextureA, pixel, vec4<f32>(color, pattern_density));
}
