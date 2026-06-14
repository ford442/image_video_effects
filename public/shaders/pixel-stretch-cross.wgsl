// ═══════════════════════════════════════════════════════════════════
//  Pixel Stretch Cross — Interactivist Upgrade
//  Category: interactive-mouse / distortion
//  Features: mouse-driven, audio-reactive, depth-aware,
//            temporal-feedback, click-shockwave, aces-tone-map,
//            upgraded-rgba
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
const GOLDEN_ANGLE: f32 = 2.39996322972865332;

// ── Tone mapping ──────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Audio envelope (attack/release smoothed bass) ─────────────────
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// ── Hash & fBm for organic jitter ─────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
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
    for (var i: i32 = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

// ── 2D rotation ───────────────────────────────────────────────────
fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ── Safe mouse UV (fallback to center before first input) ─────────
fn get_mouse() -> vec2<f32> {
    return select(vec2<f32>(0.5, 0.5), u.zoom_config.yz, u.zoom_config.y >= 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(pixel) / res;
    let mouse = get_mouse();
    let time = u.config.x;
    let mouseDown = u.zoom_config.w > 0.5;

    let hStretch = u.zoom_params.x * 0.3;
    let vStretch = u.zoom_params.y * 0.3;
    let depthInfluence = u.zoom_params.z;
    let turbulence = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Smoothed bass envelope stored in dataTextureA.r
    let smoothBass = bass_env(prev.r, bass, 0.8, 0.15);
    let stretchScale = 1.0 + smoothBass * 0.6;
    let depthFactor = 1.0 - depth * depthInfluence;

    // Mouse distance gravity well: closer pixels stretch more toward mouse
    let toMouse = uv - mouse;
    let centerDist = length(toMouse);
    let gravity = 1.0 / (1.0 + centerDist * 4.0);

    // Global rotation drifts with mids, creating emergent morphing
    let driftAngle = mids * 0.6 * sin(time * 0.7) + turbulence * fbm(uv * 4.0 + time * 0.1, 3);
    let rot = rot2(driftAngle);

    var accum = vec3<f32>(0.0);
    var weight = 0.0;
    var maxStretch = 0.0;

    let numSamples: i32 = 16;

    for (var i: i32 = 0; i < numSamples; i = i + 1) {
        let fi = f32(i) + 0.5;
        let r = sqrt(fi / f32(numSamples));
        let theta = fi * GOLDEN_ANGLE;

        let baseDir = vec2<f32>(cos(theta), sin(theta));
        // Pull direction toward mouse as a gravity well
        let attracted = normalize(mix(baseDir, normalize(toMouse + vec2<f32>(0.0001)), gravity * 0.4));
        // Organic per-ray jitter
        let jitter = fbm(uv * 10.0 + time * 0.2 + f32(i) * 0.17, 2) * turbulence;
        let dir = normalize(rot * attracted + jitter * vec2<f32>(cos(theta * 3.0), sin(theta * 3.0)));

        let aniso = mix(hStretch, vStretch, abs(dir.y));
        let stretchBand = aniso * stretchScale * depthFactor * (1.0 + gravity * 0.5);

        let parallel = dot(toMouse, dir);
        let perp = toMouse - dir * parallel;
        let perpDist = length(perp);

        let bandWidth = stretchBand * (1.0 + turbulence * 0.5);
        let inBand = 1.0 - smoothstep(0.0, bandWidth, perpDist);

        if (inBand > 0.01) {
            let decay = 10.0 + turbulence * 10.0 + mids * 5.0;
            let alongDist = abs(parallel);
            let factor = exp(-alongDist * decay) * inBand;

            // Click shockwave: expanding ring from mouse while held
            let ring = fract(time * 2.0 + f32(i) * 0.02);
            let ringDist = abs(centerDist - ring * 0.7);
            let clickPulse = select(0.0, exp(-ringDist * 45.0) * 2.0, mouseDown);

            let sampleUv = mouse + dir * parallel;
            let clampedUv = clamp(sampleUv, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, clampedUv, 0.0).rgb;

            let contribution = factor * (1.0 + clickPulse);
            accum += sampleColor * contribution;
            weight += contribution;
            maxStretch = max(maxStretch, contribution);
        }
    }

    var color = src.rgb;
    if (weight > 0.001) {
        let smearColor = accum / weight;
        color = mix(color, smearColor, min(weight * 2.0, 1.0));
    }

    // Center hot spot with treble shimmer
    let hotSpot = exp(-centerDist * 18.0) * 0.3 * (hStretch + vStretch) * stretchScale * (1.0 + treble * 0.5);
    color += src.rgb * hotSpot;

    // Temporal feedback: blend current frame into decaying trail
    let decay = 0.92 - turbulence * 0.05;
    let trail = mix(prev.rgb * decay, color, 0.25 + smoothBass * 0.15);

    // Subtle exposure boost driven by smoothed bass, then ACES tone map
    let exposure = 0.95 + smoothBass * 0.15;
    color = acesToneMap(trail * exposure);

    // Semantic alpha: source alpha modulated by effect intensity and trail presence
    let alpha = src.a * (1.0 - maxStretch * 0.2) * (0.85 + smoothBass * 0.15);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(smoothBass, 0.0, 0.0, prev.a * 0.97 + 0.03));
}
