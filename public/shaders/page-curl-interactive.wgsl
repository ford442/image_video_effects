// ═══════════════════════════════════════════════════════════════════
//  Page Curl Interactive
//  Category: image
//  Features: upgraded-rgba, mouse-driven, audio-reactive, temporal,
//            depth-aware, aces-tone-map, chromatic-aberration, oklab-mix
//  Complexity: Medium
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

// ── Hash & noise ───────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

// ── Color science ──────────────────────────────────────────────────
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(2.2)); }
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(1.0 / 2.2)); }
fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
  let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
  let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
  let l_ = pow(l, 1.0 / 3.0); let m_ = pow(m, 1.0 / 3.0); let s_ = pow(s, 1.0 / 3.0);
  return vec3<f32>(0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                   1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                   0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_);
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  let m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  let s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  let l = l_ * l_ * l_; let m = m_ * m_ * m_; let s = s_ * s_ * s_;
  return vec3<f32>(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

fn warmLight(t: f32) -> vec3<f32> { return vec3<f32>(1.0, 0.78, 0.58) * (0.85 + t * 0.35); }
fn coolLight(t: f32) -> vec3<f32> { return vec3<f32>(0.68, 0.82, 1.0) * (0.45 + t * 0.2); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  let lum = luma(c);
  return c * min(1.0, max_lum / max(lum, 1e-4));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// ── Main ───────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / res;
  let coord = vec2<i32>(global_id.xy);
  let time = u.config.x;

  let curlRadius = max(0.03, u.zoom_params.x * 0.35);
  let shadowIntensity = u.zoom_params.y;
  let feedbackAmt = u.zoom_params.z;
  let depthInfluence = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let prev = textureLoad(dataTextureC, coord, 0);

  let EPSILON = 0.001;
  let snap = 1.0 + bass * 0.4 * step(0.6, bass);
  let mouse = u.zoom_config.yz;
  let curlX = clamp(mouse.x, 0.05, 0.95);
  let dx = uv.x - curlX;
  let radius = curlRadius * snap;

  // Click shockwaves
  var shockDisp = 0.0;
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rDist = length(uv - rp.xy);
    let rAge = time - rp.z;
    let rRad = rAge * 0.45;
    let rBand = abs(rDist - rRad);
    let isActive = select(0.0, 1.0, rBand < 0.04 && rAge >= 0.0 && rAge < 1.2);
    let decay = clamp(1.0 - rAge / 1.2, 0.0, 1.0);
    shockDisp += isActive * decay * 0.025 * sin(rDist * 40.0 - rAge * 12.0);
  }

  // Front page
  let frontSampUV = clamp(uv + vec2<f32>(shockDisp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let frontColor = textureSampleLevel(readTexture, u_sampler, frontSampUV, 0.0);
  let frontLin = srgb_to_linear(frontColor.rgb);
  let frontShadow = (1.0 - smoothstep(0.0, max(radius, EPSILON), -dx)) * 0.5
                    * shadowIntensity * (1.0 + depth * depthInfluence);
  let frontRGB = frontLin * (1.0 - frontShadow);

  // Curl cylinder
  let theta = asin(clamp(dx / max(radius, EPSILON), -1.0, 1.0));
  let srcX = clamp(curlX + radius * theta, 0.0, 1.0);
  let srcUV = vec2<f32>(srcX, uv.y);
  let paperNoise = fbm(srcUV * 40.0 + vec2<f32>(time * 0.01, 0.0), 3) * 0.15;
  let chromaOff = mids * 0.01;
  let curlR = textureSampleLevel(readTexture, u_sampler,
    clamp(srcUV + vec2<f32>(chromaOff, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let curlG = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0).g;
  let curlB = textureSampleLevel(readTexture, u_sampler,
    clamp(srcUV - vec2<f32>(chromaOff, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var curlLin = srgb_to_linear(vec3<f32>(curlR, curlG, curlB) * 0.55 + vec3<f32>(paperNoise));

  // 3-point lighting on curl: warm key, cool fill, audio-reactive rim
  let normalZ = cos(theta);
  let key = warmLight(treble) * pow(max(normalZ, 0.0), 2.0) * 0.55;
  let fill = coolLight(0.0) * pow(max(-normalZ * 0.5 + 0.5, 0.0), 2.0) * 0.25;
  let rim = mixOkLab(warmLight(0.0), coolLight(0.0), mids) * pow(1.0 - abs(normalZ), 3.0) * 0.4;
  curlLin = curlLin * (1.0 + key + fill) + rim;

  let foldShadow = smoothstep(0.0, radius * 0.3, dx) * shadowIntensity;

  // Background
  let bgDark = vec3<f32>(0.02, 0.025, 0.035);
  let bgEdge = smoothstep(0.0, 0.6, uv.y + sin(uv.x * TAU + time * 0.2) * 0.05);
  let bgLin = mixOkLab(bgDark, vec3<f32>(0.08, 0.1, 0.14), bgEdge * 0.6);

  // Blend zones branchless
  let isFront = dx < 0.0;
  let isCurl = dx >= 0.0 && dx < radius;
  var rgb = mixOkLab(bgLin, curlLin, f32(isCurl));
  rgb = mixOkLab(rgb, frontRGB, f32(isFront));

  // Temporal feedback
  let fbBlend = feedbackAmt * 0.25 * (1.0 - select(0.0, 0.7, isFront));
  var hdr = mix(rgb, prev.rgb, fbBlend);

  // Chromatic aberration
  let center = uv - vec2<f32>(0.5);
  let caStr = (0.003 * (1.0 + bass) + depth * 0.001) * (1.0 + mids);
  let caDir = normalize(center + vec2<f32>(0.0001));
  hdr = vec3<f32>(hdr.r + caDir.x * caStr, hdr.g, hdr.b - caDir.y * caStr * 0.5);

  // Tone map, dither, semantic alpha
  hdr = hue_preserve_clamp(hdr, 2.0);
  let srgb = linear_to_srgb(acesToneMap(hdr * 1.15));
  let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  let outRGB = srgb + vec3<f32>(dither);
  let bloomWeight = pow(max(0.0, luma(outRGB) - 0.55), 2.0) * 2.5;
  let alpha = clamp(max(bloomWeight, 0.85 * (1.0 - f32(isFront) * 0.3)), 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(outRGB * alpha, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(outRGB, alpha));
}
