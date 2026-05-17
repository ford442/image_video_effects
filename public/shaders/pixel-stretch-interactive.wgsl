// ═══════════════════════════════════════════════════════════════════
//  Pixel Stretch Interactive
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Upgraded: 2026-05-17
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
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let modeParam = u.zoom_params.x;
  let jitterStr = u.zoom_params.y;
  let rgbShift = u.zoom_params.z * (1.0 + mids * 0.3);

  let isRight = modeParam < 0.33;
  let isLeft = modeParam >= 0.33 && modeParam < 0.66;
  let isCross = modeParam >= 0.66;

  let stretchRight = isRight && uv.x > mouse.x;
  let stretchLeft = isLeft && uv.x < mouse.x;
  let stretchCrossX = isCross && uv.x > mouse.x;
  let stretchCrossY = isCross && uv.y > mouse.y;

  var sample_uv = uv;
  sample_uv.x = select(sample_uv.x, mouse.x, stretchRight || stretchLeft || stretchCrossX);
  sample_uv.y = select(sample_uv.y, mouse.y, stretchCrossY);
  let is_stretched = stretchRight || stretchLeft || stretchCrossX || stretchCrossY;

  let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let jitter = select(vec2<f32>(0.0), vec2<f32>((noise - 0.5) * 0.1 * jitterStr), is_stretched && noise > 0.5 && jitterStr > 0.0);
  sample_uv = clamp(sample_uv + jitter, vec2<f32>(0.0), vec2<f32>(1.0));

  let shift = rgbShift * 0.02;
  let r = textureSampleLevel(readTexture, u_sampler, sample_uv + vec2<f32>(shift, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, sample_uv - vec2<f32>(shift, 0.0), 0.0).b;
  let caColor = vec4<f32>(r, g, b, 1.0);
  let normalColor = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);

  let color = select(normalColor, caColor, is_stretched && rgbShift > 0.0);
  let alpha = clamp(color.a + select(0.0, 0.2 * bass, is_stretched), 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(color.rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(color.rgb, alpha));
}
