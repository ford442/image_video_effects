// ═══════════════════════════════════════════════════════════════════
//  Mirror Drag
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Upgraded: 2026-05-17
//  By: Shader Upgrade Swarm
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let side = u.zoom_params.x;
  let flipY = u.zoom_params.y;
  let smoothness = u.zoom_params.z;
  let mode = u.zoom_params.w;

  let axisX = mousePos.x + sin(time * 2.0) * bass * 0.02;
  let axisY = mousePos.y + cos(time * 1.5) * mids * 0.02;

  let isRightSide = side > 0.5;
  let isFlipY = flipY > 0.5;
  let isKaleido = mode > 0.5;

  var finalUV = uv;

  let xReflected = select(
    select(axisX + (axisX - uv.x), uv.x, uv.x >= axisX),
    select(axisX - (uv.x - axisX), uv.x, uv.x <= axisX),
    isRightSide
  );
  finalUV.x = mix(uv.x, xReflected, smoothstep(0.0, 0.1 + smoothness * 0.4, abs(uv.x - axisX)));

  let yReflected = axisY - (uv.y - axisY);
  finalUV.y = select(finalUV.y, mix(uv.y, yReflected, smoothstep(0.0, 0.1 + smoothness * 0.4, abs(uv.y - axisY))), isFlipY);

  let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

  let distToAxisX = abs(uv.x - axisX);
  let distToAxisY = abs(uv.y - axisY);
  let seamGlow = (smoothstep(0.02, 0.0, distToAxisX) + smoothstep(0.02, 0.0, distToAxisY) * select(0.0, 1.0, isFlipY)) * smoothness;
  let neon = vec3<f32>(1.0, 0.5, 0.8) * seamGlow * (1.0 + bass);

  let mirroredAlpha = mix(color.a, 1.0, smoothstep(0.0, 0.5, abs(uv.x - axisX)) * 0.3);
  let alpha = select(mirroredAlpha, color.a * 0.8, isKaleido);

  let finalColor = color.rgb + neon;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
}
