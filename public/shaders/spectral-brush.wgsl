// ═══════════════════════════════════════════════════════════════════
//  Spectral Brush
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: Medium
//  Chunks From: spectral-brush
//  Created: 2026-05-10
//  By: Phase A Shader Upgrade Agent
//  Optimized: 2026-05-17 — early exits, textureLoad where possible,
//            branchless alpha, reduced redundant constructors
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735);
  let c = cos(hue);
  let s = sin(hue);
  return color * c + cross(k, color) * s + k * dot(k, color) * (1.0 - c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);

  if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(coord) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;

  let brushSize = u.zoom_params.x * 0.2;
  let spectralShift = u.zoom_params.y * 6.28 + bass;
  let decay = 0.005 + (1.0 - u.zoom_params.z) * 0.1;
  let edgeHardness = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let dist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));

  let prevMask = textureLoad(dataTextureC, coord, 0).r;
  let mask = max(0.0, prevMask - decay);

  // Early exit for untouched pixels: no residual mask and outside brush radius
  if (mask <= 0.0 && dist > brushSize) {
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(dataTextureA, coord, vec4<f32>(0.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coord, original);
    return;
  }

  let innerRadius = brushSize * (1.0 - edgeHardness * 0.9);
  let brushVal = 1.0 - smoothstep(innerRadius, brushSize, dist);
  let finalMask = max(mask, brushVal);

  textureStore(dataTextureA, coord, vec4<f32>(finalMask, 0.0, 0.0, finalMask));

  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let spectral = hueShift(1.0 - original.rgb, spectralShift + time);
  let finalColor = mix(original.rgb, spectral, finalMask);

  let luminance = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = mix(original.a, clamp(luminance + 0.3, 0.0, 1.0), finalMask);

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
}
