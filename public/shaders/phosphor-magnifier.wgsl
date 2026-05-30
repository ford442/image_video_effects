// ================================================================
//  Phosphor Magnifier
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: phosphor-magnifier
//  Created: 2026-05-30
//  By: Copilot
// ================================================================

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
  zoom_params: vec4<f32>,  // x=ZoomLevel, y=PixelSize, z=Glow, w=LensSize
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;

  let zoomLevel = mix(1.0, 8.0, u.zoom_params.x);
  let pixelSize = mix(40.0, 420.0, u.zoom_params.y);
  let glow = mix(0.05, 0.55, u.zoom_params.z);
  let lensSize = mix(0.08, 0.45, u.zoom_params.w);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let lensMask = 1.0 - smoothstep(lensSize - 0.05, lensSize, dist);

  let zoomed = clamp(mouse + (uv - mouse) / zoomLevel, vec2<f32>(0.0), vec2<f32>(1.0));
  let snapped = floor(zoomed * pixelSize) / pixelSize;
  let sampleUV = mix(uv, snapped, lensMask);
  let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  let local = fract(sampleUV * pixelSize) - 0.5;
  let scan = 0.6 + 0.4 * sin((sampleUV.y * dims.y) * 0.55 + time * 8.0);
  let phosphor = vec3<f32>(
    0.7 + 0.3 * smoothstep(-0.5, 0.0, local.x),
    0.7 + 0.3 * smoothstep(-0.15, 0.15, local.x),
    0.7 + 0.3 * smoothstep(0.0, 0.5, local.x)
  );
  let halo = glow * lensMask * (0.6 + audio.x + audio.y * 0.5);
  var finalColor = sampleColor * phosphor * scan;
  finalColor = finalColor + vec3<f32>(0.12, 0.95, 0.48) * halo;

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let finalAlpha = clamp(0.68 + lensMask * 0.20 + halo * 0.10, 0.42, 0.98);
  let depthOut = clamp(mix(baseDepth, 0.20 + lensMask * 0.72, 0.28), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(lensMask, scan, halo, finalAlpha));
}
