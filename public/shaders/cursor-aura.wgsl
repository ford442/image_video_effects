// ═══════════════════════════════════════════════════════════════════
//  Cursor Aura
//  Category: interactive-mouse
//  Features: mouse-driven, glow, audio-reactive, upgraded-rgba
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
  let texel = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001));
  let time = u.config.x;

  // Audio reactivity
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params
  let radius     = clamp(u.zoom_params.x * (1.0 + bass * 0.2), 0.0, 1.0) * 0.5;
  let intensity  = clamp(u.zoom_params.y * (1.0 + mids * 0.15), 0.0, 1.0);
  let mixVal     = u.zoom_params.z;
  let pulseSpeed = clamp(u.zoom_params.w * (1.0 + treble * 0.1), 0.0, 1.0) * 5.0;

  let mousePos = u.zoom_config.yz;

  // Aspect ratio correction with guard
  let aspect = resolution.x / max(resolution.y, 0.001);
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uvCorrected, mouseCorrected);

  // Pulsing radius with audio reactivity
  let currentRadius = max(radius + sin(time * pulseSpeed) * 0.02 * (1.0 + bass), 0.001);

  // Aura Mask
  let mask = 1.0 - smoothstep(currentRadius, currentRadius + 0.05, dist);

  // Base Color
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Effect Color (Edge Detection / High Pass)
  let offset = 1.0 / max(resolution.x, 0.001);
  let left   = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right  = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>( offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let top    = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -offset), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let bottom = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0,  offset), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let edges = abs(left - right) + abs(top - bottom);
  let glowStrength = intensity * (1.0 + bass * 0.5);
  let effectColor = edges * 2.0 + vec4<f32>(vec3<f32>(0.0, 0.5, 1.0) * glowStrength, glowStrength);

  // Combine
  let inside = mix(baseColor, effectColor, mixVal);

  // Glowing ring at the edge
  let ring = smoothstep(currentRadius - 0.01, currentRadius, dist) * smoothstep(currentRadius + 0.01, currentRadius, dist);
  let ringStrength = ring * intensity * 2.0 * (1.0 + bass);
  let ringColor = vec4<f32>(ringStrength, ringStrength, ringStrength, ringStrength);

  let preFinal = mix(baseColor, inside, mask) + ringColor;
  let finalAlpha = clamp(preFinal.a, 0.0, 1.0);
  let finalColor = vec4<f32>(preFinal.rgb, finalAlpha);

  // Depth read and mandatory writes
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, texel, finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
