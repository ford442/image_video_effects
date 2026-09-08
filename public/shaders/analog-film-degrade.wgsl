// ═══════════════════════════════════════════════════════════════════
//  Analog Film Degrade
//  Category: image
//  Features: audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-06
//  Ideas: per-channel grain; continuous gate-weave hairlines; C print-through
//  A packing: ACES display RGBA
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
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash11(p: f32) -> f32 {
  return fract(sin(p * 12.9898) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coords = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let grainIntensity = u.zoom_params.x * (1.0 + treble * 0.45);
  let fadeAmount = u.zoom_params.y;
  let scratchFreq = u.zoom_params.z;
  let vignetteStrength = u.zoom_params.w;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var rgb = src.rgb;

  let grainSeed = uv * vec2<f32>(512.0, 480.0) + vec2<f32>(time * 11.0, time * 7.3);
  let gR = (hash21(grainSeed) - 0.5);
  let gG = (hash21(grainSeed * vec2<f32>(1.17, 0.91) + vec2<f32>(17.1, 9.3)) - 0.5);
  let gB = (hash21(grainSeed * vec2<f32>(0.83, 1.29) + vec2<f32>(3.7, 28.4)) - 0.5);
  rgb += vec3<f32>(gR, gG, gB) * grainIntensity;

  let weave = sin(uv.y * (res.y * 0.55) + time * 2.4) * 0.0018 * scratchFreq;
  let weaveUV = clamp(uv + vec2<f32>(weave, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let weaveSample = textureSampleLevel(readTexture, u_sampler, weaveUV, 0.0).rgb;
  rgb = mix(rgb, weaveSample, 0.12 * scratchFreq * (0.4 + treble * 0.6));

  let lineId = uv.x * 90.0 + sin(time * 0.37) * 4.0;
  let hair = smoothstep(0.992, 1.0, hash11(lineId)) * scratchFreq;
  let hairBright = hash11(uv.y * 200.0 + time * 0.11) * 0.35;
  rgb += vec3<f32>(hair * hairBright);

  let dust = hash21(uv * 280.0 + vec2<f32>(time * 0.05, 2.2));
  rgb += vec3<f32>(select(0.0, dust * 0.25, dust < scratchFreq * 0.006));

  let luma = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
  let sepia = vec3<f32>(luma * 1.2, luma * 0.9, luma * 0.6);
  rgb = mix(rgb, sepia, fadeAmount * 0.5);
  rgb = mix(rgb, vec3<f32>(luma), fadeAmount * 0.3);
  rgb = mix(rgb, rgb * 0.6, bass * 0.15 * fadeAmount);

  let prev = textureLoad(dataTextureC, coords, 0);
  rgb = mix(rgb, prev.rgb, 0.10 * fadeAmount);

  let centerDist = length(uv - vec2<f32>(0.5));
  let vignette = smoothstep(0.5, 0.5 - vignetteStrength * 0.5, centerDist);
  rgb *= vignette;

  let display = acesToneMap(clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.4)));
  let damage = clamp(abs(gR) + (1.0 - vignette) + hair, 0.0, 1.0);
  let alpha = clamp(src.a * (1.0 - damage * 0.45) + treble * 0.08, 0.0, 1.0);
  let outCol = vec4<f32>(display, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coords, outCol);
  textureStore(dataTextureA, coords, outCol);
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
