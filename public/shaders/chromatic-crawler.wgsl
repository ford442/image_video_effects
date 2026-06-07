// ═══════════════════════════════════════════════════════════════════
//  Chromatic Crawler — Upgraded with Alpha-Channel Translucency
//  Category: artistic
//  Features: mouse-driven, temporal-feedback, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// ═══ Math Snippets ═══
fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

fn gaussianMask(dist: f32, sigma: f32) -> f32 {
  return exp(-dist * dist / (2.0 * sigma * sigma));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (lambda < 440.0) { r = (440.0 - lambda) / 60.0; b = 1.0; }
  else if (lambda < 490.0) { g = (lambda - 440.0) / 50.0; b = 1.0; }
  else if (lambda < 510.0) { g = 1.0; b = (510.0 - lambda) / 20.0; }
  else if (lambda < 580.0) { r = (lambda - 510.0) / 70.0; g = 1.0; }
  else if (lambda < 645.0) { r = 1.0; g = (645.0 - lambda) / 65.0; }
  else { r = 1.0; }
  var intensity = 1.0;
  if (lambda < 420.0) { intensity = 0.3 + 0.7 * (lambda - 380.0) / 40.0; }
  else if (lambda > 700.0) { intensity = 0.3 + 0.7 * (780.0 - lambda) / 80.0; }
  return clamp(vec3(r, g, b) * intensity, vec3(0.0), vec3(1.0));
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
  var p3 = vec3<f32>(
    dot(p, vec3<f32>(127.1, 311.7, 74.7)),
    dot(p, vec3<f32>(269.5, 183.3, 246.1)),
    dot(p, vec3<f32>(113.5, 271.9, 124.9))
  );
  p3 = fract(sin(p3) * 43758.5453);
  return p3;
}

fn hash1(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn voronoiRegions(uv: vec2<f32>, time: f32, regionSize: f32) -> vec2<f32> {
  let grid = vec2<f32>(10.0 + regionSize * 20.0, 8.0 + regionSize * 15.0);
  let id = floor(uv * grid);
  let fuv = fract(uv * grid);
  var minDist = 100.0;
  var minPoint = vec2<f32>(0.0);
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let pointId = id + neighbor;
      let rp = hash3(vec3<f32>(pointId.x, pointId.y, time * 0.5));
      let point = neighbor + rp.xy * 0.9;
      let dist = length(point - fuv);
      if (dist < minDist) {
        minDist = dist;
        minPoint = pointId + point / max(grid, vec2<f32>(0.0001));
      }
    }
  }
  return minPoint;
}

fn createCrawlingRegions(uv: vec2<f32>, time: f32, crawlSpeed: f32) -> vec2<f32> {
  let t = time * crawlSpeed;
  let center1 = vec2<f32>(0.5 + sin(t * 0.3) * 0.4, 0.5 + cos(t * 0.2) * 0.4);
  let center2 = vec2<f32>(0.5 + cos(t * 0.4) * 0.3, 0.5 + sin(t * 0.5) * 0.3);
  let center3 = vec2<f32>(0.5 + sin(t * 0.6) * 0.35, 0.5 + cos(t * 0.7) * 0.35);
  let d1 = length(uv - center1);
  let d2 = length(uv - center2);
  let d3 = length(uv - center3);
  let influence1 = smoothstep(0.3, 0.1, d1) * sin(t * 10.0 + uv.x * 20.0) * 0.5 + 0.5;
  let influence2 = smoothstep(0.25, 0.05, d2) * cos(t * 8.0 + uv.y * 15.0) * 0.5 + 0.5;
  let influence3 = smoothstep(0.2, 0.08, d3) * sin(t * 12.0 + (uv.x + uv.y) * 10.0) * 0.5 + 0.5;
  let totalInfluence = influence1 + influence2 + influence3;
  let crawlOffset = vec2<f32>(
    sin(totalInfluence * 20.0 + t * 5.0) * 0.08,
    cos(totalInfluence * 15.0 + t * 3.0) * 0.08
  );
  return uv + crawlOffset;
}

fn hueRotate(color: vec3<f32>, angle: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosA = cos(angle);
  let sinA = sin(angle);
  return color * cosA + cross(k, color) * sinA + k * dot(k, color) * (1.0 - cosA);
}

