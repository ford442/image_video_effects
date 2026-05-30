// ═══════════════════════════════════════════════════════════════════
//  Protocell Division
//  Category: generative
//  Features: protocell-biology, oil-iridescence, division-animation, smin-blobs, audio-reactive
//  Complexity: High
//  Created: 2026-05-31
//  By: Kimi Code CLI
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

fn h2(p: vec2<f32>) -> f32 {
  let q = fract(p * vec2<f32>(0.1031, 0.1030));
  return fract(dot(q, q + vec2<f32>(33.33)));
}

fn h3(p: vec3<f32>) -> f32 {
  let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  return fract(dot(q, q.yxz + vec3<f32>(33.33)));
}

fn n2(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(h2(i), h2(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(h2(i + vec2<f32>(0.0, 1.0)), h2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var f = 0.0; var a = 0.5; var x = p;
  for(var i = 0; i < 4; i++) { f += a * n2(x); x *= 2.03; a *= 0.5; }
  return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

fn aces(c: vec3<f32>) -> vec3<f32> {
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn cellSDF(uv: vec2<f32>, fi: f32, t: f32, bass: f32, mids: f32, treble: f32, tension: f32, divRate: f32, mouse: vec2<f32>) -> vec2<f32> {
  let hv = h3(vec3<f32>(fi * 7.31, 1.0, 1.0));
  let h2v = h3(vec3<f32>(fi * 3.17, 2.0, 2.0));
  let h3v = h3(vec3<f32>(fi * 5.93, 3.0, 3.0));
  var cx = sin(t * 0.3 + hv * 6.28) * 0.6 + h2v * 0.3;
  var cy = cos(t * 0.25 + h2v * 6.28) * 0.5 + h3v * 0.2;
  let baseR = 0.12 + hv * 0.08;
  let dp = sin(t * divRate * 2.0 + fi * 1.7) * 0.5 + 0.5;
  let div = smoothstep(0.3, 0.7, dp);
  let split = mix(0.0, 0.18 + bass * 0.1, div);
  let vibe = sin(t * 4.0 + fi * 2.1) * 0.015 * treble;
  let md = length(vec2<f32>(cx, cy) - mouse);
  let attract = exp(-md * 2.0) * 0.08;
  cx += (mouse.x - cx) * attract;
  cy += (mouse.y - cy) * attract;
  let warp = fbm(uv * 3.0 + fi * 10.0 + t * 0.1) * tension * (1.0 + mids);
  let r1 = baseR + vibe + warp * 0.02;
  let d1 = length(uv - vec2<f32>(cx - split, cy)) - r1;
  let r2 = baseR * (0.85 + div * 0.15) + vibe + warp * 0.02;
  let d2 = length(uv - vec2<f32>(cx + split, cy)) - r2;
  return vec2<f32>(smin(d1, d2, tension * (1.0 + mids * 0.5)), fi);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if(f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let cellCount = mix(3.0, 8.0, u.zoom_params.x);
  let tension = mix(0.12, 0.5, u.zoom_params.y);
  let iridescence = u.zoom_params.z;
  let divRate = u.zoom_params.w;
  let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(res.x / res.y, 1.0);
  var d = 1000.0;
  var id = 0.0;
  var cid = 0;
  for(var i = 0; i < 8; i++) {
    if(f32(i) >= cellCount) { break; }
    let b = cellSDF(uv, f32(i), t, bass, mids, treble, tension, divRate, mouse);
    if(b.x < d) { d = b.x; id = b.y; cid = i; }
  }
  let e = 0.003;
  let bxp = cellSDF(uv + vec2<f32>(e, 0.0), f32(cid), t, bass, mids, treble, tension, divRate, mouse);
  let bxm = cellSDF(uv - vec2<f32>(e, 0.0), f32(cid), t, bass, mids, treble, tension, divRate, mouse);
  let byp = cellSDF(uv + vec2<f32>(0.0, e), f32(cid), t, bass, mids, treble, tension, divRate, mouse);
  let bym = cellSDF(uv - vec2<f32>(0.0, e), f32(cid), t, bass, mids, treble, tension, divRate, mouse);
  let gx = (bxp.x - bxm.x) / (2.0 * e);
  let gy = (byp.x - bym.x) / (2.0 * e);
  let normal = normalize(vec2<f32>(gx, gy));
  let light = normalize(vec2<f32>(0.3, 0.7));
  let diff = max(dot(normal, light), 0.0);
  let fresnel = pow(1.0 - abs(d) * 6.0, 3.0);
  let film = 1.0 / (1.0 + fresnel * 5.0);
  let hue = fract(film * 2.0 + id * 0.15 + t * 0.05) * 6.283;
  let irid = vec3<f32>(0.5 + 0.5 * cos(hue), 0.5 + 0.5 * cos(hue - 2.094), 0.5 + 0.5 * cos(hue + 2.094));
  let pulse = sin(t * 2.0 + id * 1.3) * 0.5 + 0.5;
  let coreGlow = exp(-abs(d) * 8.0) * pulse * (0.6 + bass * 0.5);
  let shell = exp(-d * d * 900.0) * 2.0;
  let interior = smoothstep(0.0, -0.08, d) * 0.25;
  let thickness = shell + interior;
  var col = irid * iridescence * (diff * 0.7 + 0.3);
  col += vec3<f32>(0.9, 0.95, 0.8) * fresnel * 0.8;
  col += vec3<f32>(0.2, 0.6, 0.4) * coreGlow;
  col += (h2(uv * 43758.5453 + t) - 0.5) * 0.03;
  col = aces(col * 1.5);
  let alpha = clamp(thickness * fresnel * 2.0 + coreGlow * 0.5, 0.0, 1.0);
  let a = clamp(alpha, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(col * a, a));
  textureStore(writeDepthTexture, coord, vec4<f32>(thickness * 0.5, 0.0, 0.0, 0.0));
}
