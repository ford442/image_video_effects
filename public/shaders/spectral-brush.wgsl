// ═══════════════════════════════════════════════════════════════════
//  Spectral Brush
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal, depth-aware, blackbody,
//             oklab, chromatic-aberration, aces-tone-mapped, premultiplied-alpha
//  Complexity: High
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

fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(2.2)); }
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(1.0 / 2.2)); }
fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

// ═══ CHUNK: blackbodyRGB ═══
fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 1.0;
  var g = 1.0;
  var b = 1.0;
  if (t <= 66.0) {
    r = 1.0;
  } else {
    r = clamp(329.698727446 / (255.0 * pow(t - 60.0, 0.1332047592)), 0.0, 1.0);
  }
  if (t <= 66.0) {
    g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0);
  } else {
    g = clamp(288.1221695283 / (255.0 * pow(t - 60.0, 0.0755148492)), 0.0, 1.0);
  }
  if (t >= 66.0) {
    b = 1.0;
  } else if (t <= 19.0) {
    b = 0.0;
  } else {
    b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0);
  }
  return vec3<f32>(r, g, b);
}

// ═══ CHUNK: oklab ═══
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

// ═══ CHUNK: hue_preserve_clamp ═══
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  return c * min(1.0, max_lum / max(luma(c), 1e-4));
}

// ═══ CHUNK: ACES_tone_map ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: IGN_dither ═══
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }

// ═══ CHUNK: chromatic_aberration ═══
fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
  let center = vec2<f32>(0.5);
  let delta = uv - center;
  let lenSq = max(dot(delta, delta), 0.000001);
  let dir = delta / sqrt(lenSq);
  let offset = dir * max(amount, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let brushSize = u.zoom_params.x * 0.22 * (1.0 + bass * 0.25);
  let temperature = u.zoom_params.y;
  let persistence = 0.005 + (1.0 - u.zoom_params.z) * 0.12;
  let edgeHardness = u.zoom_params.w;

  let aspect = res.x / res.y;
  let dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthDiffusion = mix(0.3, 1.0, depth);

  let prevMask = textureLoad(dataTextureC, pixel, 0).r;
  let cooledMask = max(0.0, prevMask - persistence * (1.0 + treble * 0.15));

  let untouched = select(0.0, 1.0, cooledMask <= 0.0 && dist > brushSize);

  let innerRadius = brushSize * (1.0 - edgeHardness * 0.9) * depthDiffusion;
  let brushVal = 1.0 - smoothstep(innerRadius, brushSize, dist);
  let finalMask = max(cooledMask, brushVal);
  let effectiveMask = mix(finalMask, 0.0, untouched);

  // Base image with subtle spectral separation
  let caAmount = 0.0015 * (1.0 + bass) + depth * 0.001;
  let baseRGB = chromaticAberration(uv, caAmount);
  let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let base = vec4<f32>(baseRGB, baseSample.a);
  let baseLin = srgb_to_linear(base.rgb);

  // Blackbody spectral core, cooled by time and pushed by audio
  let coolTime = time * 0.06;
  let bbTemp = clamp(temperature + bass * 0.15 - coolTime * (1.0 - effectiveMask), 0.0, 1.0);
  let T = mix(1800.0, 12000.0, bbTemp);
  var bbLin = srgb_to_linear(blackbodyRGB(T) * (1.0 + bass * 0.9 + mids * 0.25));

  // Thin-film iridescence on the brush rim
  let film = 0.5 + 0.5 * cos(dist * 35.0 - time * 2.5 + bass * 3.0);
  bbLin = bbLin * (1.0 + film * 0.12 * effectiveMask);

  // Smooth, perceptually uniform spectral blend
  var color = mixOkLab(baseLin, bbLin, effectiveMask);

  // Bass-driven volumetric bloom around active strokes
  let bloomRadius = brushSize * 2.2 * (1.0 + bass * 0.5 + mids * 0.2);
  let bloomFalloff = smoothstep(bloomRadius, 0.0, dist);
  let bloom = bbLin * bloomFalloff * bass * 0.7;
  color = color + bloom * effectiveMask;

  // HDR clamp, ACES filmic tonemap, and sRGB gamma encode
  color = hue_preserve_clamp(color, 2.5);
  color = acesToneMap(color * (0.95 + mids * 0.2));
  color = linear_to_srgb(color);

  // Split-tone: cool shadows, warm highlights
  let lum = luma(color);
  let shadows = vec3<f32>(0.55, 0.72, 0.95);
  let highlights = vec3<f32>(1.08, 0.82, 0.55);
  color = mix(color * shadows, color * highlights, smoothstep(0.25, 0.75, lum));

  // IGN blue-noise dither to kill 8-bit banding
  let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // Semantic alpha = bloom weight / effect strength
  let bloomWeight = pow(max(0.0, lum - 0.55), 2.0) * 3.0;
  let brushAlpha = clamp(bloomWeight + 0.25 + bass * 0.15, 0.0, 1.0);
  let brushed = vec4<f32>(color * brushAlpha, brushAlpha);
  let finalColor = mix(brushed, base, untouched);

  textureStore(writeTexture, pixel, finalColor);
  textureStore(dataTextureA, pixel, vec4<f32>(effectiveMask, 0.0, 0.0, effectiveMask));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
