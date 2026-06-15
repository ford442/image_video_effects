// ═══════════════════════════════════════════════════════════════════
//  mosaic-reveal — Visualist Upgrade
//  Category: distortion
//  Features: upgraded-rgba, depth-aware, mosaic, interactive-reveal,
//            mouse-driven, hex-grid, flood-fill-reveal, audio-reactive,
//            oklab-mixing, temporal-feedback, aces-tone-map
//  Upgraded: 2026-06-14
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash & noise ──────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < oct; i++) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

// ── OkLab perceptual mixing ───────────────────────────────────────
fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
  let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
  let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
  let l_ = pow(l, 1.0 / 3.0);
  let m_ = pow(m, 1.0 / 3.0);
  let s_ = pow(s, 1.0 / 3.0);
  return vec3<f32>(
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
  );
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  let m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  let s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  let l = l_ * l_ * l_;
  let m = m_ * m_ * m_;
  let s = s_ * s_ * s_;
  return vec3<f32>(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  );
}

fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

// ── Color science & dither ────────────────────────────────────────
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  let lum = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  let s = min(1.0, max_lum / max(lum, 1e-4));
  return c * s;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  if (t <= 66.0) { r = 1.0; }
  else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
  if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
  else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
  if (t >= 66.0) { b = 1.0; }
  else if (t <= 19.0) { b = 0.0; }
  else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
  return vec3<f32>(r, g, b);
}

// ── Hex grid center ───────────────────────────────────────────────
fn hexCenter(uv: vec2<f32>, size: f32) -> vec2<f32> {
  let s = vec2<f32>(1.0, 1.7320508);
  let h = s * 0.5;
  let a = (uv - s * floor(uv / s)) - h;
  let b = ((uv - h) - s * floor((uv - h) / s)) - h;
  let g = select(a, b, dot(a, a) > dot(b, b));
  let hex = (uv - g);
  return (floor(hex) + 0.5) / size;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let aspectVec = vec2<f32>(res.x / res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let cellSize = mix(12.0, 160.0, u.zoom_params.x);
  let revealSpeed = (u.zoom_params.y * 2.0 + 0.2) * (1.0 + mids * 0.8);
  let edgeGlow = u.zoom_params.z * (1.0 + treble * 0.7);
  let isHex = u.zoom_params.w > 0.5;

  let mouse = u.zoom_config.yz;
  let mouseDist = distance((uv01 - mouse) * aspectVec, vec2<f32>(0.0));

  // Tile UV center (square or hex)
  let tile = uv01 * cellSize;
  let sqCenter = (floor(tile) + 0.5) / cellSize;
  let hxCenter = hexCenter(uv01 * cellSize, cellSize);
  let tileCenter = select(sqCenter, hxCenter, isHex);

  var colMosaic = textureSampleLevel(readTexture, non_filtering_sampler, tileCenter, 0.0).rgb;
  var colFull = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  // Organic reveal boundary
  let warp = (fbm(uv01 * cellSize * 0.4 + time * 0.15, 3) - 0.5) * 0.06;
  let bassPulse = 1.0 + bass * 0.35;
  let revealRadius = clamp(fract(time * revealSpeed * bassPulse) * 0.85 + warp, 0.0, 1.0);
  let revealMask = 1.0 - smoothstep(revealRadius - 0.05, revealRadius + 0.05, mouseDist);

  // Edge mask for rim light
  let edgeMask = smoothstep(revealRadius - 0.12, revealRadius - 0.03, mouseDist)
               * smoothstep(revealRadius + 0.12, revealRadius + 0.03, mouseDist);

  // Perceptually clean mosaic ↔ full transition
  var color = mixOkLab(colMosaic, colFull, revealMask);

  // Audio-reactive blackbody rim glow
  let temp = 2200.0 + treble * 5500.0 + mids * 1200.0;
  color = color + blackbodyRGB(temp) * edgeMask * edgeGlow * (2.0 + treble);

  // Depth haze
  let haze = depth * 0.25;
  color = mix(color, color * vec3<f32>(0.6, 0.75, 1.0) + vec3<f32>(0.1, 0.14, 0.2), haze);

  // Vignette
  let vig = 1.0 - dot((uv01 - 0.5) * 1.3, (uv01 - 0.5) * 1.3);
  color = color * mix(0.85, 1.0, clamp(vig, 0.0, 1.0));

  // Temporal feedback trail
  let prev = textureLoad(dataTextureC, pixel, 0);
  let decay = 0.94 + revealMask * 0.04;
  let trail = mix(prev.rgb * decay, color, 0.18 + bass * 0.06);

  // HDR clamp, ACES tonemap, IGN dither
  color = hue_preserve_clamp(color, 3.0);
  color = aces(color * (1.0 + mids * 0.1));
  let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // Semantic alpha = effect reveal strength
  let alpha = mix(0.5, 1.0, revealMask);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(trail, alpha));
}
