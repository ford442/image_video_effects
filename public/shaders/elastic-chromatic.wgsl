// ═══════════════════════════════════════════════════════════════════
//  Elastic Chromatic — Visualist Upgrade
//  Category: distortion
//  Features: mouse-driven, depth-aware, audio-reactive, chromatic-aberration,
//            temporal-feedback, split-tone, blackbody-temperature, aces-tone-map,
//            ign-dither, premultiplied-alpha
//  Complexity: Medium
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
const MAX_LAG: f32 = 0.995;

// ── Color / tone helpers ───────────────────────────────────────────
fn srgbToLinear(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(2.2)); }
fn linearToSrgb(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(1.0 / 2.2)); }

fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
    let L = luma(c);
    let s = min(1.0, maxLum / max(L, 1e-4));
    return c * s;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    var r = 1.0;
    var g = 0.0;
    var b = 1.0;
    if (t > 66.0) {
        r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0);
        g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0);
    } else {
        g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0);
        if (t <= 19.0) { b = 0.0; }
        else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
    }
    return vec3<f32>(r, g, b);
}

// ── Core elastic helpers ───────────────────────────────────────────
fn mouseInfluence(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32, strength: f32) -> f32 {
    let d = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    return smoothstep(0.5, 0.0, d) * strength;
}

fn ema(current: f32, history: f32, lag: f32) -> f32 {
    return mix(current, history, lag);
}

fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let center = vec2<f32>(0.5);
    let delta = uv - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * (1.0 / sqrt(lenSq));
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

    let uv01 = vec2<f32>(pixel) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // User parameters
    let elasticity = mix(0.1, 1.0, p1) * (1.0 + bass * 0.5);
    let chromaticScale = mix(0.0, 1.0, p2);
    let lissajousRatio = mix(0.5, 2.0, p3);
    let damping = mix(0.1, 0.9, p4);

    // Lissajous secondary chromatic source around mouse
    let lissFreqX = 1.0 + mids * 0.3;
    let lissFreqY = lissajousRatio + mids * 0.2;
    let lissAmp = chromaticScale * 0.08;
    let lissPos = mouse + vec2<f32>(
        lissAmp * sin(time * lissFreqX * 2.0 * (1.0 + elasticity)),
        lissAmp * sin(time * lissFreqY * 2.0 * (1.0 + elasticity))
    );

    // Chromatic input sample with radial RGB shift
    let caAmount = 0.003 * (1.0 + bass) + depth * 0.002 + chromaticScale * 0.004;
    let source = srgbToLinear(chromaticAberration(uv01, caAmount));
    let sourceA = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).a;

    // Influences
    let influence = mouseInfluence(uv01, mouse, aspect, elasticity);
    let lissInfluence = smoothstep(0.4, 0.0, distance(uv01, lissPos)) * chromaticScale;
    let depthMod = (1.0 - depth) * 0.35;

    // Per-channel elastic lag
    let lagR = clamp(elasticity + influence + depthMod + lissInfluence, 0.0, MAX_LAG) * damping;
    let lagB = clamp(elasticity * 0.8 + influence * 0.5 + depthMod * 0.5 + lissInfluence * 0.7, 0.0, MAX_LAG) * damping;
    let lagG = clamp(elasticity * 0.6 + influence * 0.3, 0.0, MAX_LAG) * damping;

    // Temporal chromatic accumulation in linear light
    var color = vec3<f32>(0.0);
    color.r = ema(source.r, prev.r, lagR);
    color.g = ema(source.g, prev.g, lagG);
    color.b = ema(source.b, prev.b, lagB);

    // Audio-reactive split-tone temperature grading
    let lum = luma(color);
    let shadowK = 2200.0 + depth * 1500.0;
    let highlightK = 5500.0 + bass * 6500.0;
    let tone = smoothstep(0.18, 0.72, lum);
    let toneColor = mix(blackbodyRGB(shadowK), blackbodyRGB(highlightK), tone);
    color = color * toneColor;

    // HDR clamp, ACES tone map, sRGB encode
    color = huePreserveClamp(color, 1.6 + mids * 0.4);
    let linearOut = acesToneMap(color * (0.95 + treble * 0.15));

    // Write linear history for next-frame feedback
    textureStore(dataTextureA, pixel, vec4<f32>(linearOut, sourceA));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // IGN dither + premultiplied semantic alpha
    let aberration = abs(lagR - lagB) + lissInfluence;
    let effectAlpha = clamp(0.35 + aberration * 2.0 + treble * 0.1, 0.0, 0.95);
    let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
    let srgbOut = linearToSrgb(linearOut) + vec3<f32>(dither);

    textureStore(writeTexture, pixel, vec4<f32>(srgbOut * effectAlpha, effectAlpha));
}
