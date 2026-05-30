// ================================================================
//  Cyber Organic Scanner
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: cyber-organic
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
  zoom_params: vec4<f32>,  // x=ScanSpeed, y=OrganicScale, z=RevealRadius, w=PulseSpeed
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = p;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + a * hash12(floor(f) + fract(f));
    f = f * 2.1 + 7.13;
    a = a * 0.5;
  }
  return v;
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

  let scanSpeed = 0.15 + u.zoom_params.x * 4.0;
  let organicScale = mix(2.0, 14.0, u.zoom_params.y);
  let revealRadius = mix(0.10, 0.80, u.zoom_params.z);
  let pulseSpeed = 0.2 + u.zoom_params.w * 5.0;

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let reveal = 1.0 - smoothstep(0.0, revealRadius, dist);
  let field = fbm(uv * organicScale + vec2<f32>(time * 0.12, -time * 0.09));
  let vein = 1.0 - smoothstep(0.12, 0.32, abs(field - 0.5));
  let scan = 0.5 + 0.5 * sin(uv.y * 40.0 + time * scanSpeed * 6.0 + field * 6.28318);
  let pulse = 0.5 + 0.5 * sin(time * pulseSpeed * 6.0 + field * 12.0);
  let warp = vec2<f32>(scan - 0.5, pulse - 0.5) * 0.03 * (0.4 + audio.x + reveal);
  let sampleUV = clamp(uv + warp, vec2<f32>(0.0), vec2<f32>(1.0));

  var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let bioTint = mix(vec3<f32>(0.05, 0.95, 0.75), vec3<f32>(0.55, 1.0, 0.15), pulse * 0.55);
  finalColor = mix(finalColor, finalColor * 0.55 + bioTint * (0.45 + audio.z * 0.2), reveal * 0.55 + vein * 0.15);
  finalColor = finalColor + bioTint * vein * (0.05 + 0.16 * audio.y);

  let finalAlpha = clamp(0.68 + reveal * 0.18 + vein * 0.10, 0.42, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.24 + reveal * 0.56 + vein * 0.18, 0.32), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(vein, scan, reveal, finalAlpha));
}
