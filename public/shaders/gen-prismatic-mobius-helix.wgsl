// ═══════════════════════════════════════════════════════════════════
//  Prismatic Möbius Helix
//  Category: generative
//  Features: möbius-strip SDF helix, thin-film iridescence, spectral
//            edge glow, audio twist, mouse focal orbit, temporal trails
//  Complexity: High
//  Created: 2026-07-12
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn spectral(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

fn thinFilm(hue: f32, view: f32) -> vec3<f32> {
  let n = 1.0 + view * 2.5;
  return spectral(hue + n * 0.15 + sin(view * 12.0) * 0.08);
}

fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

// Möbius strip SDF (IQ-style approximation)
fn sdMobius(p: vec3<f32>, R: f32, w: f32) -> f32 {
  let t = atan2(p.z, p.x);
  let r = length(p.xz);
  let u = t * 0.5;
  let twist = vec3<f32>(cos(u) * (r - R), p.y, sin(u) * (r - R));
  return length(twist) - w;
}

// Helical offset: stack multiple möbius rings along Y
fn mobiusHelixSDF(p: vec3<f32>, coils: f32, R: f32, w: f32, twist: f32) -> f32 {
  var md = 1e9;
  let n = i32(coils);
  for (var i = 0; i < n; i = i + 1) {
    let fi = f32(i);
    let phase = fi * TAU / coils + twist;
    let offset = vec3<f32>(sin(phase) * 0.15, fi * 0.35 - coils * 0.175, cos(phase) * 0.15);
    let q = p - offset;
    let ringR = R + sin(fi * 1.3) * 0.08;
    md = min(md, sdMobius(q, ringR, w));
  }
  return md;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;

  let coilCount = mix(3.0, 8.0, u.zoom_params.x);
  let ribbonWidth = mix(0.04, 0.12, u.zoom_params.y);
  let helixRadius = mix(0.35, 0.75, u.zoom_params.z);
  let iridescence = u.zoom_params.w;

  let aspect = res.x / max(res.y, 1.0);
  var p = vec3<f32>((uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 2.0, 0.0);
  let yaw = (mouse.x - 0.5) * TAU + time * 0.2;
  let pitch = (0.5 - mouse.y) * PI * 0.5;
  p = rotY(rotX(p, pitch), yaw);

  let twist = time * mix(0.3, 1.2, u.zoom_params.x) + bass * 0.5;
  let d = mobiusHelixSDF(p, coilCount, helixRadius, ribbonWidth * 0.5, twist);

  let edge = exp(-abs(d) * 60.0);
  let surface = exp(-max(d, 0.0) * 20.0);
  let viewAngle = atan2(p.z, p.x) / TAU + length(p.xy) * 0.5;
  let hue = fract(viewAngle + time * 0.05 + iridescence + mids * 0.1);

  let film = thinFilm(hue, iridescence + treble * 0.2);
  var color = vec3<f32>(0.015, 0.01, 0.04);
  color += film * edge * (1.5 + bass * 0.6);
  color += spectral(hue + 0.25) * surface * 0.4;

  // Helix trail glow along Y
  let trail = exp(-abs(p.y) * 1.5) * spectral(hue + 0.5) * 0.15 * (1.0 + treble * 0.3);
  color += trail;

  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(color, prev.rgb, 0.05 + mids * 0.02);
  color = acesToneMap(color * (1.1 + bass * 0.15));

  let alpha = clamp(edge * 0.85 + surface * 0.3 + length(trail), 0.0, 1.0);
  let depthOut = clamp(1.0 - d * 2.0, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(d, hue, alpha, edge));
}
