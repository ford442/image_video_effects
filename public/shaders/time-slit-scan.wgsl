// ═══════════════════════════════════════════════════════════════════
//  Time Slit Scan
//  Category: artistic
//  Features: mouse-driven, audio-reactive
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

// ── Slit SDFs ────────────────────────────────────────────────
fn sdSineSlit(uv: vec2<f32>, amplitude: f32, freq: f32, phase: f32, width: f32) -> f32 {
  let sineY = 0.5 + amplitude * sin(uv.x * freq + phase);
  return abs(uv.y - sineY) - width * 0.5;
}

fn sdRadialSlit(uv: vec2<f32>, center: vec2<f32>, angle: f32, width: f32) -> f32 {
  let dir = uv - center;
  let a = atan2(dir.y, dir.x);
  let da = abs(fract((a - angle) / 6.283) - 0.5) * 6.283;
  return da - width * 0.5;
}

fn sdSpiralSlit(uv: vec2<f32>, center: vec2<f32>, turns: f32, width: f32) -> f32 {
  let dir = uv - center;
  let r = length(dir);
  let a = atan2(dir.y, dir.x);
  let spiralA = a + r * turns * 6.283;
  let da = abs(fract(spiralA / 6.283) - 0.5) * 6.283;
  return da * r - width * 0.5;
}

// ── Slit Feathering ──────────────────────────────────────────
fn slitBlendFactor(distance: f32, width: f32, feather: f32) -> f32 {
  return smoothstep(width + feather, max(width - feather, 0.0), distance);
}

// ── MAIN ─────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let slitCount = i32(clamp(u.zoom_params.x * 2.0 + 1.0, 1.0, 3.0));
  let slitShape = i32(clamp(u.zoom_params.y * 2.0 + 0.5, 0.0, 2.0));
  let driftSpeed = u.zoom_params.z;
  let slitWidth = mix(0.01, 0.15, u.zoom_params.w);

  let center = vec2<f32>(0.5);
  let phase = time * driftSpeed * 2.0;

  var slitAlpha = 0.0;
  var slitColor = vec3<f32>(0.0);

  for (var s = 0; s < 3; s = s + 1) {
    if (s >= slitCount) { break; }

    let offset = f32(s) * 0.33;
    let slitUV = uv;
    var dist = 0.0;

    if (slitShape == 0) {
      dist = sdSineSlit(slitUV, 0.1, 6.283, phase + offset * 6.283, slitWidth);
    } else if (slitShape == 1) {
      dist = sdRadialSlit(slitUV, center, phase * 0.5 + offset * 2.094, slitWidth);
    } else {
      dist = sdSpiralSlit(slitUV, center, 2.0 + f32(s), slitWidth);
    }

    let inSlit = slitBlendFactor(dist, 0.0, 0.02);
    slitAlpha = slitAlpha + inSlit;

    if (inSlit > 0.0) {
      var driftUV = slitUV;
      if (slitShape == 0) {
        driftUV.x = fract(driftUV.x + driftSpeed * 0.1 * (1.0 + f32(s)));
      } else if (slitShape == 1) {
        let dir = slitUV - center;
        let angle = atan2(dir.y, dir.x) + driftSpeed * 0.05;
        let r = length(dir);
        driftUV = center + vec2<f32>(cos(angle), sin(angle)) * r;
      } else {
        let dir = slitUV - center;
        let angle = atan2(dir.y, dir.x) + driftSpeed * 0.1 * length(dir);
        let r = length(dir);
        driftUV = center + vec2<f32>(cos(angle), sin(angle)) * r;
      }

      let sampleColor = textureSampleLevel(dataTextureC, u_sampler, clamp(driftUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
      // Time-warp tinting: older frames bluer, newer redder
      let tint = mix(vec3<f32>(0.8, 0.9, 1.2), vec3<f32>(1.2, 0.9, 0.8), f32(s) * 0.3);
      slitColor = slitColor + sampleColor.rgb * tint * inSlit;
    }
  }

  slitAlpha = clamp(slitAlpha, 0.0, 1.0);

  // Background: current frame dimmed
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var finalColor = mix(current.rgb * 0.3, slitColor, slitAlpha);

  // Alpha: full in slit, lower outside
  let finalAlpha = mix(0.4, 1.0, slitAlpha);

  let out = vec4<f32>(finalColor, finalAlpha);
  textureStore(writeTexture, global_id.xy, out);
  textureStore(dataTextureA, global_id.xy, out);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
