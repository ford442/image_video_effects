// ═══════════════════════════════════════════════════════════════════
//  Flow Sort — Streamline Pixel Sorting
//  Category: simulation
//  Features: temporal-persistence, mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-09
//  Ideas: LIC smear along the field; Asendorf gate on the streamline
//  A packing: ACES display RGBA (C persist is color)
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

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}

fn computeFlowField(uv: vec2<f32>, texelSize: vec2<f32>) -> vec2<f32> {
  let left = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0).rgb);
  let right = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).rgb);
  let up = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0).rgb);
  let down = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).rgb);
  let gx = right - left;
  let gy = down - up;
  return normalize(vec2<f32>(-gy, gx) + vec2<f32>(0.001));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let flowStrength = mix(0.1, 2.0, u.zoom_params.x) * (1.0 + bass * 0.3);
  let sortPasses = i32(mix(1.0, 8.0, u.zoom_params.y));
  let strandPersist = mix(0.0, 0.95, u.zoom_params.z);
  let threshold = mix(0.0, 1.0, u.zoom_params.w);

  var flow = computeFlowField(uv, texelSize);
  let timeRot = sin(time * 0.5) * 0.2;
  let c = cos(timeRot);
  let s = sin(timeRot);
  flow = vec2<f32>(flow.x * c - flow.y * s, flow.x * s + flow.y * c);

  var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let toMouse = uv - mouse;
  let mouseDist = length(toMouse);
  let mouseRadius = 0.2;
  if (mouseDist < mouseRadius && mouseDist > 0.001) {
    let vortex = vec2<f32>(-toMouse.y, toMouse.x) / mouseDist;
    let influence = 1.0 - mouseDist / mouseRadius;
    flow = mix(flow, vortex, influence * flowStrength);
  }

  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 2.0) {
        let toRipple = uv - ripple.xy;
        let dist = length(toRipple);
        if (dist < 0.15 && dist > 0.001) {
          let vortex = vec2<f32>(-toRipple.y, toRipple.x) / dist;
          let influence = (1.0 - rippleAge / 2.0) * (1.0 - dist / 0.15);
          flow = mix(flow, vortex, influence * 0.5);
        }
      }
    }
  }

  let currentColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let currentLum = luminance(currentColor.rgb);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let shouldSort = currentLum > threshold || currentLum < (1.0 - threshold);

  if (!shouldSort) {
    let idle = vec4<f32>(acesToneMap(currentColor.rgb), currentColor.a);
    textureStore(writeTexture, vec2<i32>(coord), idle);
    textureStore(dataTextureA, vec2<i32>(coord), idle);
    textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
    return;
  }

  var sortedColor = currentColor.rgb;
  var sortedLum = currentLum;

  for (var passIndex = 0; passIndex < sortPasses; passIndex = passIndex + 1) {
    let passOffset = f32(passIndex + 1) * texelSize * flowStrength;
    let upstreamUV = clamp(uv - flow * passOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let downstreamUV = clamp(uv + flow * passOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let upstreamColor = textureSampleLevel(readTexture, u_sampler, upstreamUV, 0.0);
    let downstreamColor = textureSampleLevel(readTexture, u_sampler, downstreamUV, 0.0);
    let upstreamLum = luminance(upstreamColor.rgb);
    let downstreamLum = luminance(downstreamColor.rgb);
    let blend = 0.5 / f32(passIndex + 1);
    // Idea 2 — interval gate: skip a swap once luma has left the run.
    if (upstreamLum > sortedLum && upstreamLum > threshold) {
      sortedColor = mix(sortedColor, upstreamColor.rgb, blend);
      sortedLum = luminance(sortedColor);
    }
    if (downstreamLum < sortedLum && downstreamLum < (1.0 - threshold)) {
      sortedColor = mix(sortedColor, downstreamColor.rgb, blend);
      sortedLum = luminance(sortedColor);
    }
  }

  // Idea 1 — LIC smear along the existing field.
  let licA = textureSampleLevel(readTexture, u_sampler, clamp(uv + flow * texelSize * 3.0 * flowStrength, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let licB = textureSampleLevel(readTexture, u_sampler, clamp(uv - flow * texelSize * 3.0 * flowStrength, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  sortedColor = mix(sortedColor, (licA + licB) * 0.5, 0.18 * (0.5 + mids * 0.5));

  let histDims = vec2<i32>(textureDimensions(dataTextureC));
  let prevColor = textureLoad(dataTextureC, historyCoord(uv, histDims), 0).rgb;
  sortedColor = mix(sortedColor, prevColor, strandPersist);

  let sortDelta = abs(sortedLum - currentLum);
  let depthInfluence = 1.0 - depth * 0.5;
  sortedColor = mix(currentColor.rgb, sortedColor, depthInfluence);
  sortedColor = clamp(sortedColor, vec3<f32>(0.0), vec3<f32>(1.0));

  let alpha = clamp(currentColor.a * 0.4 + sortDelta * 0.8 + strandPersist * 0.2 + treble * 0.05, 0.0, 1.0);
  let outCol = vec4<f32>(acesToneMap(sortedColor), alpha);
  textureStore(writeTexture, vec2<i32>(coord), outCol);
  textureStore(dataTextureA, vec2<i32>(coord), outCol);
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