// Smooth depth blending curve for compositing
fn depthBlend(depth: f32, intensity: f32) -> f32 {
  let near = smoothstep(0.0, 0.25, depth);
  let far = 1.0 - smoothstep(0.5, 1.0, depth);
  return near * far * intensity;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  var uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;

  let crawlSpeed = u.zoom_params.x * 2.0 + 0.5;
  let swapIntensity = u.zoom_params.y;
  let feedbackMix = u.zoom_params.z * 0.4 + 0.2;
  let flashRate = u.zoom_params.w * 20.0 + 5.0;
  let regionSize = u.zoom_config.x;
  let glowAmount = u.zoom_config.y * 0.3;
  let colorModSpeed = u.zoom_config.z * 2.0 + 0.5;
  let depthInf = u.zoom_config.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // ── Single smooth displacement field ──
  let crawledUV = createCrawlingRegions(uv, time, crawlSpeed);
  let region = voronoiRegions(crawledUV, time, regionSize);
  let crawlVec = crawledUV - uv;
  let crawlMag = length(crawlVec);

  // Smooth hue rotation + spectral tint instead of harsh channel swapping
  let regionHash = hash3(vec3<f32>(region.x * 100.0, region.y * 100.0, time * 2.0));
  let hueAngle = (regionHash.x - 0.5) * 3.14159 * 2.0 * swapIntensity;
  let rotatedColor = hueRotate(inputColor, hueAngle);
  let lambda = mix(450.0, 650.0, regionHash.y);
  let spectralTint = wavelengthToRGB(lambda);
  let tintBlend = tentAlpha(crawlMag * 5.0) * swapIntensity;
  var color = mix(rotatedColor, rotatedColor * spectralTint, tintBlend);

  // Depth modulates intensity for compositing awareness
  let depthModIntensity = swapIntensity * (1.0 - depth * depthInf * 0.5);
  color = mix(inputColor, color, depthModIntensity);

  // Temporal feedback trail via dataTextureC for organic persistence
  let prevUV = createCrawlingRegions(uv, time - 0.016, crawlSpeed);
  let prevColor = textureSampleLevel(dataTextureC, u_sampler, clamp(prevUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let animatedMix = feedbackMix + sin(time * 3.0 + uv.x * 5.0) * 0.1;
  color = mix(color, prevColor, animatedMix);

  // Temporal color modulation via smooth oscillators
  let modOsc = vec3<f32>(
    sin(time * colorModSpeed * 2.0 + uv.x * 10.0) * 0.1 + 1.0,
    cos(time * colorModSpeed * 1.7 + uv.y * 8.0) * 0.1 + 1.0,
    sin(time * colorModSpeed * 2.3 + (uv.x + uv.y) * 6.0) * 0.1 + 1.0
  );
  color = color * modOsc;

  // Smooth flash pulse instead of hard binary step
  let flashPhase = time * flashRate + region.x * 10.0 + region.y * 7.0;
  let flash = gaussianMask(fract(flashPhase) - 0.5, 0.12) * 2.0;
  let flashColor = vec3<f32>(1.0, 0.5, 0.8) * flash;
  color = mix(color, color + flashColor, glowAmount * 1.5);

  // Crawling glow with smooth gaussian falloff
  let crawlGlow = smoothstep(0.0, 0.15, crawlMag) * 5.0 * glowAmount;
  let glowColor = vec3<f32>(0.8, 0.4, 1.0) * crawlGlow;
  color = color + glowColor;

  // Audio-reactive enhancement: treble drives sparkle near crawl fronts
  let treble = plasmaBuffer[0].z;
  let bass = plasmaBuffer[0].x;
  color = color * (1.0 + treble * 0.2 * crawlMag * 10.0);
  color = color + vec3<f32>(0.2, 0.1, 0.3) * bass * crawlGlow;

  // Depth-aware compositing: soften edges in deep areas
  let depthSoft = smoothstep(0.2, 0.7, depth);
  color = mix(color, inputColor, depthSoft * 0.25);

  // Alpha = crawl intensity mapped through smooth tent curve
  let alpha = tentAlpha(crawlMag * 4.0) * (0.6 + swapIntensity * 0.4);
  let finalAlpha = clamp(alpha + glowAmount * 0.15, 0.15, 0.9);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(color, finalAlpha));
}
