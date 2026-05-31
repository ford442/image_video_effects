// ═══════════════════════════════════════════════════════════════════
//  Motion Revealer v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, optical-flow, motion-trails, depth-aware, upgraded-rgba
//  Complexity: Very High
//  Chunks From: motion-revealer, structure-tensor, aces-tonemap
//  Created: 2024-01-01
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

  let sensitivity = u.zoom_params.x * (1.0 + bass * 0.5);
  let trailLen = u.zoom_params.y;
  let glowStr = u.zoom_params.z;
  let chromaSep = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.4, 1.0, depth);

  // Current and previous frame for motion detection
  let live = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;

  // Structure tensor for optical flow direction
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
  let flowDir = vec2(cos(theta), sin(theta));

  // Motion magnitude from frame difference
  let diff = length(live - prev);
  let motionMag = diff * (1.0 + lambda * 2.0);

  // Mouse motion mask
  let aspect = resolution.x / resolution.y;
  let mouseDist = length((uv - mouse) * vec2(aspect, 1.0));
  let mouseMask = 1.0 - smoothstep(0.0, 0.4, mouseDist);

  // Motion confidence threshold (bass drives sensitivity)
  let threshold = 0.03 / max(sensitivity, 0.01);
  let motionConfidence = smoothstep(threshold, threshold * 2.0, motionMag + mouseMask * 0.2);

  // Motion trails with spectral chromatic aberration
  var trailR = vec3(0.0);
  var trailG = vec3(0.0);
  var trailB = vec3(0.0);
  var glow = vec3(0.0);
  let steps = 7;
  let maxTrail = trailLen * depthFactor * 0.08;
  for (var i = 0; i < steps; i = i + 1) {
    let t = f32(i) / f32(steps - 1);
    let offset = flowDir * maxTrail * t;
    let rUV = clamp(uv + offset * (1.0 + chromaSep * 0.3), vec2(0.0), vec2(1.0));
    let gUV = clamp(uv + offset, vec2(0.0), vec2(1.0));
    let bUV = clamp(uv + offset * (1.0 - chromaSep * 0.3), vec2(0.0), vec2(1.0));
    trailR = trailR + textureSampleLevel(readTexture, u_sampler, rUV, 0.0).rgb;
    trailG = trailG + textureSampleLevel(readTexture, u_sampler, gUV, 0.0).rgb;
    trailB = trailB + textureSampleLevel(readTexture, u_sampler, bUV, 0.0).rgb;
    let samp = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).rgb;
    let lum = dot(samp, vec3(0.299, 0.587, 0.114));
    glow = glow + samp * smoothstep(0.5, 0.85, lum) * motionMag;
  }
  let invSteps = 1.0 / f32(steps);
  var color = vec3(trailR.r, trailG.g, trailB.b) * invSteps;

  // HDR glow on fast-moving objects
  glow = glow * invSteps * glowStr * 4.0;
  color = color + glow * vec3(1.0, 0.85, 0.7);

  // Motion blur on trails
  color = mix(live * 0.3, color, motionConfidence);

  // ACES tone mapping
  color = aces(color * 1.2);

  let trailIntensity = motionConfidence * depthFactor;
  let alpha = clamp(motionConfidence * trailIntensity * depthFactor, 0.02, 0.96);

  textureStore(writeTexture, coord, vec4(color, alpha));
  textureStore(dataTextureA, coord, vec4(color, alpha));
  textureStore(writeDepthTexture, coord, vec4(depth, 0.0, 0.0, 0.0));
}
