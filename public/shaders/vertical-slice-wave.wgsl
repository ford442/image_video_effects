// ═══════════════════════════════════════════════════════════════════
//  Vertical Slice Wave
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3  = fract(vec3<f32>(p.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) {
    return;
  }

  let resolution = u.config.zw;
  let coords = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Per-pixel temporal state read from previous frame
  let prev = textureLoad(dataTextureC, coords, 0);

  // Attack/release audio envelope per-pixel
  let attack = select(0.15, 0.8, bass > prev.r);
  let env = mix(prev.r, bass, attack);

  // Spring-damped mouse follow per-pixel
  let mouse_target = u.zoom_config.yz;
  let spring = prev.gb;
  let vel = prev.a;
  let dir = mouse_target - spring;
  let dist = length(dir);
  let ndir = select(vec2<f32>(0.0), dir / max(dist, 0.001), dist > 0.001);
  let force = dist * 12.0 - vel * 3.0;
  let vel_new = vel + force * 0.016;
  let spring_new = spring + ndir * vel_new * 0.016;

  // Parameters
  let strips_param = u.zoom_params.x;
  let speed_param = u.zoom_params.y;
  let rgb_split = u.zoom_params.z;
  let jitter_amt = u.zoom_params.w;

  // Mouse drives frequency & amplitude via spring-damped follow
  let freq_mod = spring_new.x * 40.0 + 1.0;
  let amp_mod = spring_new.y * 0.2;
  let click_burst = select(1.0, 1.8, u.zoom_config.w > 0.5);

  let num_strips = floor(strips_param * 100.0) + 5.0;
  let strip_id = floor(uv.x * num_strips);
  let strip_uv_x = strip_id / num_strips;

  // Wave with smoothed audio envelope
  let wave_speed = speed_param * 5.0;
  let wave_phase = strip_uv_x * freq_mod + time * wave_speed;
  let audio_amp = amp_mod * (1.0 + env * 0.5) * click_burst;
  var offset = sin(wave_phase) * audio_amp;

  // Jitter
  let noise_val = hash12(vec2<f32>(strip_id, floor(time * 10.0)));
  offset = offset + (noise_val - 0.5) * jitter_amt * 0.2;

  // RGB Split
  let split_factor = rgb_split * 0.05;

  // Sample with vertical displacement — clamp UVs
  let r_uv = clamp(vec2<f32>(uv.x, uv.y + offset - split_factor), vec2<f32>(0.0), vec2<f32>(1.0));
  let g_uv = clamp(vec2<f32>(uv.x, uv.y + offset), vec2<f32>(0.0), vec2<f32>(1.0));
  let b_uv = clamp(vec2<f32>(uv.x, uv.y + offset + split_factor), vec2<f32>(0.0), vec2<f32>(1.0));

  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

  // Temporal feedback trail
  let feedback = 0.82;
  var col = mix(vec3<f32>(r, g, b), prev.rgb, 0.18);
  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

  // Alpha encodes intensity + trail age + mids/treble sparkle
  let luminance = 0.299 * r + 0.587 * g + 0.114 * b;
  let intensity = clamp(abs(offset) * 10.0 + env * 0.3 + treble * 0.1, 0.0, 1.0);
  let base_alpha = mix(0.65, 0.98, luminance * 0.3 + intensity * 0.7);
  let trail_age = prev.a * feedback + base_alpha * (1.0 - feedback);

  // Depth pass-through
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let outColor = vec4<f32>(col, clamp(trail_age, 0.0, 1.0));

  // Persist per-pixel state for next frame (env, spring, velocity)
  let stateColor = vec4<f32>(env, spring_new, vel_new);

  textureStore(writeTexture, coords, outColor);
  textureStore(dataTextureA, coords, stateColor);
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
