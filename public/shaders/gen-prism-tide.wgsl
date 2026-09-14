// ═══════════════════════════════════════════════════════════════════
//  Prism Tide
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-14
//  Ideas: Cauchy prism dispersion splitting RGB wavefronts at refracted crests; click tide packets with water-wave dispersion (w^2 = g k tanh(k h)) and Miche breaking foam
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Wave Scale, .y = Refraction, .z = Pulse, .w = Saturation
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

// ACES filmic tone mapping
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hue-preserving clamp before ACES
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

// ── Noise ─────────────────────────────────────────────────────────

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
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
  var v = 0.0;
  var a = 0.5;
  var f = p;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + a * noise2(f);
    f = f * 2.1 + vec2<f32>(7.13, 3.71);
    a = a * 0.5;
  }
  return v;
}

// ── Atmosphere ────────────────────────────────────────────────────

// Mie scattering for haze
fn mieScattering(cosTheta: f32, g: f32) -> f32 {
  let g2 = g * g;
  return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
}

// Animated caustics: FBM of sinusoids
fn caustics(p: vec2<f32>, t: f32) -> f32 {
  let f1 = sin(p.x * 8.0 + t * 1.2) * cos(p.y * 7.0 - t * 0.9);
  let f2 = sin(p.x * 13.0 - t * 0.7) * cos(p.y * 11.0 + t * 1.1);
  return 0.5 + 0.5 * sin(fbm(p + t * 0.05) * 8.0 + t) * (f1 + f2) * 0.5;
}

// Native idea 2: a single click launches a tide packet that obeys the finite-depth
// water-wave dispersion relation w^2 = g k tanh(k h). Each of a few wavenumbers
// travels at its own phase speed, so the packet spreads (long waves outrun short).
// Returns (height, steepness) so the caller can apply the Miche breaking limit.
fn tidePacket(d: f32, age: f32) -> vec2<f32> {
  let g = 9.81;
  let depthH = 0.08;
  var h = 0.0;
  var slope = 0.0;
  for (var j = 0; j < 4; j = j + 1) {
    let k = 18.0 + f32(j) * 14.0;
    let w = sqrt(g * k * tanh(k * depthH));
    let cph = w / k;
    let env = exp(-pow((d - cph * age * 0.9) * 9.0, 2.0));
    let amp = 1.0 / (1.0 + f32(j) * 0.6);
    h = h + amp * env * sin(k * d - w * age * 0.9);
    slope = slope + amp * env * k * abs(cos(k * d - w * age * 0.9));
  }
  let decay = exp(-age * 0.9) / (1.0 + d * 3.0);
  return vec2<f32>(h, slope * 0.02) * decay;
}

