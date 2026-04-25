// ═══════════════════════════════════════════════════════════════════
//  Chroma Shift Grid
//  Category: distortion
//  Features: mouse-driven
//  Complexity: Medium-High
//  Upgraded: 2026-04-25
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

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}
fn hash11(p: f32) -> f32 {
  return fract(sin(p * 12.9898) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}
fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let c = hsv.z * hsv.y;
  let h = hsv.x * 6.0;
  let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else              { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(hsv.z - c);
}
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}
fn sdLine(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// ── Chromatic Offsets ────────────────────────────────────────
fn getChromaticOffsets(uv: vec2<f32>, center: vec2<f32>, strength: f32, mode: i32) -> array<vec2<f32>, 3> {
  var offsets: array<vec2<f32>, 3>;
  let dir = uv - center;
  let dist = length(dir);
  let angle = atan2(dir.y, dir.x);
  if (mode == 0) {
    let r = strength * 0.05;
    offsets[0] = -normalize(dir + vec2<f32>(0.0001)) * r * 1.2;
    offsets[1] = vec2<f32>(0.0);
    offsets[2] = normalize(dir + vec2<f32>(0.0001)) * r * 1.2;
  } else if (mode == 1) {
    let r = strength * 0.03;
    let ca = cos(angle + 0.5);
    let sa = sin(angle + 0.5);
    offsets[0] = vec2<f32>(ca, sa) * r;
    offsets[1] = vec2<f32>(0.0);
    offsets[2] = vec2<f32>(-ca, -sa) * r;
  } else {
    let r = strength * 0.04;
    offsets[0] = -dir * r * 1.5;
    offsets[1] = vec2<f32>(0.0);
    offsets[2] = dir * r * 1.5;
  }
  return offsets;
}

// ── Grid Lens Distortion ─────────────────────────────────────
fn distortByGrid(uv: vec2<f32>, cellCenter: vec2<f32>, strength: f32) -> vec2<f32> {
  let local = uv - cellCenter;
  let dist = length(local);
  let k = strength * 0.5;
  let factor = 1.0 + k * dist * dist * 20.0;
  return cellCenter + local * factor;
}

// ── Depth-Aware Strength ─────────────────────────────────────
fn depthAwareStrength(base: f32, uv: vec2<f32>, focal: f32) -> f32 {
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  return base * (1.0 + abs(d - focal) * 3.0);
}

// ── MAIN ─────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let mode = i32(clamp(u.zoom_params.x * 2.0 + 0.5, 0.0, 2.0));
  let animSpeed = u.zoom_params.y;
  let distortStr = u.zoom_params.z;
  let chromaStr = u.zoom_params.w;

  let gridSize = 16.0;
  let gridUV = floor(uv * gridSize);
  let cellCenter = (gridUV + 0.5) / gridSize;

  let distortedUV = distortByGrid(uv, cellCenter, distortStr);

  let animatedStr = chromaStr * (0.7 + 0.3 * sin(time * animSpeed * 5.0));

  let focal = 0.5;
  let finalStr = depthAwareStrength(animatedStr, distortedUV, focal);

  let center = vec2<f32>(0.5);
  let offs = getChromaticOffsets(distortedUV, center, finalStr, mode);

  let cR = textureSampleLevel(readTexture, u_sampler, clamp(distortedUV + offs[0], vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let cG = textureSampleLevel(readTexture, u_sampler, clamp(distortedUV + offs[1], vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, clamp(distortedUV + offs[2], vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  var color = vec4<f32>(cR.r, cG.g, cB.b, max(cR.a, max(cG.a, cB.a)));

  let f = fract(uv * gridSize);
  let edgeDist = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
  let gridAlpha = smoothstep(0.0, 0.15, edgeDist);
  color.a = color.a * (0.6 + 0.4 * gridAlpha);

  textureStore(writeTexture, global_id.xy, color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
