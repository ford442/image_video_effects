// ═══════════════════════════════════════════════════════════════════
//  Neon Pulse Edge
//  Category: lighting-effects
//  Features: audio-reactive, depth-aware, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-11
//  Ideas: gradient-oriented neon rim; treble sub-harmonic strobe on pulse
//  A packing: edge magnitude in C.r for halo reads; ACES display on writeTexture
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
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn historyEdgeAt(uv: vec2<f32>, resolution: vec2<f32>) -> f32 {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0).r;
}

fn softEdgeDist(uv: vec2<f32>, px: vec2<f32>, r: f32, resolution: vec2<f32>) -> f32 {
  var acc = 0.0;
  let steps = 8;
  for (var i = 0; i < steps; i++) {
    let angle = f32(i) / f32(steps) * 6.28318;
    let offset = vec2<f32>(cos(angle), sin(angle)) * r;
    acc += historyEdgeAt(clamp(uv + offset * px, vec2<f32>(0.0), vec2<f32>(1.0)), resolution);
  }
  return acc / f32(steps);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let px = 1.0 / resolution;

  let threshold = u.zoom_params.x * 0.5 + 0.02;
  let glowRadius = u.zoom_params.y * 6.0 + 1.0;
  let pulseSpeed = u.zoom_params.z * 6.0 + 0.5;
  let cycleRate = u.zoom_params.w;

  let hasAudio = arrayLength(&plasmaBuffer) > 0u;
  let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
  let mids = select(0.0, plasmaBuffer[0].y, hasAudio);
  let treble = select(0.0, plasmaBuffer[0].z, hasAudio);
  let audioBoost = 1.0 + bass * 0.6 + treble * 0.2;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-px.x, -px.y), 0.0).rgb;
  let tc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -px.y), 0.0).rgb;
  let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, -px.y), 0.0).rgb;
  let ml = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-px.x, 0.0), 0.0).rgb;
  let mr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb;
  let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-px.x, px.y), 0.0).rgb;
  let bc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb;
  let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, px.y), 0.0).rgb;

  let lum = vec3<f32>(0.299, 0.587, 0.114);
  let gxMag = -dot(tl, lum) - 2.0 * dot(ml, lum) - dot(bl, lum)
            + dot(tr, lum) + 2.0 * dot(mr, lum) + dot(br, lum);
  let gyMag = -dot(tl, lum) - 2.0 * dot(tc, lum) - dot(tr, lum)
            + dot(bl, lum) + 2.0 * dot(bc, lum) + dot(br, lum);

  let edgeMag = sqrt(gxMag * gxMag + gyMag * gyMag);
  let edgeAngle = atan2(gyMag, gxMag);
  let gradLen = max(length(vec2<f32>(gxMag, gyMag)), 0.0001);
  let gradNorm = vec2<f32>(gxMag, gyMag) / gradLen;

  let hue = fract(edgeAngle / 6.28318 + time * pulseSpeed * 0.02 + cycleRate * 0.3 + bass * 0.15);
  let sat = 0.8 + treble * 0.15;
  let neonColor = hsv2rgb(vec3<f32>(hue, sat, 1.0));

  let coreGlow = softEdgeDist(uv, px, 1.5, resolution);
  let haloGlow = softEdgeDist(uv, px, glowRadius, resolution);
  let diffuseGlow = softEdgeDist(uv, px, glowRadius * 2.8, resolution);

  let depthFactor = 1.0 + depth * 1.2;

  let mouse = u.zoom_config.yz;
  var mouseFactor = 1.0;
  let hasMouse = mouse.x >= 0.0 && mouse.x <= 1.0 && mouse.y >= 0.0 && mouse.y <= 1.0;
  let mDist = length((uv - mouse) * vec2<f32>(resolution.x / resolution.y, 1.0));
  mouseFactor = select(1.0, 1.0 + (1.0 - smoothstep(0.0, 0.25, mDist)) * 1.5, hasMouse);

  let subHarmonic = sin(time * pulseSpeed * 2.6 * (1.0 + treble * 0.85));
  let pulse = 0.7 + 0.3 * sin(time * pulseSpeed * (1.0 + bass)) * (0.65 + 0.35 * subHarmonic);

  var emission = vec3<f32>(0.0);
  let isEdge = step(threshold, edgeMag);

  // Gradient-oriented neon rim: sample emission along Sobel normal
  let rimOffset = gradNorm * px * (1.2 + glowRadius * 0.08);
  let rimUV = clamp(uv + rimOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let rimMag = sqrt(
    pow(dot(textureSampleLevel(readTexture, u_sampler, rimUV + vec2<f32>(px.x, 0.0), 0.0).rgb, lum)
      - dot(textureSampleLevel(readTexture, u_sampler, rimUV - vec2<f32>(px.x, 0.0), 0.0).rgb, lum), 2.0)
    + pow(dot(textureSampleLevel(readTexture, u_sampler, rimUV + vec2<f32>(0.0, px.y), 0.0).rgb, lum)
      - dot(textureSampleLevel(readTexture, u_sampler, rimUV - vec2<f32>(0.0, px.y), 0.0).rgb, lum), 2.0)
  );
  let rimHue = fract(hue + rimMag * 0.35);
  let rimColor = hsv2rgb(vec3<f32>(rimHue, sat * 0.95, 1.0));
  emission += rimColor * smoothstep(threshold * 0.7, threshold * 1.4, rimMag) * pulse * 0.45 * depthFactor;

  emission += neonColor * edgeMag * pulse * depthFactor * mouseFactor * audioBoost * 1.8 * isEdge;

  let haloColor = hsv2rgb(vec3<f32>(fract(hue + 0.05), sat * 0.7, 1.0));
  emission += haloColor * coreGlow * depthFactor * audioBoost * 0.6;
  emission += neonColor * haloGlow * depthFactor * audioBoost * 0.25;
  emission += haloColor * diffuseGlow * 0.08 * audioBoost;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let edgeDim = 1.0 - isEdge * 0.4;
  let hdr = baseColor * edgeDim + emission;

  let glowStrength = clamp(length(emission) * 0.5, 0.0, 1.0);
  let display = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), glowStrength);

  textureStore(writeTexture, coord, display);
  textureStore(dataTextureA, coord, vec4<f32>(edgeMag, display.g, display.b, display.a));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
