// ═══════════════════════════════════════════════════════════════════
//  Liquid Glitch (Upgraded Batch 51)
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-15
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  return clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let blockPixels = mix(8.0, 48.0, u.zoom_params.x);
  let corruption = u.zoom_params.y;
  let burstStrength = mix(0.005, 0.065, u.zoom_params.z);
  let chromaShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let rawDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(1.0, 0.35, clamp(rawDepth, 0.0, 1.0));

  // Dual continuous motion: Fluid velocity advection + Quantized Bernoulli slip bands
  let blockSize = vec2<f32>(blockPixels) / resolution;
  let block = floor(uv / blockSize);
  let blockUV = (block + 0.5) * blockSize;

  let timeQuantum = floor(time * (6.0 + audio.z * 14.0));
  let blockRand = hash21(block + vec2<f32>(timeQuantum * 0.13, timeQuantum * 0.29));
  let rowRand = hash21(vec2<f32>(block.y, floor(time * 8.5)));

  // Continuous fluid stream
  let pAspect = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let fluidStream = vec2<f32>(
    sin(pAspect.y * 10.0 + time * 1.1 + audio.x * 1.8),
    cos(pAspect.x * 8.0 - time * 0.95 + audio.y * 1.4)
  ) * (0.002 + corruption * 0.004) * depthFactor;

  var glitchOffset = fluidStream + vec2<f32>((blockRand - 0.5) * corruption * 0.045, sin(block.x + time * 3.5) * corruption * 0.003);
  let isBadSignal = step(0.86 - corruption * 0.18 - audio.z * 0.15, rowRand);
  glitchOffset.x += (rowRand - 0.5) * isBadSignal * (0.035 + corruption * 0.14);

  // Interactive pointer drag / vortex glitch tearing
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w;
  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let dragCore = exp(-mouseDist * 6.0);
  let dragWake = vec2<f32>(-mouseDelta.y, mouseDelta.x) * (dragCore / mouseDist) * (0.01 + corruption * 0.02) * (1.0 + isMouseDown * 2.5);
  glitchOffset += vec2<f32>(dragWake.x / aspect, dragWake.y);

  // 50-ripple shockwaves with localized digital shard bursts
  var burstMask = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age > 0.0 && age < 2.0) {
      let rDelta = (blockUV - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let ring = step(0.52, sin(rDist * 65.0 - age * 22.0));
      let envelope = (1.0 - smoothstep(0.0, 2.0, age)) * exp(-rDist * 4.5);
      let rDir = rDelta / rDist;
      let shard = (hash21(block + f32(i) * 1.37) - 0.5) * 2.0;

      glitchOffset += vec2<f32>(rDir.x / aspect, rDir.y) * ring * envelope * shard * burstStrength * 1.8;
      burstMask += ring * envelope;
    }
  }

  // Chromatic glitch aberration channels
  let smear = vec2<f32>(glitchOffset.x * (1.0 + audio.x * 0.75), glitchOffset.y);
  let split = vec2<f32>(0.0035 + chromaShift * 0.022 + audio.y * 0.008, 0.0);

  let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(uv + smear + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sampleG = textureSampleLevel(readTexture, u_sampler, clamp(uv + smear, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(uv + smear - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  // Exact-load temporal state feedback from dataTextureC
  let histUV = clamp(uv - smear * 0.4, vec2<f32>(0.0), vec2<f32>(1.0));
  let histCoord = clamp(vec2<i32>(floor(histUV * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  let scanline = 0.88 + 0.12 * sin(f32(gid.y) * 3.14159 + time * (9.0 + audio.z * 12.0));
  let digitalTint = vec3<f32>(0.1, 0.0, 0.16) * blockRand * (corruption + audio.y * 0.8);
  let currentRGB = vec3<f32>(sampleR.r, sampleG.g, sampleB.b) * scanline + digitalTint;

  let persistence = clamp(0.12 + corruption * 0.38 - burstMask * 0.1, 0.04, 0.52) * history.a;
  var rgb = mix(currentRGB, history.rgb, persistence);
  rgb = acesToneMapping(rgb);

  let sourceAlpha = max(sampleR.a, max(sampleG.a, sampleB.a));
  let energy = clamp(length(smear) * 20.0 + burstMask * 0.4 + isBadSignal * 0.25, 0.0, 1.0);
  let finalAlpha = clamp(sourceAlpha * (0.75 + (1.0 - corruption) * 0.22) + energy * 0.22, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, finalAlpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let outDepth = clamp(rawDepth + burstMask * 0.04 - length(smear) * 0.2, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
