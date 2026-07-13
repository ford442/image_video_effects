// ═══════════════════════════════════════════════════════════════════
//  Solar Wind Ribbons
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba,
//            hdr-aces, oklab-mix, blackbody-plasma,
//            atmospheric-fog, fresnel-rim, volumetric-glow
//  Complexity: Medium-High
//  Created: 2026-05-30
//  Upgraded: 2026-07-13
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn huePreservingClamp(col: vec3<f32>, maxVal: f32) -> vec3<f32> {
    let mx = max(max(col.r, col.g), col.b);
    let scale = min(mx, maxVal) / max(mx, 0.0001);
    return col * scale;
}

fn rgbToOkLab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        0.8189330101, 0.3618667424, -0.1288597137,
        0.0329845436, 0.9293118715, 0.0361456387,
        0.0482003018, 0.2643662691, 0.6338517070
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0 / 3.0));
    return mat3x3<f32>(
        0.2104542553, 0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050, 0.4505937099,
        0.0259040371, 0.7827717662, -0.8086757660
    ) * lms_;
}

fn okLabToRgb(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        1.0, 0.3963377774, 0.2158037573,
        1.0, -0.1055613458, -0.0638541728,
        1.0, -0.0894841775, -1.2914855480
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        4.0767416621, -3.3077115913, 0.2309699292,
        -1.2684380046, 2.6097574011, -0.3413193965,
        -0.0041960863, -0.7034186147, 1.7076147010
    ) * lms;
}

fn blackbody(t: f32) -> vec3<f32> {
    let T = mix(1800.0, 14000.0, clamp(t, 0.0, 1.0));
    let g = clamp(0.0001 * T - 0.05, 0.0, 1.0);
    let b = clamp(0.00004 * (T - 4200.0), 0.0, 1.0);
    return vec3<f32>(1.0, g, b) * (T / 5000.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn ribbonCentre(s: f32, t: f32, twist: f32, bass: f32, idx: f32) -> vec2<f32> {
  let phase = idx * 1.37 + t * 0.3;
  let x = s * 2.0 - 1.0 + sin(s * TAU * twist + phase) * 0.25 * (1.0 + bass * 0.5);
  let y = 0.5 * sin(s * PI + t * 0.5 + phase * 0.7) * (1.0 + bass * 0.2);
  return vec2<f32>(x, y);
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
      0.5 + 0.5 * cos(TAU * hue),
      0.5 + 0.5 * cos(TAU * (hue + 0.33)),
      0.5 + 0.5 * cos(TAU * (hue + 0.67))
    );
    let width = mix(0.01, 0.05, fract(fi * 0.618)) * (1.0 + bass * 0.4);
    var minDist = 1e6;
    for (var si = 0; si < nSamples; si++) {
      let s = f32(si) * ds;
      let cen = ribbonCentre(s, t * speed, twist, bass, fi);
      let d = length(p - cen);
      minDist = min(minDist, d);
    }
    let mask = exp(-minDist * minDist / (width * width * 2.0)) * glowPower;
    let detail = fbm(p * 5.0 + vec2<f32>(t * 0.1, fi * 0.4), 5);
    let edge = exp(-minDist * 4.0) * treble * 2.0;
    col += ribbonCol * mask * (0.7 + 0.3 * detail) * (1.0 + treble * 0.2);
    col += blackbody(0.4 + fi * 0.03 + treble * 0.2) * edge * mask;
  }

  let streakY = fract(p.y * 8.0 + t * 0.15 + bass * 0.1);
  let streak = exp(-abs(streakY - 0.5) * 40.0) * 0.06;
  col += vec3<f32>(0.3, 0.6, 1.0) * streak;

  let radial = length(p);
  let fresnel = pow(1.0 - clamp(radial * 0.6, 0.0, 1.0), 3.0);
  let rim = blackbody(0.55 + mids * 0.2) * fresnel * (1.0 + bass) * 0.5;
  col = col + rim;

  let fog = exp(-radial * (0.8 + bass * 0.3));
  let fogCol = vec3<f32>(0.05, 0.15, 0.35) * (1.0 + mids) * (1.0 - fog);
  col = col + fogCol;

  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  let okPrev = rgbToOkLab(prev * 0.94);
  let okCol = rgbToOkLab(col);
  let okMix = mix(okPrev, okCol, 0.4 + bass * 0.1);
  col = okLabToRgb(okMix);

  col = huePreservingClamp(col, 6.0);
  col = acesToneMap(col * 1.2);

  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.9 + streak * 0.1 + fog * 0.15, 0.0, 1.0);
  let depth = clamp(1.0 - radial * 0.4, 0.0, 1.0);

  let finalColor = vec4<f32>(col, alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
