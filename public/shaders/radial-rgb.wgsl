// ═══════════════════════════════════════════════════════════════════
//  Radial RGB — Upgraded with Alpha-Channel Translucency Blending
//  Category: distortion
//  Features: mouse-driven, chromatic-aberration, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-04-25
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
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

fn lensDistort(uv: vec2<f32>, center: vec2<f32>, k1: f32, k2: f32) -> vec2<f32> {
  let d = uv - center;
  let r2 = dot(d, d);
  let r4 = r2 * r2;
  let dist = 1.0 + k1 * r2 + k2 * r4;
  return center + d * dist;
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    let n = sin(p * f * 3.14159) * cos(p.yx * f * 2.71828);
    v = v + a * (n.x * n.y * 0.5 + 0.5);
    a = a * 0.5;
    f = f * 2.0;
  }
  return v;
}

fn smoothVignette(uv: vec2<f32>, intensity: f32, roundness: f32) -> f32 {
  let dist = length(uv - 0.5);
  let inner = 0.3 * roundness;
  let outer = 0.85;
  let v = 1.0 - smoothstep(inner, outer, dist * intensity);
  let softEdge = smoothstep(0.0, inner, dist * intensity);
  return v * softEdge;
}

fn smoothFalloff(x: f32, edge0: f32, edge1: f32) -> f32 {
  let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

fn audioPulse(audio: vec4<f32>, uv: vec2<f32>, intensity: f32) -> f32 {
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let dist = length(uv - 0.5);
  let bassPulse = bass * gaussianMask(dist, 0.25);
  let trebleSparkle = treble * gaussianMask(dist, 0.08);
  return 1.0 + (bassPulse + trebleSparkle) * intensity;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let center = vec2(0.5);
  let k1 = (u.zoom_params.x - 0.5) * 2.0;
  let k2 = (u.zoom_params.y - 0.5) * 2.0;
  let anamorphic = 1.0 + u.zoom_params.z * 2.0;
  let dispersion = u.zoom_params.w * 0.05;

  // ── Single smooth displacement field ──
  var distortedUV = lensDistort(uv, center, k1, k2);
  distortedUV.y = (distortedUV.y - 0.5) / anamorphic + 0.5;

  let mouseDir = normalize(u.zoom_config.yz - 0.5 + vec2(0.0001));
  let displacementMag = length(distortedUV - uv);
  let smoothOffset = (distortedUV - uv) * (1.0 + dispersion * 2.0);
  let displacedUV = uv + smoothOffset;

  // Single RGB sample at displaced UV — no per-channel splitting
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Spectral tint derived from displacement magnitude via wavelength mapping
  let wavelength = mix(520.0, 680.0, clamp(displacementMag * 20.0, 0.0, 1.0));
  let spectralTint = wavelengthToRGB(wavelength);
  let tintStrength = tentAlpha(displacementMag * 8.0) * dispersion * 10.0;
  var color = mix(baseColor, baseColor * spectralTint, tintStrength);

  // Audio-reactive pulse from plasmaBuffer: bass drives brightness, treble adds sparkle
  let audio = plasmaBuffer[0];
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let pulse = 1.0 + bass * 0.3 * gaussianMask(displacementMag, 0.15);
  let sparkle = treble * 0.2 * gaussianMask(displacementMag, 0.08);
  color = color * pulse + vec3<f32>(sparkle);
  color = color * (1.0 + mids * 0.1 * smoothFalloff(displacementMag, 0.0, 0.05));

  // Depth-aware compositing: pull background through in deep regions
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFade = smoothstep(0.0, 0.5, depth);
  let depthMid = smoothstep(0.2, 0.6, depth);
  color = mix(color, baseColor, depthFade * 0.35);
  color = mix(color, color * 1.15, depthMid * mids * 0.5);

  // Multi-zone vignette falloff with smooth inner/outer curves
  let vignetteIntensity = 1.0 + abs(k1) * 0.5;
  let vignette = smoothVignette(uv, vignetteIntensity, 1.0);
  color = color * vignette;

  // Additional smoothstep falloff for edge darkening near frame boundaries
  let edgeX = smoothstep(0.0, 0.08, uv.x) * (1.0 - smoothstep(0.92, 1.0, uv.x));
  let edgeY = smoothstep(0.0, 0.08, uv.y) * (1.0 - smoothstep(0.92, 1.0, uv.y));
  let edgeMask = edgeX * edgeY;
  color = mix(color * 0.85, color, edgeMask);

  // Fresnel-style transmission for glass translucency
  let viewDot = max(1.0 - length(uv - 0.5) * 2.0, 0.0);
  let fresnel = schlickFresnel(viewDot, 0.04);
  let edgeDist = length(uv - 0.5);
  let transmission = 1.0 - smoothstep(0.4, 0.9, edgeDist * (1.0 + abs(k1) * 0.3));
  let lensAlpha = smoothFalloff(displacementMag, 0.0, 0.08) * 0.6;
  let alpha = clamp((transmission + lensAlpha) * (1.0 + displacementMag * 4.0) * (1.0 - fresnel * 0.25), 0.25, 0.95);

  textureStore(writeTexture, global_id.xy, vec4(color, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, global_id.xy, vec4(color, alpha));
  textureStore(dataTextureB, global_id.xy, vec4(displacementMag, bass, depth, alpha));
}
