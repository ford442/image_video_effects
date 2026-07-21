// ═══════════════════════════════════════════════════════════════════
//  Pixel Stretch Cross — Visualist Cinematic Polish Upgrade
//  Category: interactive-mouse / distortion
//  Features: mouse-driven, audio-reactive, depth-aware,
//            temporal-feedback, click-shockwave, aces-tone-map,
//            upgraded-rgba, alpha-layered
//  Upgraded: 2026-07-08 (Phase B alpha compositor)
//  Upgraded: 2026-07-21 (Visualist: velocity-steered axis blend,
//            bass-pulse amplitude, HDR bloom on stretch crossings)
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

// Fixed character constants (formerly wired to legacy sliders h/v/depth/turb
// at their 0.5 defaults — preserved so the shader's soul stays intact).
const DEPTH_INFLUENCE: f32 = 0.5;
const TURBULENCE: f32 = 0.5;

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

// ── Luminance for alpha keying ────────────────────────────────────
fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── HDR bloom kernel for stretch crossings (pre-tonemap only) ─────
// Quadratic falloff keeps highlights hot without lifting the floor.
fn crossingBloom(c: vec3<f32>, mask: f32, intensity: f32) -> vec3<f32> {
    let hot = max(c, vec3<f32>(0.0));
    return (hot * hot * 0.7 + hot * 0.3) * mask * intensity;
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

    // ── Slider params (Visualist wiring, index 0–3) ───────────────
    let stretchAmp = u.zoom_params.x;    // Stretch Amplitude
    let axisBlendParam = u.zoom_params.y; // Axis Blend (manual H<->V bias)
    let bloomIntensity = u.zoom_params.z; // Bloom Intensity
    let bassResponse = u.zoom_params.w;   // Bass Response

    let depthInfluence = DEPTH_INFLUENCE;
    let turbulence = TURBULENCE;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // ── Mouse velocity tracking (global scratch in extraBuffer) ───
    // [0..1] = previous mouse uv, [2..3] = smoothed mouse velocity.
    let prevMouse = vec2<f32>(extraBuffer[0], extraBuffer[1]);
    var smVel = vec2<f32>(extraBuffer[2], extraBuffer[3]);
    let rawVel = mouse - prevMouse;
    smVel = mix(smVel, rawVel, 0.35);
    if (global_id.x == 0u && global_id.y == 0u) {
      extraBuffer[0] = mouse.x;
      extraBuffer[1] = mouse.y;
      extraBuffer[2] = smVel.x;
      extraBuffer[3] = smVel.y;
    }

    let mouseSpeed = length(smVel);
    // Confidence ramps in only when the pointer actually moves.
    let velConf = clamp(mouseSpeed * 40.0, 0.0, 1.0);
    // Signed axis preference: + = horizontal motion, - = vertical motion.
    let velAxis = clamp(0.5 + (abs(smVel.x) - abs(smVel.y)) * 20.0, 0.0, 1.0);
    // Velocity steers the manual axis blend; at rest the slider rules.
    let axisMix = clamp(mix(axisBlendParam, velAxis, velConf * 0.8), 0.0, 1.0);

    // Amplitude slider maps to a cinematic range; default 0.5 ≈ old feel.
    let ampScale = 0.06 + stretchAmp * 0.42;
    let hStretch = ampScale * axisMix;
    let vStretch = ampScale * (1.0 - axisMix);

    // Smoothed bass envelope stored in dataTextureA.r
    let smoothBass = bass_env(prev.r, bass, 0.8, 0.15);
    // Bass-pulse: stretch magnitude breathes with the bass envelope.
    let stretchScale = 1.0 + smoothBass * (0.15 + bassResponse * 1.1);
    let depthFactor = 1.0 - depth * depthInfluence;

    // Mouse distance gravity well: closer pixels stretch more toward mouse
    let toMouse = uv - mouse;
    let centerDist = length(toMouse);
    let gravity = 1.0 / (1.0 + centerDist * 4.0);

    // Global rotation drifts with mids, creating emergent morphing.
    // Fast mouse flicks add a transient twist to the whole field.
    let flickTwist = clamp(mouseSpeed * 6.0, 0.0, 0.6) * sign(smVel.x + 0.0001);
    let driftAngle = mids * 0.6 * sin(time * 0.7)
        + turbulence * fbm(uv * 4.0 + time * 0.1, 3)
        + flickTwist;
    let rot = rot2(driftAngle);

    var accum = vec3<f32>(0.0);
    var weight = 0.0;
    var maxStretch = 0.0;
    var crossEnergy = 0.0;

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
            // Overlap of multiple rays = crossing; feed the bloom mask.
            crossEnergy += contribution * inBand;
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

    // ── HDR bloom on stretch crossings (added BEFORE tonemapping) ──
    // Crossings glow hardest near the mouse well and on strong overlaps;
    // the bass envelope gives the bloom a subtle heartbeat.
    let crossMask = smoothstep(0.10, 0.85, crossEnergy * (0.5 + gravity));
    let bloomGain = bloomIntensity * 1.8 * (1.0 + smoothBass * 0.4);
    let bloomed = trail + crossingBloom(trail, crossMask, bloomGain);

    // Subtle exposure boost driven by smoothed bass, then ACES tone map
    let exposure = 0.95 + smoothBass * 0.15;
    color = acesToneMap(bloomed * exposure);

    // ── Layered alpha compositing ───────────────────────────────────
    // Depth-layered: far pixels fade, near pixels remain solid
    let depthAlpha = mix(0.35, 1.0, depth);

    // Luminance key: dark stretched regions become transparent
    let luma = luminance(color);
    let lumaAlpha = smoothstep(0.04, 0.22, luma);

    // Effect-intensity: high stretch contributions slightly reduce opacity
    let stretchAlpha = 1.0 - clamp(maxStretch * 0.35, 0.0, 0.45);

    // Audio-reactive opacity envelope
    let bassAlpha = 0.8 + smoothBass * 0.2;

    // Bloom slightly thickens alpha so crossings read as luminous paint
    let bloomAlpha = 1.0 + crossMask * bloomIntensity * 0.25;

    // Blend depth/luminance keys via depth-influence parameter
    let keyedAlpha = mix(lumaAlpha, depthAlpha, depthInfluence);

    // Source alpha composited with layered keys and effect intensity
    var alpha = src.a * keyedAlpha * stretchAlpha * bassAlpha * bloomAlpha;

    // Accumulative trail: feedback builds alpha like paint while preserving motion
    alpha = mix(prev.a * 0.96, alpha, 0.2 + maxStretch * 0.35);

    // Keep a small floor so the chain never fully vanishes
    alpha = clamp(alpha, 0.06, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(smoothBass, crossMask, 0.0, alpha * 0.97 + 0.03));
}
