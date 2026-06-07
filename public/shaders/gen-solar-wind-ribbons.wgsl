// ═══════════════════════════════════════════════════════════════════
//  Solar Wind Ribbons
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium-High
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
//  Streaming ribbons of magnetised plasma — coronal mass ejection
//  caught mid-flight, woven into curtains of aurora.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=RibbonCount, y=Twist, z=Speed, w=Glow
  ripples: array<vec4<f32>, 50>,
};

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0; var amp = 0.5; var pp = p;
  for (var i = 0u; i < 5u; i++) {
    v += amp * noise2(pp); pp *= 2.0; amp *= 0.5;
  }
  return v;
}

// Parametric ribbon centre-line at parameter s ∈ [0,1]
fn ribbonCentre(s: f32, t: f32, twist: f32, bass: f32, idx: f32) -> vec2<f32> {
  let phase = idx * 1.37 + t * 0.3;
  let x = s * 2.0 - 1.0 + sin(s * 6.28 * twist + phase) * 0.25 * (1.0 + bass * 0.5);
  let y = 0.5 * sin(s * 3.14159 + t * 0.5 + phase * 0.7) * (1.0 + bass * 0.2);
  return vec2<f32>(x, y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / vec2<f32>(dims);
  let t = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let nRibbons  = i32(mix(3.0, 14.0, u.zoom_params.x));
  let twist     = mix(0.5, 4.0, u.zoom_params.y);
  let speed     = mix(0.1, 1.2, u.zoom_params.z);
  let glowPower = mix(0.5, 3.0, u.zoom_params.w) * (1.0 + mids * 0.3);

  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p -= mouse * 0.3 * u.zoom_config.w;

  var col = vec3<f32>(0.0);
  let nSamples = 64;
  let ds = 1.0 / f32(nSamples);

  for (var ri = 0; ri < nRibbons; ri++) {
    let fi = f32(ri);
    let hue = fract(fi / f32(nRibbons) + t * 0.04 + bass * 0.1);
    let ribbonCol = vec3<f32>(
      0.5 + 0.5 * cos(6.2832 * hue),
      0.5 + 0.5 * cos(6.2832 * (hue + 0.33)),
      0.5 + 0.5 * cos(6.2832 * (hue + 0.67))
    );
    let width = mix(0.01, 0.05, fract(fi * 0.618)) * (1.0 + bass * 0.4);
    var minDist = 1e6;
    for (var si = 0; si < nSamples; si++) {
      let s = f32(si) * ds;
      let cen = ribbonCentre(s, t * speed, twist, bass, fi);
      let d = length(p - cen);
      if (d < minDist) { minDist = d; }
    }
    let mask = exp(-minDist * minDist / (width * width * 2.0)) * glowPower;
    // Noise-perturbed brightness along ribbon
    let detail = fbm(p * 5.0 + vec2<f32>(t * 0.1, fi * 0.4));
    col += ribbonCol * mask * (0.7 + 0.3 * detail) * (1.0 + treble * 0.2);
  }

  // Stellar wind background: faint horizontal streaks
  let streakY = fract(p.y * 8.0 + t * 0.15 + bass * 0.1);
  let streak = exp(-abs(streakY - 0.5) * 40.0) * 0.06;
  col += vec3<f32>(0.3, 0.6, 1.0) * streak;

  col = aces(col);
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.9 + streak * 0.1, 0.0, 1.0);
  let depth = clamp(1.0 - length(p) * 0.4, 0.0, 1.0);

  let finalColor = vec4<f32>(acesToneMap(col * 1.1), alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
