// ═══════════════════════════════════════════════════════════════════
//  Sonar Pulse
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001, 0.001));
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let waveSpeed = mix(1.0, 10.0, u.zoom_params.x) * (1.0 + bass * 0.2);
  let waveFreq = mix(10.0, 100.0, u.zoom_params.y) + mids * 10.0;
  let intensity = clamp(u.zoom_params.z + treble * 0.1, 0.0, 1.0);
  let waveWidth = max(mix(0.1, 0.5, u.zoom_params.w), 0.001);

  // Mouse Position (corrected for aspect ratio)
  let aspect = resolution.x / max(resolution.y, 0.001);
  var mousePos = u.zoom_config.yz;

  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uv_corrected, mouse_corrected);

  // Sonar Pulse Logic
  let phase = dist * waveFreq - time * waveSpeed;
  let wave = sin(phase);
  let pulse = smoothstep(1.0 - waveWidth, 1.0, wave);
  let falloff = 1.0 / (1.0 + dist * 2.0);

  let audioBoost = 1.0 + bass * 0.5;
  let pulseStrength = pulse * intensity * falloff * audioBoost;

  // Branchless UV distortion
  let safeDist = max(dist, 0.001);
  let offsetDir = (uv_corrected - mouse_corrected) / safeDist;
  let distortAmt = 0.02 * pulse * intensity;
  let distortedUV = clamp(uv - offsetDir * distortAmt, vec2<f32>(0.0), vec2<f32>(1.0));
  let distortedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

  // Add a green/blue tint based on pulse
  let pulseColor = vec4<f32>(0.0, 1.0, 0.5, 0.0);
  var finalColor = mix(distortedColor, distortedColor + pulseColor * pulseStrength, 0.5);

  // Meaningful alpha based on luminance and effect intensity
  let luminance = dot(finalColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  finalColor.a = clamp(luminance + pulseStrength * 0.3, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
