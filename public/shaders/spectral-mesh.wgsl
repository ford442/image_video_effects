// ═══════════════════════════════════════════════════════════════════
//  Spectral Mesh v2
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: spectral-mesh
//  Created: 2026-05-30
//  By: 4-Agent Shader Upgrade Swarm
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

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn spectralWavelength(t: f32) -> vec3<f32> {
  let wave = 380.0 + t * 400.0;
  var rgb = vec3<f32>(0.0);
  if (wave < 440.0) {
    rgb = vec3<f32>(-(wave - 440.0) / 60.0, 0.0, 1.0);
  } else if (wave < 490.0) {
    rgb = vec3<f32>(0.0, (wave - 440.0) / 50.0, 1.0);
  } else if (wave < 510.0) {
    rgb = vec3<f32>(0.0, 1.0, -(wave - 510.0) / 20.0);
  } else if (wave < 580.0) {
    rgb = vec3<f32>((wave - 510.0) / 70.0, 1.0, 0.0);
  } else if (wave < 645.0) {
    rgb = vec3<f32>(1.0, -(wave - 645.0) / 65.0, 0.0);
  } else {
    rgb = vec3<f32>(1.0, 0.0, 0.0);
  }
  return clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn imageGradient(uv: vec2<f32>, tex: texture_2d<f32>, samp: sampler) -> f32 {
  let eps = 0.002;
  let gx = textureSampleLevel(tex, samp, uv + vec2<f32>(eps, 0.0), 0.0).rgb
         - textureSampleLevel(tex, samp, uv - vec2<f32>(eps, 0.0), 0.0).rgb;
  let gy = textureSampleLevel(tex, samp, uv + vec2<f32>(0.0, eps), 0.0).rgb
         - textureSampleLevel(tex, samp, uv - vec2<f32>(0.0, eps), 0.0).rgb;
  return length(gx) + length(gy);
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
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let densityBase = 6.0 + u.zoom_params.x * 82.0;
  let displacementStrength = u.zoom_params.y * 0.08;
  let mouseRadius = max(0.02, u.zoom_params.z * 0.7);
  let colorShift = u.zoom_params.w;

  let gradMag = imageGradient(uv, readTexture, u_sampler);
  let adaptiveDensity = densityBase * (1.0 + gradMag * 2.5 + audio.x * 0.8);

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let pull = 1.0 - smoothstep(0.0, mouseRadius, dist);

  let attract = (mouse - uv) * pull * 0.06 * (1.0 + audio.y * 0.6);
  let wobble = vec2<f32>(
    sin(uv.y * adaptiveDensity + time * (0.8 + audio.x * 2.0)),
    cos(uv.x * adaptiveDensity * 1.2 - time * (1.1 + audio.y * 1.6))
  ) * displacementStrength * pull;
  let sampleUV = clamp(uv + wobble + attract, vec2<f32>(0.0), vec2<f32>(1.0));

  let foreshorten = 1.0 - depth * 0.35;
  let gridUV = sampleUV * adaptiveDensity * foreshorten;
  let grid = abs(fract(gridUV) - 0.5);
  let lineWidth = 0.03 + audio.z * 0.015;
  let line = 1.0 - smoothstep(0.0, lineWidth, min(grid.x, grid.y));
  let diagonal = 1.0 - smoothstep(lineWidth, lineWidth * 2.75, abs(grid.x - grid.y));

  let triA = 1.0 - smoothstep(0.0, lineWidth, abs(grid.x + grid.y - 0.5));
  let triB = 1.0 - smoothstep(0.0, lineWidth, abs(grid.x + grid.y - 1.5));
  let triLine = max(triA, triB);

  let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let waveParam = colorShift + sampleUV.x * 0.5 + time * 0.04 + audio.y * 0.2 + gradMag;
  let spectral = spectralWavelength(fract(waveParam));

  let glow = line * (0.12 + 0.28 * audio.z) + triLine * (0.06 + 0.14 * audio.x);
  let sss = diagonal * (0.08 + 0.18 * pull);
  var finalColor = mix(baseColor, spectral, line * 0.35 + triLine * 0.18);
  finalColor = finalColor + spectral * (glow + sss);

  let bloom = glow * glow * vec3<f32>(0.45, 0.55, 0.75);
  finalColor = finalColor + bloom;

  finalColor = acesFilm(finalColor * 1.08);

  let meshDensity = clamp((line + triLine + diagonal) * 0.5, 0.0, 1.0);
  let spectralIntensity = clamp(length(spectral), 0.0, 1.0);
  let finalAlpha = clamp(meshDensity * spectralIntensity * depth * 2.2, 0.12, 0.94);

  let depthOut = clamp(mix(depth, 0.20 + line * 0.75 + pull * 0.15, 0.28), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(line, triLine, pull, finalAlpha));
}
