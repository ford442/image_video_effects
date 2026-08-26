// ═══════════════════════════════════════════════════════════════════
//  Neon Pulse Stream — Bundled Tube Bank with Travelling Packets
//  Category: image
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-stream-fft, tube-bundle, chromatic-aberration, fresnel,
//            afterglow-persistence, depth-aware, upgraded-rgba,
//            semantic-alpha, aces
//  Complexity: High
//  Chunks From: curl2D, warpedFBM, bass_env, Fresnel-tube
//  Created: 2026-05-23
//  Upgraded: 2026-08-23 (Batch 56 — Turbulent Vortex)
// ═══════════════════════════════════════════════════════════════════
//  The previous version had a single scrolling band field: one `fract()` stripe
//  across the whole frame, no pointer input, no click response, no read-back.
//  Two structures replace it:
//
//    1. Tube bundle — five independent neon tubes, each a curl-perturbed
//       sinusoidal centreline with its own frequency, drift and phase. Every
//       tube is shaded as a real glass tube: gaussian core, Fresnel rim that
//       brightens toward the silhouette, and an outer bloom. Because the tubes
//       cross, the bundle produces genuine overlap highlights instead of a
//       uniform stripe pattern.
//
//    2. Travelling packets + per-stream FFT — each tube owns one of the 8
//       spectrum bins (plasmaBuffer[1..8]), which sets its thickness, hue drift
//       and the speed of the light packets running along it. Packets are
//       gaussian pulses in arc length, so the bundle reads as signal traffic.
//
//  Interaction: the pointer is a magnetic attractor that bends every tube
//  toward it (held = stronger and brighter), and clicks inject bounded pulse
//  fronts that flare the tubes they cross. dataTextureC supplies exact-load
//  afterglow, and the rims are split chromatically.
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=StreamSpeed, y=StreamDensity, z=LumaThreshold, w=Softness
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const STREAMS: u32 = 5u;

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let uu = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, uu.x), mix(c, d, uu.x), uu.y);
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

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = fbm(p + vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n2 = fbm(p - vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n3 = fbm(p + vec2<f32>(0.0, eps) + t * 0.1, 3);
  let n4 = fbm(p - vec2<f32>(0.0, eps) + t * 0.1, 3);
  let dy = (n1 - n2) / (2.0 * eps);
  let dx = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dx, -dy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

// IQ cosine palette — hue per stream, drifting with its own band.
fn palette(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(TAU * (vec3<f32>(1.0, 1.0, 1.0) * t
                               + vec3<f32>(0.0, 0.33, 0.67)));
}

fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, lum);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let dims = vec2<f32>(dimsI);
    let uv = vec2<f32>(global_id.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioReactivity = bass_env(bass, mids);

    // ── Params ───────────────────────────────────────────────────────────────
    let streamSpeed = u.zoom_params.x * 3.0 * (1.0 + mids * 0.3);
    let streamDensity = u.zoom_params.y * 10.0 + 3.0 + treble * 2.0;
    let lumaThreshold = u.zoom_params.z * 0.5;
    let softness = max(u.zoom_params.w * 0.2, 0.02);

    let mouse = u.zoom_config.yz;
    let held = step(0.5, u.zoom_config.w);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFade = mix(0.6, 1.0, depth);

    // Curl advection of the sampling frame — keeps the plate moving with the tubes.
    let curl = curl2D(uv * 2.0, time * 0.15) * 0.02 * audioReactivity;
    let advectUV = uv + curl;

    // ── Bounded click pulse fronts ───────────────────────────────────────────
    var clickFlare = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.4) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            let front = rDist - age * 0.65;
            clickFlare += exp(-front * front * 200.0) * exp(-age * 1.5);
        }
    }
    clickFlare = min(clickFlare, 1.5);

    // ── Structure 1 + 2: tube bundle with travelling packets ─────────────────
    let mouseVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let mouseDist = length(mouseVec);
    let attractStrength = (0.06 + held * 0.10) * exp(-mouseDist * mouseDist * 9.0);

    var streamColor = vec3<f32>(0.0);
    var coreMax = 0.0;
    var rimMax = 0.0;
    var packetMax = 0.0;

    for (var k = 0u; k < STREAMS; k = k + 1u) {
        let fk = f32(k);
        let band = plasmaBuffer[(k % 8u) + 1u].x;

        // Centreline: sinusoid + curl perturbation + pointer attraction.
        let freq = 1.2 + fk * 0.55;
        let phase = fk * 1.7;
        let amp = 0.10 + 0.05 * sin(fk * 2.3) + band * 0.06;
        var yC = 0.18 + fk * 0.16
               + sin(advectUV.x * TAU * freq + time * streamSpeed * 0.35 + phase) * amp
               + curl.y * 0.6;
        yC += (mouse.y - yC) * attractStrength * 6.0;

        let d = abs(uv.y - yC);

        // Tube geometry: gaussian core, Fresnel-style rim, outer bloom.
        let width = (0.006 + band * 0.010 + bass * 0.004) * (1.0 + held * 0.3);
        let nd = d / max(width, 1e-4);
        let core = exp(-nd * nd);
        let rim = pow(clamp(1.0 - abs(nd - 1.0), 0.0, 1.0), 6.0);
        let bloom = exp(-nd * nd * 0.08) * 0.22;

        // Packets running along arc length; density sets their spacing.
        let s = advectUV.x * streamDensity * 0.35 - time * streamSpeed * (0.6 + band * 0.5) + phase;
        let pk = fract(s) - 0.5;
        let packet = exp(-pk * pk * 42.0) * exp(-nd * nd * 0.6);

        let hue = fk * 0.17 + time * 0.03 + band * 0.25 + bass * 0.08;
        let tint = palette(hue);

        streamColor += tint * (core * 1.5 + rim * 1.1 + bloom) * depthFade;
        streamColor += tint * packet * (1.4 + treble * 1.6);

        coreMax = max(coreMax, core);
        rimMax = max(rimMax, rim);
        packetMax = max(packetMax, packet);
    }

    let tubeMask = clamp(coreMax + rimMax * 0.6 + packetMax * 0.8, 0.0, 1.0);

    // ── Plate, with chromatic split proportional to tube rim energy ──────────
    let ca = (0.0015 + treble * 0.005) * (rimMax + clickFlare);
    let bR = textureSampleLevel(readTexture, u_sampler, advectUV + vec2<f32>(ca, 0.0), 0.0).r;
    let bG = textureSampleLevel(readTexture, u_sampler, advectUV, 0.0);
    let bB = textureSampleLevel(readTexture, u_sampler, advectUV - vec2<f32>(ca, 0.0), 0.0).b;
    let bg = vec3<f32>(bR, bG.g, bB);
    let bgLuma = dot(bg, vec3<f32>(0.299, 0.587, 0.114));

    var composite = bg * (1.0 - tubeMask * 0.7) + streamColor;

    // Click fronts flare whichever tubes they cross.
    composite += streamColor * clickFlare * 1.2 + vec3<f32>(0.6, 0.85, 1.0) * clickFlare * 0.35;
    // Pointer halo.
    composite += vec3<f32>(0.35, 0.7, 1.0) * exp(-mouseDist * mouseDist * 24.0) * (0.25 + held * 0.7);

    // Sparkle on bright plate regions when treble is hot.
    var sparkle = 0.0;
    if (treble > 0.4 && bgLuma > 0.5) {
      let sparkNoise = hash21(uv * 500.0 + time * 30.0);
      let sparkMask = step(0.97, sparkNoise);
      composite += vec3<f32>(sparkMask * treble * 2.0);
      sparkle = sparkMask;
    }

    // ── Afterglow: exact previous-frame read-back ────────────────────────────
    let prev = textureLoad(dataTextureC, coord, 0);
    composite = max(composite, prev.rgb * (0.86 - mids * 0.06));

    composite = acesFilm(composite);

    // ── Semantic alpha ───────────────────────────────────────────────────────
    let lumaAlpha = luminanceKeyAlpha(streamColor, lumaThreshold, softness);
    let alpha = clamp(lumaAlpha * tubeMask + bgLuma * 0.2 + 0.1
                      + sparkle * 0.5 + clickFlare * 0.3, 0.0, 1.0);
    let finalColor = vec4<f32>(composite, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);

    // Depth: tubes float in front of the plate.
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(depth * (1.0 - coreMax * 0.14), 0.0, 0.0, 0.0));
}
