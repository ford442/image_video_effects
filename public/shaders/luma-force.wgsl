// ═══════════════════════════════════════════════════════════════════
//  Luma Force
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
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let strength = u.zoom_params.x * (1.0 + bass * 0.5);
  let radius = u.zoom_params.y;
  let mode = u.zoom_params.z;
  let lumaWeight = u.zoom_params.w;

  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uvCorrected, mouseCorrected);
  let falloff = smoothstep(radius, 0.0, dist);

  var dir = normalize(uv - mouse + vec2<f32>(0.0001));
  let isAttract = mode > 0.5;
  let forceDir = select(-dir, dir, isAttract);

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let effectiveStrength = strength * mix(1.0, luma, lumaWeight);
  let offsetAmt = falloff * effectiveStrength * 0.2;
  let offset = forceDir * offsetAmt;

  let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  let swirl = mids * 0.02 * falloff;
  let rotUV = clamp(sampleUV + vec2<f32>(-offset.y, offset.x) * swirl, vec2<f32>(0.0), vec2<f32>(1.0));
  let swirlColor = textureSampleLevel(readTexture, u_sampler, rotUV, 0.0);
  let blended = mix(finalColor, swirlColor, falloff * mids);

  let alpha = mix(blended.a, 1.0, falloff * 0.3);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(blended.rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(blended.rgb, alpha));
}
