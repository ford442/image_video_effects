// ═══════════════════════════════════════════════════════════════════
//  Echo Ripple
//  Category: image
//  Features: mouse-driven, audio-reactive, audio-envelope, temporal,
//            depth-aware, chromatic-aberration, aces-tone-mapping
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash & noise ──────────────────────────────────────────────────
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
    for (var i: i32 = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}

// ── Audio envelope ────────────────────────────────────────────────
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// ── Tone map & luma ───────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Chromatic shift ───────────────────────────────────────────────
fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(color.r * (1.0 + shift.x * 0.8), color.g, color.b * (1.0 - shift.y * 0.5));
}

// ── Echo ripple helper ────────────────────────────────────────────
fn echoWave(uv: vec2<f32>, center: vec2<f32>, aspect: f32, freq: f32, speed: f32, age: f32, phase: f32) -> f32 {
    let rd = (uv - center) * vec2<f32>(aspect, 1.0);
    let rdist = length(rd);
    return sin(rdist * freq - age * speed + phase) * smoothstep(0.7, 0.0, rdist) * step(0.0, age);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Audio reactivity with temporal envelope stored in history alpha
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let rms = plasmaBuffer[0].w;
    let history = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0);
    let envBass = bass_env(history.a, bass, 0.8, 0.15);
    let beat = envBass * exp(-3.0 * fract(time * 3.0));

    // Params
    let frequency = u.zoom_params.x * 30.0 + 2.0;
    let speed = u.zoom_params.y * 8.0 + 0.5;
    let decay = u.zoom_params.z * 0.97 + 0.02;
    let strength = u.zoom_params.w * 0.15 + 0.01;

    // Mouse gravity well (branchless UV pull toward cursor)
    let d = (uv01 - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(d);
    let dist2 = dot(d, d) + 0.001;
    let grav = d * strength * 0.02 / dist2;

    // Primary ripple from live mouse position
    let wave = sin(dist * frequency - time * speed + mids * 2.0) * (1.0 + beat * 3.0);
    let atten = smoothstep(0.6, 0.0, dist);

    // Echo ripples from the last three click events
    let rippleCount = u32(u.config.y);
    var totalWave = wave;
    for (var i: i32 = 0; i < 3; i++) {
        let hasR = f32(rippleCount > u32(i));
        let r = u.ripples[i];
        let rw = echoWave(uv01, r.xy, aspect, frequency, speed, time - r.z, f32(i) * 0.7) * hasR;
        totalWave += rw;
    }

    // Click shockwave burst
    let clickWave = sin(dist * 50.0 - time * 20.0) * mouseDown * smoothstep(0.25, 0.0, dist);

    // Branchless outward direction
    let rawDir = uv01 - mouse;
    let rawDist = length(rawDir) + 0.0001;
    let dir = rawDir / rawDist;

    // Depth-aware parallax: stronger distortion on foreground
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let depthMod = mix(0.6, 1.2, depth);

    // Total UV distortion with organic audio drift
    let drift = fbm(uv01 * 4.0 + time * 0.1, 2) * 0.01 * mids;
    let distort = (totalWave + clickWave) * strength * atten * depthMod;
    let sampleUV = clamp(uv01 - dir * (distort + drift) + grav, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample video input with RGB channel separation
    var color: vec3<f32>;
    color.r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(0.003, 0.0) * strength, 0.0).r;
    color.g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    color.b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(0.003, 0.0) * strength, 0.0).b;

    // FFT multi-band color tinting at ripple edges
    let fftTint = vec3<f32>(envBass * 0.5, mids * 0.3, treble * 0.6) * totalWave * atten * strength * 10.0;
    color += fftTint;

    // Treble sparkle on ripple crests
    let hash = fract(sin(dot(uv01 * 1000.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let sparkle = treble * step(0.92, hash) * atten * 0.5;
    color += vec3<f32>(sparkle);

    // Temporal feedback loop with subtle motion advection
    let advect = dir * distort * 0.02;
    let prev = textureSampleLevel(dataTextureC, u_sampler, clamp(uv01 - advect, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let mixed = mix(color, prev.rgb, decay * (1.0 - atten * 0.25));

    // Chromatic aberration + ACES tone mapping
    let caStr = 0.003 * (1.0 + envBass) + depth * 0.001;
    var outColor = genChromaticShift(mixed, uv01, caStr);
    outColor = acesToneMap(outColor * (0.9 + mids * 0.2));

    // Semantic alpha: blend input transparency with ripple intensity
    let inputAlpha = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).a;
    let finalAlpha = mix(inputAlpha, clamp(luma(outColor) * 1.5, 0.2, 0.95), atten * 0.7);

    textureStore(writeTexture, pixel, vec4<f32>(outColor, finalAlpha));
    textureStore(dataTextureA, pixel, vec4<f32>(mixed, envBass));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
