// ═══════════════════════════════════════════════════════════════════
//  Ripple Bloom — Caustic Cinema Edition
//  Category: hybrid
//  Features: ripple, bloom, audio-reactive, mouse-interactive, depth-aware,
//            upgraded-rgba, multi-pass-bloom, caustic-refraction, dispersion,
//            starburst-diffraction, film-grain, chromatic-aberration, vignette,
//            color-grading, anamorphic-streaks, lens-dirt
//  Complexity: High
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
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let f = fract(p * vec2<f32>(123.34, 456.21));
  return fract(dot(f, vec2<f32>(1.0, 1.0)) * 78.233);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

// Temporal grain
fn temporalGrain(gid: vec2<f32>, time: f32, treble: f32) -> f32 {
    let t1 = hash21(gid + fract(time * 0.7) * 100.0);
    let t2 = hash21(gid * 1.3 + fract(time * 0.3) * 100.0);
    return (mix(t1, t2, 0.5) - 0.5) * (1.0 + treble * 0.3);
}

// Multi-pass Gaussian bloom approximation (9-tap)
fn gaussianBloom(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, texelSize: vec2<f32>, amount: f32) -> vec3<f32> {
    let weights = array<f32, 5>(0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    var result = textureSampleLevel(tex, samp, uv, 0.0).rgb * weights[0];
    // Horizontal pass
    for (var i: i32 = 1; i < 5; i = i + 1) {
        let offset = vec2<f32>(f32(i) * texelSize.x, 0.0);
        result = result + textureSampleLevel(tex, samp, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * weights[i];
        result = result + textureSampleLevel(tex, samp, clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * weights[i];
    }
    // Vertical pass (approximate by sampling again)
    var result2 = textureSampleLevel(tex, samp, uv, 0.0).rgb * weights[0];
    for (var i: i32 = 1; i < 5; i = i + 1) {
        let offset = vec2<f32>(0.0, f32(i) * texelSize.y);
        result2 = result2 + textureSampleLevel(tex, samp, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * weights[i];
        result2 = result2 + textureSampleLevel(tex, samp, clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * weights[i];
    }
    return (result + result2) * 0.5 * amount;
}

// Caustic refraction: light patterns through water/glass surfaces
fn causticRefraction(uv: vec2<f32>, time: f32, strength: f32) -> f32 {
    let p1 = uv * 4.0 + time * 0.3;
    let p2 = uv * 7.0 - time * 0.2;
    let c1 = sin(p1.x * 3.0) * sin(p1.y * 4.0) * 0.5 + 0.5;
    let c2 = sin(p2.x * 5.0 + p2.y * 3.0) * 0.5 + 0.5;
    let caustic = pow(c1 * c2, 2.0);
    return caustic * strength;
}

// Dispersion: rainbow separation at edges of bright objects
fn dispersion(uv: vec2<f32>, brightness: f32, strength: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let r = sin(angle) * 0.5 + 0.5;
    let g = sin(angle + 2.094) * 0.5 + 0.5;
    let b = sin(angle + 4.189) * 0.5 + 0.5;
    return vec3<f32>(r, g, b) * brightness * strength;
}

// Starburst diffraction: 6-pointed star from very bright pixels
fn starburstDiffraction(uv: vec2<f32>, center: vec2<f32>, brightness: f32, strength: f32) -> vec3<f32> {
    let dir = uv - center;
    let angle = atan2(dir.y, dir.x);
    let dist = length(dir);
    let sixPoint = pow(abs(cos(angle * 3.0)), 4.0);
    let star = sixPoint * exp(-dist * 8.0) * brightness * strength;
    return vec3<f32>(star * 1.0, star * 0.95, star * 0.9);
}

// Chromatic aberration: R/G/B channel offset
fn chromaticAberration(uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let center = uv - vec2<f32>(0.5);
    let r2 = dot(center, center);
    let offset = center * r2 * strength;
    return vec3<f32>(offset.x, offset.x * 0.5, -offset.x);
}

// Vignette
fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let center = uv - vec2<f32>(0.5);
    let r = length(center) * 1.4142;
    return pow(1.0 - r * strength, 2.0);
}

// Color grading
fn colorGrade(color: vec3<f32>, lift: vec3<f32>, gamma: vec3<f32>, gain: vec3<f32>) -> vec3<f32> {
    var c = color;
    c = c + lift * (1.0 - c);
    c = pow(c, gamma);
    c = c * gain;
    return c;
}

// Anamorphic streaks
fn anamorphicStreaks(uv: vec2<f32>, center: vec2<f32>, brightness: f32, strength: f32) -> vec3<f32> {
    let dx = abs(uv.x - center.x);
    let streak = exp(-dx * dx * 2000.0) * brightness * strength;
    return vec3<f32>(streak * 1.0, streak * 0.9, streak * 0.7);
}

// Lens dirt
fn lensDirt(uv: vec2<f32>, time: f32, brightness: f32) -> f32 {
    let dirt1 = hash21(uv * 3.0 + time * 0.01);
    let dirt2 = hash21(uv * 7.0 - time * 0.015);
    let dirt = mix(dirt1, dirt2, 0.5);
    return smoothstep(0.6, 0.9, dirt) * brightness * 0.12;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let rippleAmount = u.zoom_params.x * (0.8 + bass * 0.7);
  let bloomAmount = u.zoom_params.y * (0.9 + treble * 0.6);
  let mouseInfluence = u.zoom_params.z;
  let colorShift = u.zoom_params.w;

  // Cinematic params
  let caStrength = 0.008 + bass * 0.015;
  let vignetteStrength = 0.4 + bass * 0.15;
  let anamorphicStrength = 0.25 + bass * 0.25;
  let causticStrength = 0.15 + mids * 0.2;
  let dispersionStrength = 0.1 + treble * 0.15;
  let starburstStrength = 0.3 + treble * 0.4;
  let lensDirtAmount = 0.15 + treble * 0.1;

  // Depth controls water depth (affects ripple speed)
  let waterDepth = mix(0.3, 1.0, 1.0 - depth);
  let rippleSpeed = 3.5 * waterDepth;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Huygens wavelet construction: multiple frequency ripples with dispersion
  let distToMouse = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  var ripple = 0.0;
  var rippleHeight = 0.0;
  for (var f: i32 = 0; f < 3; f = f + 1) {
    let freq = 8.0 + f32(f) * 10.0;
    let phase = distToMouse * freq - time * rippleSpeed * (1.0 + f32(f) * 0.15);
    let decay = exp(-distToMouse * (3.0 + f32(f) * 0.8));
    let wave = sin(phase) * decay;
    ripple = ripple + wave * (1.0 - f32(f) * 0.2);
    rippleHeight = rippleHeight + abs(wave) * (1.0 - f32(f) * 0.15);
  }
  ripple = ripple * rippleAmount * 0.4;
  rippleHeight = rippleHeight * rippleAmount;

  let displacedUV = clamp(uv + vec2<f32>(ripple * 0.02, ripple * 0.015), vec2<f32>(0.0), vec2<f32>(1.0));
  var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Chromatic dispersion on ripple crests
  let crest = smoothstep(0.2, 0.8, rippleHeight);
  let caOffset = crest * 0.004 * colorShift;
  let rSamp = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + vec2<f32>(caOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bSamp = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - vec2<f32>(caOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  color = vec3<f32>(rSamp, color.g, bSamp);

  // ── Multi-pass Gaussian bloom ──
  let texelSize = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
  let bloom = gaussianBloom(readTexture, u_sampler, displacedUV, texelSize, bloomAmount);
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let brightMask = smoothstep(0.5, 0.92, luma);
  color = color + bloom * vec3<f32>(0.5, 0.75, 1.0) * (0.6 + mids * 0.5);

  // ── Caustic refraction ──
  let caustic = causticRefraction(displacedUV, time, causticStrength);
  color = color + caustic * vec3<f32>(0.4, 0.6, 0.9) * rippleHeight * 0.3;

  // ── Dispersion: rainbow separation at bright edges ──
  let dispColor = dispersion(displacedUV, brightMask, dispersionStrength);
  color = color + dispColor * crest;

  // ── Starburst diffraction from very bright points ──
  let starburst = starburstDiffraction(displacedUV, mouse, brightMask, starburstStrength);
  color = color + starburst * (0.5 + bass * 0.3);

  // Subsurface scattering in ripple troughs
  let trough = 1.0 - crest;
  let sss = trough * rippleHeight * 0.15 * vec3<f32>(0.4, 0.6, 0.9);
  color = color + sss;

  // Mouse light tint (stone drop)
  let mouseLight = (1.0 - smoothstep(0.0, 0.45, distToMouse)) * mouseInfluence * 0.5;
  color = color + mouseLight * vec3<f32>(0.8, 0.9, 1.0);

  // Color shift from audio
  let hueShift = colorShift * 0.15 + mids * 0.08;
  color = mix(color, color * vec3<f32>(1.0 + hueShift, 1.0 - hueShift * 0.5, 1.0 - hueShift), 0.2);

  // ── Film grain ──
  let grain = temporalGrain(vec2<f32>(gid.xy), time, treble);
  color = color + grain * 0.04;

  // ── Chromatic aberration (radial) ──
  let ca = chromaticAberration(uv, caStrength);
  let rCA = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + vec2<f32>(ca.r, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bCA = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + vec2<f32>(ca.b, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  color = vec3<f32>(mix(color.r, rCA, 0.3), color.g, mix(color.b, bCA, 0.3));

  // ACES tone mapping
  color = acesToneMap(color * 1.2);

  // ── Vignette ──
  let vig = vignette(uv, vignetteStrength * 0.7);
  color = color * mix(0.5, 1.0, vig);

  // ── Color grading ──
  let lift = vec3<f32>(0.01, 0.005, -0.005) * (1.0 + bass * 0.05);
  let gamma = vec3<f32>(0.97, 0.98, 1.03) - mids * 0.02;
  let gain = vec3<f32>(1.03, 1.0, 0.97) * (1.0 + treble * 0.03);
  color = colorGrade(color, lift, gamma, gain);

  // ── Anamorphic streaks ──
  let streaks = anamorphicStreaks(uv, vec2<f32>(0.5), brightMask, anamorphicStrength);
  color = color + streaks;

  // ── Lens dirt ──
  let dirt = lensDirt(uv, time, brightMask * lensDirtAmount);
  color = color + vec3<f32>(0.9, 0.85, 0.7) * dirt;

  // Semantic alpha: ripple_height * dispersion_intensity * depth
  let dispersionIntensity = crest + bloomAmount * 0.5 + rippleHeight * 0.3;
  let semanticAlpha = clamp(rippleHeight * dispersionIntensity * depth * 2.0, 0.15, 0.95);

  let depthOut = clamp(mix(depth, 0.25 + rippleHeight * 0.6, 0.2), 0.0, 1.0);

  color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.5));
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color * semanticAlpha, semanticAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(ripple, rippleHeight, bloomAmount, semanticAlpha));
}