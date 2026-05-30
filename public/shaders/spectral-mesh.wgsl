// ================================================================
//  Spectral Mesh
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: spectral-mesh
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GridDensity, y=DisplacementStrength, z=MouseRadius, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

fn palette(t: f32) -> vec3<f32> {
  return 0.52 + 0.48 * cos(6.28318 * (vec3<f32>(0.0, 0.18, 0.35) + t));
}

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

  let density = 6.0 + u.zoom_params.x * 82.0;
  let displacementStrength = u.zoom_params.y * 0.08;
  let mouseRadius = max(0.02, u.zoom_params.z * 0.7);
  let colorShift = u.zoom_params.w;

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let pull = 1.0 - smoothstep(0.0, mouseRadius, dist);
  let wobble = vec2<f32>(
    sin(uv.y * density + time * (0.8 + audio.x * 2.0)),
    cos(uv.x * density * 1.2 - time * (1.1 + audio.y * 1.6))
  ) * displacementStrength * pull;
  let sampleUV = clamp(uv + wobble, vec2<f32>(0.0), vec2<f32>(1.0));

  let grid = abs(fract(sampleUV * density) - 0.5);
  let line = 1.0 - smoothstep(0.0, 0.08 + audio.z * 0.02, min(grid.x, grid.y));
  let diagonal = 1.0 - smoothstep(0.08, 0.22, abs(grid.x - grid.y));

  var baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let spectral = palette(colorShift + sampleUV.x * 0.5 + time * 0.04 + audio.y * 0.2);
  baseColor = mix(baseColor, spectral, line * 0.45 + diagonal * 0.15);
  baseColor = baseColor + spectral * diagonal * (0.08 + 0.20 * pull);

  let finalAlpha = clamp(0.70 + line * 0.18 + pull * 0.12, 0.40, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.22 + line * 0.75 + pull * 0.15, 0.28), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(baseColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(line, diagonal, pull, finalAlpha));
}
