// ═══════════════════════════════════════════════════════════════════
//  Film Gate Weave v2
//  Category: retro-glitch
//  Features: temporal-frame-jitter, dust-scratches, color-flicker, audio-reactive-jitter,
//            upgraded-rgba, gate-flutter, registration-jitter, scratch-persistence,
//            splice-tape, chromatic-aberration
//  Complexity: Very High
//  Chunks From: film-gate-weave.wgsl v1
//  Created: 2026-05-31
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn dyeCloudGrain(uv: vec2<f32>, frameId: f32, grainSize: f32) -> f32 {
  let g1 = hash21(uv * 300.0 * grainSize + frameId * 0.3);
  let g2 = hash21(uv * 700.0 * grainSize + frameId * 0.7 + 17.3);
  let g3 = hash21(uv * 1200.0 * grainSize + frameId * 1.1 + 43.1);
  return g1 * 0.5 + g2 * 0.3 + g3 * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let weaveAmount = u.zoom_params.x * 0.025;
  let dustAmount = u.zoom_params.y;
  let scratchAmount = u.zoom_params.z;
  let flickerAmount = u.zoom_params.w;

  let fps = 24.0;
  let frameId = floor(time * fps);
  let subFrame = fract(time * fps);

  let gateFlutter = sin(frameId * 0.47 + bass * 3.0) * 0.5 + 0.5;
  let regJitter = (hash21(vec2<f32>(frameId, 0.0)) - 0.5) * weaveAmount * 0.4;
  let intermittent = smoothstep(0.3, 0.7, gateFlutter) * weaveAmount * 0.3;
  let weave = sin(frameId * 0.37) * weaveAmount + regJitter + intermittent;

  let audioJitter = (hash21(vec2<f32>(time * fps, uv.y * 150.0)) - 0.5) * weaveAmount * bass * 0.6;
  let mouseScrub = select(0.0, (mousePos.x - 0.5) * 0.02, mouseDown > 0.5);

  let sampleUV = clamp(uv + vec2<f32>(mouseScrub, weave + audioJitter), vec2<f32>(0.0), vec2<f32>(1.0));

  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  let perfX = fract(uv.x * 4.0);
  let perfY = fract(uv.y * 30.0);
  let perfHole = step(0.15, perfX) * step(0.35, perfY) * step(perfY, 0.65);
  let perfJitter = (hash21(vec2<f32>(floor(uv.x * 4.0), frameId)) - 0.5) * weaveAmount * 0.2;
  let perfMask = perfHole * smoothstep(0.0, 0.02, abs(perfJitter));

  let grainSize = mix(1.5, 0.6, depth);
  let grain = (dyeCloudGrain(uv, frameId, grainSize) - 0.5) * 0.08 * (1.0 + treble * 0.3);

  let dustUV = uv * resolution * 0.4;
  let dustNoise = hash21(floor(dustUV) + frameId * 0.15);
  let dust = step(1.0 - dustAmount * 0.04, dustNoise) * 0.25;

  let prevScratch = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).g;
  let scratchLine = hash21(vec2<f32>(floor(uv.x * resolution.x * 0.3), frameId));
  let newScratch = step(1.0 - scratchAmount * 0.015, scratchLine) * smoothstep(0.0, 0.08, uv.y) * smoothstep(1.0, 0.92, uv.y);
  let scratch = mix(prevScratch * 0.85, newScratch, 0.3);

  let hairLine = hash21(vec2<f32>(floor(uv.y * resolution.y), frameId * 0.5));
  let hair = step(1.0 - dustAmount * 0.008, hairLine) * 0.15 * smoothstep(0.1, 0.5, uv.x) * smoothstep(0.9, 0.5, uv.x);

  let splicePos = 0.33 + hash21(vec2<f32>(7.0, floor(time * 0.1))) * 0.34;
  let spliceTape = smoothstep(0.003, 0.0, abs(uv.y - splicePos)) * 0.4 * step(0.2, fract(time * 0.1));

  let flicker = 1.0 + (hash21(vec2<f32>(frameId, 0.0)) - 0.5) * flickerAmount * 0.35;
  let rFlicker = flicker + (hash21(vec2<f32>(frameId, 1.0)) - 0.5) * flickerAmount * 0.25 * treble;
  let bFlicker = flicker + (hash21(vec2<f32>(frameId, 2.0)) - 0.5) * flickerAmount * 0.25 * bass;

  let lensBreathe = 1.0 + sin(subFrame * 6.283) * weaveAmount * 0.5;
  let chromR = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.003 * lensBreathe, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let chromB = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(0.003 * lensBreathe, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  var rgb = vec3<f32>(chromR * rFlicker, color.g * flicker, chromB * bFlicker);
  rgb = rgb + vec3<f32>(grain);
  rgb = rgb + vec3<f32>(dust) + vec3<f32>(scratch * 0.6) + vec3<f32>(hair);
  rgb = rgb + vec3<f32>(0.9, 0.85, 0.7) * spliceTape;

  let sepia = vec3<f32>(1.0, 0.88, 0.72) * mids * 0.08;
  rgb = rgb + sepia;

  let weaveConfidence = 1.0 - abs(weave) / (weaveAmount + 0.001);
  let grainDensity = abs(grain) * 12.0 + dust + scratch + hair;

  rgb = acesToneMap(rgb * 1.05);

  let alpha = clamp(weaveConfidence * grainDensity * depth + color.a * 0.3 + bass * 0.04, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(rgb.r, scratch, 0.0, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
