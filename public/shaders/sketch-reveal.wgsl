// ================================================================
//  Sketch Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: sketch-reveal
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
  zoom_params: vec4<f32>,  // x=BrushSize, y=EdgeStrength, z=SketchContrast, w=BrushSoftness
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn sampleLuma(uv: vec2<f32>) -> f32 {
  return luminance(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
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

  let brushSize = mix(0.05, 0.55, u.zoom_params.x);
  let edgeStrength = mix(0.8, 3.0, u.zoom_params.y);
  let sketchContrast = mix(1.0, 3.5, u.zoom_params.z);
  let brushSoftness = mix(0.02, 0.30, u.zoom_params.w);

  let px = vec2<f32>(1.0 / dims.x, 1.0 / dims.y);
  let c = sampleLuma(uv);
  let edgeX = sampleLuma(uv + vec2<f32>(px.x, 0.0)) - sampleLuma(uv - vec2<f32>(px.x, 0.0));
  let edgeY = sampleLuma(uv + vec2<f32>(0.0, px.y)) - sampleLuma(uv - vec2<f32>(0.0, px.y));
  let edge = clamp(length(vec2<f32>(edgeX, edgeY)) * edgeStrength * 4.0, 0.0, 1.0);

  let brushDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let reveal = 1.0 - smoothstep(brushSize, brushSize + brushSoftness, brushDist);
  let hatch = 0.5 + 0.5 * sin((uv.x + uv.y) * 180.0 + time * 2.0 + audio.z * 6.0);
  let sketchBase = clamp(pow(1.0 - c, sketchContrast) + edge * 0.7 + hatch * 0.12, 0.0, 1.0);
  let sketchColor = vec3<f32>(sketchBase) * mix(vec3<f32>(0.88, 0.86, 0.82), vec3<f32>(0.65, 0.75, 1.0), audio.y * 0.25);
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var finalColor = mix(sketchColor, sourceColor + edge * vec3<f32>(0.08, 0.12, 0.18), reveal);
  finalColor = finalColor + vec3<f32>(1.0, 0.85, 0.65) * edge * (1.0 - reveal) * 0.12;

  let finalAlpha = clamp(mix(0.62 + edge * 0.12, 0.96, reveal), 0.38, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.20 + edge * 0.75, 0.24), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(edge, reveal, sketchBase, finalAlpha));
}
