// ═══════════════════════════════════════════════════════════════════
//  Pixel Stretch Interactive v2
//  Category: image
//  Features: mouse-driven, audio-reactive, anisotropic-stretch, depth-aware, upgraded-rgba
//  Complexity: Very High
//  Chunks From: pixel-stretch-interactive, structure-tensor, aces-tonemap
//  Created: 2026-05-17
//  Upgraded: 2026-05-31
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

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / b, vec3(0.0), vec3(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let texel = 1.0 / resolution;

  let stretchParam = u.zoom_params.x;
  let bloomStr = u.zoom_params.y;
  let grainStr = u.zoom_params.z * 0.1;
  let chromaScale = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.35, 1.0, depth);

  // Structure tensor for edge-directed anisotropic stretch
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let rx = textureSampleLevel(readTexture, u_sampler, uv + vec2(texel.x, 0.0), 0.0).rgb;
  let lx = textureSampleLevel(readTexture, u_sampler, uv - vec2(texel.x, 0.0), 0.0).rgb;
  let ty = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, texel.y), 0.0).rgb;
  let by = textureSampleLevel(readTexture, u_sampler, uv - vec2(0.0, texel.y), 0.0).rgb;
  let gx = (rx - lx) * 0.5;
  let gy = (ty - by) * 0.5;
  let E = dot(gx, gx);
  let G = dot(gy, gy);
  let F = dot(gx, gy);
  let lambda = sqrt((E - G) * (E - G) + 4.0 * F * F);
  let theta = atan2(2.0 * F, E - G + lambda) * 0.5;
  let edgeDir = vec2(cos(theta), sin(theta));
  let edgeAlign = clamp(lambda * 3.0, 0.0, 1.0);

  // Mouse controls stretch direction; bass drives magnitude
  let mouseDir = normalize(uv - mouse + 0.001);
  let stretchDir = mix(mouseDir, edgeDir, 0.55);
  let stretchAmt = stretchParam * (1.0 + bass * 0.8) * depthFactor * edgeAlign;

  // Parallax layering: sample near and far layers with depth offset
  let parallaxNear = textureSampleLevel(readTexture, u_sampler, uv + stretchDir * stretchAmt * 0.3, 0.0).rgb;
  let parallaxFar = textureSampleLevel(readTexture, u_sampler, uv - stretchDir * stretchAmt * 0.15, 0.0).rgb;
  let parallaxMix = mix(parallaxFar, parallaxNear, depth);

  // Chromatic pixel smear along stretch axis
  var accR = vec3(0.0);
  var accG = vec3(0.0);
  var accB = vec3(0.0);
  var bloom = vec3(0.0);
  let steps = 8;
  for (var i = 0; i < steps; i = i + 1) {
    let t = (f32(i) / f32(steps - 1)) - 0.5;
    let offset = stretchDir * stretchAmt * t;
    let rUV = clamp(uv + offset * (1.0 + chromaScale * 0.5), vec2(0.0), vec2(1.0));
    let gUV = clamp(uv + offset, vec2(0.0), vec2(1.0));
    let bUV = clamp(uv + offset * (1.0 - chromaScale * 0.5), vec2(0.0), vec2(1.0));
    accR = accR + textureSampleLevel(readTexture, u_sampler, rUV, 0.0).rgb;
    accG = accG + textureSampleLevel(readTexture, u_sampler, gUV, 0.0).rgb;
    accB = accB + textureSampleLevel(readTexture, u_sampler, bUV, 0.0).rgb;
    let lum = dot(textureSampleLevel(readTexture, u_sampler, gUV, 0.0).rgb, vec3(0.299, 0.587, 0.114));
    let highlight = smoothstep(0.5, 0.9, lum);
    bloom = bloom + vec3(highlight) * lum;
  }
  let invSteps = 1.0 / f32(steps);
  var color = vec3(accR.r, accG.g, accB.b) * invSteps;

  // HDR bloom on stretched highlights
  bloom = bloom * invSteps * bloomStr * 3.0;
  color = color + bloom * vec3(1.0, 0.9, 0.7);

  // Blend with parallax layers
  color = mix(color, parallaxMix, 0.25 * depthFactor);

  // ACES tone mapping
  color = aces(color * 1.15);

  // Film grain
  let grain = (hash12(uv * resolution + fract(time * 0.7)) - 0.5) * grainStr;
  color = clamp(color + grain, vec3(0.0), vec3(1.0));

  let stretchMag = length(stretchAmt);
  let alpha = clamp(stretchMag * edgeAlign * depthFactor, 0.02, 0.96);

  textureStore(writeTexture, coord, vec4(color, alpha));
  textureStore(writeDepthTexture, coord, vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4(color, alpha));
}
