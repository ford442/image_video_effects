// ═══════════════════════════════════════════════════════════════════
//  Rose FBM Kaleidoscope
//  Category: distortion
//  Features: audio-reactive, audio-driven
//  Complexity: High
//  Upgraded by: Optimizer Agent
//  Date: 2026-05-03
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

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0; var a = 0.5;
  var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  var pos = p;
  for(var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise2D(pos);
    pos = rot * pos * 2.0 + 100.0;
    a = a * 0.5;
  }
  return v;
}
fn superellipseMask(d: vec2<f32>, a: f32, b: f32, n: f32) -> f32 {
  let xn = pow(abs(d.x) / max(a, 0.001), n);
  let yn = pow(abs(d.y) / max(b, 0.001), n);
  return 1.0 - smoothstep(0.8, 1.0, xn + yn);
}
fn roseModulation(angle: f32, n: f32, a: f32) -> f32 {
  return a * abs(cos(n * angle * 0.5));
}
fn lissajousOffset(t: f32, A: f32, B: f32, a: f32, b: f32, delta: f32) -> vec2<f32> {
  return vec2<f32>(A * sin(a * t + delta), B * sin(b * t));
}
fn epicycloidPoint(t: f32, R: f32, r: f32) -> vec2<f32> {
  let k = (R + r) / max(r, 0.001);
  return vec2<f32>((R + r) * cos(t) - r * cos(k * t), (R + r) * sin(t) - r * sin(k * t));
}
fn hypocycloidPoint(t: f32, R: f32, r: f32) -> vec2<f32> {
  let k = (R - r) / max(r, 0.001);
  return vec2<f32>((R - r) * cos(t) + r * cos(k * t), (R - r) * sin(t) - r * sin(k * t));
}
fn gaborTexture(p: vec2<f32>, freq: f32, angle: f32) -> f32 {
  let g = exp(-dot(p, p) * 12.0);
  let ca = cos(angle);
  let sa = sin(angle);
  return g * cos(freq * (p.x * ca + p.y * sa));
}
fn hypocycloidRadius(angle: f32, time: f32, speed: f32) -> f32 {
  let t = angle + time * speed * 0.5;
  let p = hypocycloidPoint(t, 0.5, 0.1);
  return length(p) * 0.42;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let audio = u.zoom_config.x;
  let audioBass = plasmaBuffer[0].x;
  let audioTreble = plasmaBuffer[0].z;
  let audioReact = 1.0 + audio * 0.3 + audioBass * 0.2;

  let segments = max(u.zoom_params.x * 16.0, 4.0);
  let speed = u.zoom_params.y * 0.5;
  let zoom = max(u.zoom_params.z, 0.1);
  let edgeSoft = max(u.zoom_params.w * 0.05, 0.0001);

  // Centered coordinates for mirror operations
  var centered = uv - 0.5;
  let radius = length(centered);
  var angle = atan2(centered.y, centered.x);

  // 1. Lissajous displacement field (breathing wobble)
  let liss = lissajousOffset(time * speed, 0.025, 0.02, 3.0, 2.0, 0.5);
  centered = centered + liss * audioReact;
  let dispRadius = length(centered);
  var dispAngle = atan2(centered.y, centered.x);

  // 2. FBM turbulent mirror distortion (organic liquid-like)
  let turb = fbm(vec2<f32>(dispRadius * 5.0, dispAngle * 3.0) + time * 0.4, 4);
  dispAngle = dispAngle + turb * 0.12 * audioReact;

  // 3. Rose curve segment boundaries (petal-shaped mirrors)
  let roseK = segments;
  let roseA = 0.25 * audioReact;
  let roseWarp = roseModulation(dispAngle, roseK, roseA);
  let warpedAngle = dispAngle + roseWarp * sin(dispRadius * 8.0);

  // Normalize angle to positive range for consistent mirroring
  let normAngle = select(warpedAngle, warpedAngle + 6.2831853, warpedAngle < 0.0);

  // Standard angular mirror within rose-warped segments
  let segAngle = 6.2831853 / segments;
  let segIndex = floor(normAngle / segAngle);
  let segFrac = fract(normAngle / segAngle);
  let mirrorFrac = select(segFrac, 1.0 - segFrac, abs(segIndex % 2.0) > 0.5);
  let mirrorAngle = mirrorFrac * segAngle + segIndex * segAngle;

  // 4. Epicycloid inner pattern distortion (spirograph wobble)
  let epiT = time * speed + dispRadius * 12.0 + audioTreble * 2.0;
  let epi = epicycloidPoint(epiT, 0.025, 0.008) * audioReact;
  let zoomed = vec2<f32>(cos(mirrorAngle), sin(mirrorAngle)) * dispRadius / zoom + epi;

  // 5. Superellipse zoom window (squircle aperture)
  let sqN = mix(2.0, 10.0, u.zoom_params.w);
  let sqMask = superellipseMask(zoomed, 0.55, 0.55, sqN);
  let finalUV = zoomed + 0.5;

  // Edge fade for sampled texture bounds
  let fadeX = smoothstep(0.0, edgeSoft, finalUV.x) * smoothstep(1.0, 1.0 - edgeSoft, finalUV.x);
  let fadeY = smoothstep(0.0, edgeSoft, finalUV.y) * smoothstep(1.0, 1.0 - edgeSoft, finalUV.y);
  let edgeFade = fadeX * fadeY;

  // 6. Gabor anisotropic segment texture (fabric-like interiors)
  let segCenter = vec2<f32>(cos(segIndex * segAngle), sin(segIndex * segAngle)) * 0.25;
  let gabor = gaborTexture(centered - segCenter, 10.0, segIndex * segAngle * 0.5) * 0.12;
  let gaborTint = vec3<f32>(0.9, 0.85, 0.7) * gabor * audioReact;

  // 7. RGB channel separation per segment index
  let segMod = f32(segIndex % 3.0);
  let shift = edgeSoft * 0.4 * segMod;
  let rUV = finalUV + vec2<f32>(shift, 0.0);
  let gUV = finalUV;
  let bUV = finalUV - vec2<f32>(shift, 0.0);
  let rSamp = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let gSamp = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let bSamp = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var rgb = vec3<f32>(rSamp, gSamp, bSamp) + gaborTint;

  // 8. Hypocycloid outer frame mask (star/flower aperture)
  let frameR = hypocycloidRadius(angle, time, speed);
  let frameMask = 1.0 - smoothstep(frameR - 0.03, frameR, radius);

  // Compose color with superellipse and frame masking
  rgb = rgb * edgeFade * sqMask * frameMask;

  // Edge glow intensity stored in alpha
  let segmentEdge = abs(sin(mirrorFrac * 3.14159265));
  let edgeGlow = (1.0 - edgeFade) * 1.5 + segmentEdge * 0.25 * audio;
  let alpha = edgeFade * frameMask + edgeGlow * edgeSoft * 8.0;

  let finalColor = vec4<f32>(rgb, clamp(alpha, 0.0, 1.0));
  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
