// ═══════════════════════════════════════════════════════════════════
//  Circular Pixelate
//  Category: image
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-17
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;

  let density_param = u.zoom_params.x;
  let radius_param = u.zoom_params.y;
  let hardness_param = u.zoom_params.z;
  let bg_mix_param = u.zoom_params.w;

  let cells = density_param * 100.0 + 10.0;
  let cell_count_x = cells;
  let cell_count_y = cells / max(aspect, 0.001);

  let grid_uv = uv * vec2<f32>(cell_count_x, cell_count_y);
  let cell_id = floor(grid_uv);
  let cell_local = fract(grid_uv) - 0.5;
  let dist = length(cell_local);

  let sample_uv = (cell_id + 0.5) / vec2<f32>(cell_count_x, cell_count_y);
  let color = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let mouse_dist = distance(uv, mouse);
  let interaction = 1.0 - smoothstep(0.0, 0.3, mouse_dist);

  let ripple_count = u32(u.config.y);
  var click_boost = 0.0;
  for (var i = 0u; i < ripple_count; i = i + 1u) {
    let ripple = u.ripples[i];
    let r_dist = distance(uv, ripple.xy);
    let elapsed = time - ripple.z;
    let ripple_radius = elapsed * 0.4;
    let ripple_strength = 1.0 - smoothstep(0.0, 0.6, elapsed);
    click_boost = click_boost + smoothstep(ripple_radius + 0.15, ripple_radius, r_dist) * ripple_strength * 0.25;
  }

  let is_mouse_down = u.zoom_config.w > 0.5;
  let click_pulse = select(0.0, 0.15 * sin(time * 8.0), is_mouse_down);

  let depth_scale = mix(0.6, 1.0, depth);
  let audio_pulse = 1.0 + bass * 0.3;
  let final_radius = (radius_param * 0.5 + interaction * 0.2 + click_boost + click_pulse) * depth_scale * audio_pulse;

  let edge = 0.01 + (1.0 - hardness_param) * 0.2;
  let mask = 1.0 - smoothstep(max(final_radius - edge, 0.0), final_radius, dist);

  let tint = (hash12(cell_id + 0.5) - 0.5) * 0.06;
  let hue_cycle = mids * 0.2;
  let tinted = color.rgb + vec3<f32>(tint + hue_cycle, tint * 0.7 - hue_cycle * 0.3, -tint * 0.5 + hue_cycle * 0.1);

  let highlight = smoothstep(final_radius * 0.7, final_radius, dist) * 0.15;
  let dot_rgb = tinted + highlight;

  let dot_color = vec4<f32>(dot_rgb, color.a);
  let effect = mix(vec4<f32>(0.0), dot_color, mask);
  let final_color = mix(orig, effect, bg_mix_param);

  textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), final_color);
}
