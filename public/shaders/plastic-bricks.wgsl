// ================================================================
//  Plastic Bricks
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: plastic-bricks
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
  zoom_params: vec4<f32>,  // x=BrickDensity, y=StudSize, z=ReliefDepth, w=Bevel
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(173.3, 251.9))) * 43758.5453);
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

  let density = mix(6.0, 32.0, u.zoom_params.x);
  let studSize = mix(0.10, 0.38, u.zoom_params.y);
  let relief = mix(0.06, 0.40, u.zoom_params.z);
  let bevel = mix(0.01, 0.18, u.zoom_params.w);

  var brickUV = uv * density;
  if (fract(floor(brickUV.y) * 0.5) >= 0.5) {
    brickUV.x = brickUV.x + 0.5;
  }
  let brickId = floor(brickUV);
  let cell = fract(brickUV) - 0.5;

  let mortar = smoothstep(0.46, 0.50, max(abs(cell.x), abs(cell.y)));
  let studDist = length(cell);
  let studMask = 1.0 - smoothstep(studSize, studSize + bevel, studDist);
  let bodyMask = 1.0 - mortar;

  let centerUV = clamp((brickId + 0.5) / density, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0).rgb;

  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseGlow = 1.0 - smoothstep(0.0, 0.45, mouseDist);
  let huePulse = hash12(brickId + vec2<f32>(floor(time), 0.0));
  let toyTint = mix(vec3<f32>(1.0, 0.25, 0.18), vec3<f32>(0.05, 0.75, 1.0), huePulse + audio.z * 0.3);

  var finalColor = mix(baseColor, toyTint, 0.30 * bodyMask + 0.25 * studMask);
  let highlight = studMask * (0.18 + audio.x * 0.25) + bodyMask * mouseGlow * 0.10;
  finalColor = finalColor + vec3<f32>(1.0, 0.95, 0.85) * highlight;

  let reliefMask = clamp(bodyMask * relief + studMask * (relief + 0.25), 0.0, 1.0);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, centerUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.20 + reliefMask * 0.75, 0.35), 0.0, 1.0);
  let finalAlpha = clamp(0.72 + reliefMask * 0.18 + highlight * 0.2, 0.48, 0.99);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(studMask, mortar, mouseGlow, finalAlpha));
}
