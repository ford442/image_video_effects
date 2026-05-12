// ═══════════════════════════════════════════════════════════════════
//  Interactive RGB Split
//  Category: distortion
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Phase A Upgrade Swarm
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Falloff, z=Mode, w=AngleOffset
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0, 1.0));

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  // Mouse Input
  var mouse = u.zoom_config.yz; // 0..1
  // If mouse is -1,-1 (off canvas), default to center
  var center = mouse;
  if (center.x < 0.0) { center = vec2<f32>(0.5, 0.5); }

  let bass = plasmaBuffer[0].x;

  // Parameters
  let strength = u.zoom_params.x * 0.05 * (1.0 + bass * 0.3); // Max split amount
  let falloff = clamp(u.zoom_params.y, 0.0, 1.0); // How fast effect fades from mouse
  let mode = clamp(u.zoom_params.z, 0.0, 1.0); // 0 = radial, 1 = directional
  let angleOffset = u.zoom_params.w;

  let aspect = resolution.x / max(resolution.y, 1.0);
  let uv_aspect = uv * vec2<f32>(aspect, 1.0);
  let center_aspect = center * vec2<f32>(aspect, 1.0);

  let dist = distance(uv_aspect, center_aspect);
  let delta = uv_aspect - center_aspect;
  let deltaLen = max(length(delta), 0.001);
  var dir = delta / deltaLen;

  // Calculate aberration amount
  // If falloff is high, effect is localized to mouse.
  // If falloff is low, effect is global.
  var amount = strength;
  if (falloff > 0.001) {
      amount *= smoothstep(0.8, 0.0, dist * falloff * 2.0);
  }

  var r_uv = uv;
  var b_uv = uv;

  if (mode < 0.5) {
      // Radial Split (away from mouse)
      // Correct direction for non-square aspect ratio
      let offset = (uv - center) * amount;
      r_uv = uv - offset;
      b_uv = uv + offset;
  } else {
      // Directional Split (based on angle)
      // Rotate dir by angleOffset
      let angle = angleOffset * 6.2831;
      let s = sin(angle);
      let c = cos(angle);
      let splitDir = vec2<f32>(c, s);

      r_uv = uv - splitDir * amount;
      b_uv = uv + splitDir * amount;
  }

  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g; // G stays put
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

  // Alpha: split intensity as compositing weight — more aberration = more prominent blend
  let splitMag = length(r_uv - b_uv);
  let luma = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(splitMag * 5.0 + luma * 0.4 + 0.1, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(r, g, b, alpha));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
