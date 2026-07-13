// ═══════════════════════════════════════════════════════════════════
//  Cyber Organic Scanner — Visualist Enhanced Edition
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba,
//            bioluminescent, oklab-mixing, blackbody-warmth,
//            volumetric-glow, aces-tone-map, split-tone
//  Complexity: High
//  Chunks From: cyber-organic
//  Created: 2026-05-30
//  Upgraded: 2026-06-28
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
  zoom_params: vec4<f32>,  // x=ScanSpeed, y=OrganicScale, z=RevealRadius, w=PulseSpeed
  ripples: array<vec4<f32>, 50>,
};

// ── Color Science ─────────────────────────────────────────────────

// Inigo Quilez cosine palette
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

// OkLab color space
fn srgbToLinear(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(2.2));
}

fn linearToSrgb(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(1.0 / 2.2));
}

fn linearToOkLab(c: vec3<f32>) -> vec3<f32> {
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

fn okLabToLinear(c: vec3<f32>) -> vec3<f32> {
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

fn okLabMix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  let la = linearToOkLab(srgbToLinear(a));
  let lb = linearToOkLab(srgbToLinear(b));
  return linearToSrgb(okLabToLinear(mix(la, lb, t)));
}

// Blackbody color temperature approximation
fn blackbodyRGB(temp: f32) -> vec3<f32> {
  var t = temp / 100.0;
  var r: f32;
  var g: f32;
  var b: f32;

  if (t <= 66.0) {
    r = 255.0;
    g = 99.4708025861 * log(t) - 161.1195681661;
    if (t <= 19.0) {
      b = 0.0;
    } else {
      b = 138.5177312231 * log(t - 10.0) - 305.0447927307;
    }
  } else {
    r = 329.698727446 * pow(t - 60.0, -0.1332047592);
    g = 288.1221695283 * pow(t - 60.0, -0.0755148492);
    b = 255.0;
  }

  return clamp(vec3<f32>(r, g, b) / 255.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ACES filmic tone mapping
fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return (x * (a * x + b)) / (x * (c * x + d) + e);
}

// Hue-preserving clamp
fn huePreserveClamp(c: vec3<f32>) -> vec3<f32> {
  let maxc = max(max(c.r, c.g), c.b);
  if (maxc > 1.0) {
    return c / maxc;
  }
  return c;
}

// IGN blue-noise dither
fn ignDither(p: vec2<f32>, t: f32) -> f32 {
  let fp = fract(p + t * 0.07);
  return fract(52.9829189 * fract(0.06711056 * fp.x + 0.00583715 * fp.y));
}

// ── Noise & FBM ───────────────────────────────────────────────────

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = p;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + a * hash12(floor(f) + fract(f));
    f = f * 2.1 + 7.13;
    a = a * 0.5;
  }
  return v;
}

// ── Main ──────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let scanSpeed = 0.15 + u.zoom_params.x * 4.0;
  let organicScale = mix(2.0, 14.0, u.zoom_params.y);
  let revealRadius = mix(0.10, 0.80, u.zoom_params.z);
  let pulseSpeed = 0.2 + u.zoom_params.w * 5.0;

  let centered = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let reveal = 1.0 - smoothstep(0.0, revealRadius, dist);
  let field = fbm(uv * organicScale + vec2<f32>(time * 0.12, -time * 0.09));
  let vein = 1.0 - smoothstep(0.12, 0.32, abs(field - 0.5));
  let scan = 0.5 + 0.5 * sin(uv.y * 40.0 + time * scanSpeed * 6.0 + field * 6.28318);
  let pulse = 0.5 + 0.5 * sin(time * pulseSpeed * 6.0 + field * 12.0);
  let warp = vec2<f32>(scan - 0.5, pulse - 0.5) * 0.03 * (0.4 + audio.x + reveal);
  let sampleUV = clamp(uv + warp, vec2<f32>(0.0), vec2<f32>(1.0));

  var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Bioluminescent color palette with OkLab mixing
  // ═══════════════════════════════════════════════════════════════
  let bioPaletteT = field * 3.0 + time * 0.2 + bass * 2.0;
  let bioColor1 = palette(bioPaletteT,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(0.30, 0.50, 0.20)  // green-cyan
  );
  let bioColor2 = palette(bioPaletteT + 0.5 + mids,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5 + treble * 0.3, 0.5),
    vec3<f32>(0.8, 1.0, 0.6),
    vec3<f32>(0.55, 0.35, 0.75)  // magenta shift
  );
  let bioTint = okLabMix(bioColor1, bioColor2, pulse * 0.55);

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Blackbody warmth modulation
  // ═══════════════════════════════════════════════════════════════
  let bbTemp = 3000.0 + bass * 4000.0 + reveal * 2000.0;
  let bbColor = blackbodyRGB(bbTemp);
  let warmTint = okLabMix(bioTint, bbColor, reveal * 0.3 + vein * 0.2);

  finalColor = mix(finalColor, finalColor * 0.55 + warmTint * (0.45 + audio.z * 0.2), reveal * 0.55 + vein * 0.15);
  finalColor = finalColor + warmTint * vein * (0.05 + 0.16 * audio.y);

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Volumetric glow around veins
  // ═══════════════════════════════════════════════════════════════
  let veinGlow = vein * vein * 0.4 * (1.0 + bass * 0.6);
  let glowColor = okLabMix(
    vec3<f32>(0.05, 0.95, 0.75),
    vec3<f32>(0.95, 0.45, 0.85),
    pulse * 0.5 + treble * 0.3
  );
  finalColor = finalColor + glowColor * veinGlow;

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Split-tone — shadows cool, highlights warm
  // ═══════════════════════════════════════════════════════════════
  let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let shadowTint = vec3<f32>(0.08, 0.18, 0.35); // deep bioluminescent blue
  let highlightTint = vec3<f32>(0.95, 0.85, 0.40); // warm phosphor yellow
  finalColor = okLabMix(finalColor, shadowTint, (1.0 - luma) * 0.25 * (reveal + vein));
  finalColor = okLabMix(finalColor, highlightTint, smoothstep(0.5, 0.95, luma) * 0.2 * (reveal + vein));

  // HDR workflow
  finalColor = finalColor * (1.0 + treble * 0.3);

  // Hue-preserving clamp
  finalColor = huePreserveClamp(finalColor);

  // ACES filmic tone mapping
  finalColor = aces(finalColor);

  // IGN dither
  let dither = ignDither(vec2<f32>(gid.xy), time) * 0.0039;
  finalColor = finalColor + vec3<f32>(dither);

  // Bloom-based alpha
  let bloomAlpha = pow(max(0.0, luma - 0.6), 2.0) * 3.0;
  let finalAlpha = clamp(0.68 + reveal * 0.18 + vein * 0.10 + bloomAlpha * 0.1, 0.42, 0.98);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.24 + reveal * 0.56 + vein * 0.18, 0.32), 0.0, 1.0);

  // Premultiplied alpha writeback
  let out = vec4<f32>(finalColor * finalAlpha, finalAlpha);

  textureStore(writeTexture, vec2<i32>(gid.xy), out);
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(vein, scan, reveal, finalAlpha));
}
