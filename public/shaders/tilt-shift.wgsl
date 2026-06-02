// ═══════════════════════════════════════════════════════════════════
//  Tilt Shift Miniature v2
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-10
//  Upgraded: 2026-05-30
//  Chunks From: scheimpflug-coc, aces-tonemap, chromatic-aberration
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=FocusWidth, z=Saturation, w=TiltAngle
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  var K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  var p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
  let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let e = 1.0e-10;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  var K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  var p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // Bass drives tilt angle oscillation
  let tiltOsc = sin(u.config.x * 2.0) * bass * 0.1;
  let strength = u.zoom_params.x * 24.0 * (1.0 + bass * 0.15);
  let focusWidth = u.zoom_params.y * 0.25 + 0.04;
  let saturation = u.zoom_params.z * 2.2 * (1.0 + mids * 0.15);
  let tiltAngle = (u.zoom_params.w - 0.5) * 1.2 + tiltOsc;

  // Mouse positions the focal plane
  let focusCenter = u.zoom_config.z;

  // Depth controls local blur radius (shallow DOF)
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Scheimpflug principle: tilted focal plane
  let tiltedDist = abs(uv.y - focusCenter + tiltAngle * (uv.x - 0.5));
  let coc = smoothstep(focusWidth * 0.4, focusWidth * 1.6, tiltedDist) * strength * (0.6 + (1.0 - depth) * 0.8);
  let radius = max(coc, 0.5);

  // Angular blur kernel (golden angle spiral)
  var colorSum = vec3<f32>(0.0);
  var totalWeight = 0.001;
  let samples = 16.0;

  for (var i = 0.0; i < samples; i = i + 1.0) {
    let r = sqrt(i + 0.5) / sqrt(samples) * radius;
    let theta = 2.3999632 * i + tiltAngle * 3.0;
    let offset = vec2<f32>(cos(theta), sin(theta)) * r / resolution;
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    colorSum += textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    totalWeight += 1.0;
  }

  var finalColor = colorSum / totalWeight;

  // Chromatic aberration in out-of-focus areas
  let caStrength = coc * 0.003;
  let rOffset = clamp(uv + vec2<f32>(caStrength, -caStrength * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
  let bOffset = clamp(uv - vec2<f32>(caStrength * 0.5, caStrength), vec2<f32>(0.0), vec2<f32>(1.0));
  finalColor.r = mix(finalColor.r, textureSampleLevel(readTexture, u_sampler, rOffset, 0.0).r, smoothstep(0.5, 4.0, coc));
  finalColor.b = mix(finalColor.b, textureSampleLevel(readTexture, u_sampler, bOffset, 0.0).b, smoothstep(0.5, 4.0, coc));

  // Toy miniature aesthetic: boosted saturation
  var hsv = rgb2hsv(finalColor);
  hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
  finalColor = hsv2rgb(hsv);

  // Vignette on blurred regions
  let edgeDist = length(uv - 0.5);
  let blurVignette = 1.0 - smoothstep(0.3, 0.75, edgeDist) * smoothstep(0.0, 8.0, coc) * 0.4;
  finalColor *= blurVignette;

  // ACES tone mapping
  finalColor = acesToneMap(finalColor);

  // Alpha: in_focus_confidence × saturation_boost × depth
  let focusConf = 1.0 - smoothstep(focusWidth * 0.3, focusWidth * 1.2, tiltedDist);
  let satBoost = hsv.y / max(saturation, 0.001);
  let alpha = clamp(focusConf * satBoost * (0.2 + depth * 0.8), 0.0, 1.0);

  let fc = vec4<f32>(finalColor, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