// ── Main ──────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouseDown = u.zoom_config.w;

  let waveScale = mix(1.0, 9.0, u.zoom_params.x);
  let refractAmt = mix(0.0, 0.15, u.zoom_params.y);
  let pulse = mix(0.1, 2.0, u.zoom_params.z);
  let saturation = mix(0.3, 1.6, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * vec2<f32>(0.3, 0.2);

  // Click tide packets (floor: ripples) — accumulated height perturbs the tide phase
  var packetH = 0.0;
  var packetSteep = 0.0;
  let clickCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < clickCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age <= 0.0 || age > 4.0) { continue; }
    var cp = rp.xy * 2.0 - 1.0;
    cp.x = cp.x * aspect;
    cp = cp + mouse * vec2<f32>(0.3, 0.2);
    let tp = tidePacket(length(p - cp), age);
    packetH = packetH + tp.x;
    packetSteep = packetSteep + tp.y;
  }

  // Mouse held: the cursor acts as a denser prism lens, locally boosting refraction
  let mouseP = vec2<f32>(mouse.x * aspect, mouse.y) + mouse * vec2<f32>(0.3, 0.2);
  let lens = mouseDown * exp(-dot(p - mouseP, p - mouseP) * 6.0);

  let n = noise2(p * 3.0 + vec2<f32>(time * 0.1, -time * 0.14));
  let refractField = vec2<f32>(sin(p.y * 8.0 + time), cos(p.x * 7.0 - time)) * (refractAmt * (1.0 + lens * 2.5) + lens * 0.05) * (0.4 + n);
  let refracted = p + refractField;
  let phase = length(refracted) * waveScale - time * (0.7 + bass * 0.8) + packetH * 1.6;

  // Native idea 1: Cauchy prism dispersion. Each channel refracts by n(lambda) = A + B/lambda^2,
  // so the refracted wavefront position splits per wavelength (violet bends most).
  // Scaled by the local refraction field, so the split vanishes where refraction is zero.
  let lambdaRGB = vec3<f32>(0.65, 0.55, 0.45);
  let cauchyN = vec3<f32>(1.0) + vec3<f32>(0.012) / (lambdaRGB * lambdaRGB);
  let splitPhase = (cauchyN - vec3<f32>(cauchyN.g)) * length(refractField) * waveScale * (60.0 + treble * 40.0);

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Enhanced prism dispersion — wavelength-dependent
  // ═══════════════════════════════════════════════════════════════
  let dispersionR = 1.0 + treble * 0.3;
  let dispersionG = 1.0 + mids * 0.2;
  let dispersionB = 1.0 + bass * 0.15;

  let r = 0.5 + 0.5 * sin(phase * dispersionR + splitPhase.r + pulse * 1.7 + treble * 1.2);
  let g = 0.5 + 0.5 * sin(phase * dispersionG + splitPhase.g + 2.094 + pulse * 1.1 + mids * 1.5 + bass * 0.1);
  let b = 0.5 + 0.5 * sin(phase * dispersionB + splitPhase.b + 4.188 + pulse * 1.4 + bass * 1.6 + treble * 0.1);

  let crest = smoothstep(0.55, 1.0, max(max(r, g), b));
  // Miche breaking limit: packets steeper than H/L ~ 0.142 spill white foam
  let breaking = smoothstep(0.142, 0.35, packetSteep);
  let foam = sat(smoothstep(0.65, 1.0, sin(phase * 2.3 + n * 2.0)) + breaking * 0.8);
  let sparkle = 0.5 + 0.5 * sin(time * (4.0 + treble * 22.0) + n * 15.0);

  var color = vec3<f32>(r, g, b) * saturation;
  color = color + vec3<f32>(0.8, 0.9, 1.0) * foam * 0.35 * (1.0 + treble * 0.6);
  color = color * (0.75 + crest * 0.75) * (0.85 + sparkle * 0.25);

  // Temporal tide persistence
  let prevCoord = clamp(coord, vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
  let prev = textureLoad(dataTextureC, prevCoord, 0);
  color = mix(color, prev.rgb * 0.9, foam * 0.06 + bass * 0.01);

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Cosine palette overlay for richer chromatic range
  // ═══════════════════════════════════════════════════════════════
  let paletteT = phase * 0.1 + time * 0.08 + bass * 0.5;
  let prismColor = palette(paletteT,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(0.00, 0.33, 0.67)
  );
  let prismColor2 = palette(paletteT + 0.33 + mids,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5 + treble * 0.2, 0.5, 0.5 + bass * 0.2),
    vec3<f32>(0.9, 1.0, 0.8),
    vec3<f32>(0.20, 0.45, 0.70)
  );
  let prismMix = okLabMix(prismColor, prismColor2, crest * 0.5 + foam * 0.3);
  color = okLabMix(color, prismMix, crest * 0.25 + foam * 0.15);

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Animated caustics overlay
  // ═══════════════════════════════════════════════════════════════
  let causticLight = caustics(refracted * 2.0, time) * (0.08 + treble * 0.15);
  let causticColor = vec3<f32>(0.7, 0.85, 1.0);
  color = color + causticColor * causticLight;

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Mie scattering for atmospheric haze
  // ═══════════════════════════════════════════════════════════════
  let viewDir = normalize(p);
  let lightDir = normalize(vec2<f32>(cos(time * 0.15), sin(time * 0.12)));
  let cosTheta = dot(viewDir, lightDir);
  let mie = mieScattering(cosTheta, 0.75) * 0.06 * (1.0 - crest * 0.5);
  let hazeColor = vec3<f32>(0.85, 0.82, 0.78);
  color = color + hazeColor * mie;

  // ═══════════════════════════════════════════════════════════════
  //  VISUALIST: Split-tone
  // ═══════════════════════════════════════════════════════════════
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let shadowTint = vec3<f32>(0.05, 0.15, 0.35); // deep ocean shadows
  let highlightTint = vec3<f32>(0.95, 0.80, 0.45); // warm sun highlights
  color = okLabMix(color, shadowTint, (1.0 - luma) * 0.2);
  color = okLabMix(color, highlightTint, smoothstep(0.5, 0.95, luma) * 0.2);

  // HDR workflow
  color = color * (1.0 + treble * 0.35);

  // Hue-preserving clamp before ACES
  color = huePreserveClamp(color);

  // ACES filmic tone mapping
  color = acesToneMap(color * 1.1);

  // IGN dither
  let dither = ignDither(vec2<f32>(gid.xy), time) * 0.0039;
  color = color + vec3<f32>(dither);

  // Semantic alpha: wave-crest / foam coverage
  let presence = sat(crest * 0.85 + foam * 0.5);
  let bloomAlpha = pow(max(0.0, luma - 0.6), 2.0) * 3.0;
  let alpha = sat(0.1 + presence * 0.9 + bloomAlpha * 0.1);
  let depth = sat(0.8 - crest * 0.55 + noise2(p * 6.0) * 0.12);

  // Premultiplied alpha writeback
  let out = vec4<f32>(color * alpha, alpha);

  textureStore(writeTexture, coord, out);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, out);
}
