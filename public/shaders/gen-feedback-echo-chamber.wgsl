// ═══════════════════════════════════════════════════════════════════════════════
//  Gen Feedback Echo Chamber v5 — Multi-Pass-Architect Optimized
//  Category: feedback/temporal
//  Focus: cached fBM, distance-aware LOD, branchless feedback envelope,
//         tighter temporal accumulation loop.
// ═══════════════════════════════════════════════════════════════════════════════

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

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
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
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i: i32 = 0; i < oct; i++) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.0001;
    return d * (strength / dist2);
}

fn psychedelicPalette(t: f32) -> vec3<f32> {
    let hue = fract(t);
    let sat = clamp(0.72 + 0.28 * sin(TAU * (t * 0.137 + 0.19)), 0.45, 1.0);
    let val = 1.0 + 0.18 * sin(TAU * (t * 0.071 + 0.43));
    let rgb = clamp(abs(fract(vec3<f32>(hue) + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let smoothRgb = rgb * rgb * (vec3<f32>(3.0) - 2.0 * rgb);
    return mix(vec3<f32>(val), smoothRgb * val, sat);
}

// Manual reconstruction uses only exact texel loads from the feedback ring.
fn loadHistoryExact(uv: vec2<f32>) -> vec4<f32> {
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    let hi = dims - vec2<i32>(1);
    let p = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(dims) - vec2<f32>(0.5);
    let base = vec2<i32>(floor(p));
    let f = fract(p);
    let c00 = textureLoad(dataTextureC, clamp(base, vec2<i32>(0), hi), 0);
    let c10 = textureLoad(dataTextureC, clamp(base + vec2<i32>(1, 0), vec2<i32>(0), hi), 0);
    let c01 = textureLoad(dataTextureC, clamp(base + vec2<i32>(0, 1), vec2<i32>(0), hi), 0);
    let c11 = textureLoad(dataTextureC, clamp(base + vec2<i32>(1), vec2<i32>(0), hi), 0);
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let audio = plasmaBuffer[0];
    let bassRaw = audio.x;
    let mids = audio.y;
    let treble = audio.z;
    let hasEnvelope = arrayLength(&extraBuffer) >= 134u;
    var prevEnv = bassRaw;
    if (hasEnvelope) { prevEnv = extraBuffer[133]; }
    let bass = bass_env(prevEnv, bassRaw, 0.8, 0.15);

    let echoCount = i32(round(mix(2.0, 8.0, clamp(u.zoom_params.x, 0.0, 1.0))));
    let decayRate = mix(0.55, 0.94, clamp(u.zoom_params.y, 0.0, 1.0));
    let echoSpacing = mix(0.002, 0.06, clamp(u.zoom_params.z, 0.0, 1.0));
    let colorShift = u.zoom_params.w;

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);

    // Luma-keyed spawn from bright video regions
    let lumaVid = luma(video.rgb);
    let spawnMask = smoothstep(0.45, 0.85, lumaVid) * (0.25 + treble * 0.75);

    // Mouse gravity well + fBM domain-warped drift
    let gWell = gravityWell(uv01, mouse, 0.015 + mouseDown * 0.055);
    var warpedUV = uv01 + gWell * (0.02 + echoSpacing * 2.0);

    // Distance-aware LOD: fewer octaves in the periphery
    let focusDist = length(uv01 - vec2<f32>(0.5));
    let lodOct = i32(clamp(3.0 - focusDist * 2.0, 1.0, 3.0));

    // Cached fBM: one noise field drives both drift and palette
    let driftTime = time * 0.2;
    let noiseBase = warpedUV * 8.0;
    let driftA = fbm(noiseBase + vec2<f32>(driftTime, 0.0), lodOct);
    let driftB = fbm(noiseBase + vec2<f32>(5.2 - driftTime * 0.85, 1.3), lodOct);
    let drift = vec2<f32>(driftA, driftB);
    warpedUV += drift * (0.015 + mids * 0.02);

    // Echo displacement from feedback
    let wobble = vec2<f32>(
        sin(time * 0.5 * (1.0 + mids * 0.3) + warpedUV.y * 6.0) * echoSpacing * (1.0 + bass * 0.3),
        cos(time * 0.35 * (1.0 + mids * 0.3) + warpedUV.x * 6.0) * echoSpacing * (1.0 + bass * 0.2)
    );
    var echoAccum = vec4<f32>(0.0);
    var totalWeight = 0.0;
    var echoWeight = 1.0;
    for (var echoIndex = 1; echoIndex <= 8; echoIndex++) {
        if (echoIndex > echoCount) { break; }
        echoWeight *= decayRate;
        let fi = f32(echoIndex);
        let echoUV = fract(warpedUV + wobble * fi + vec2<f32>(driftB - 0.5, driftA - 0.5) * echoSpacing * fi);
        echoAccum += loadHistoryExact(echoUV) * echoWeight;
        totalWeight += echoWeight;
    }
    let echo = echoAccum / max(totalWeight, 0.0001);

    // Psychedelic generative color (reuses cached drift noise)
    let paletteT = time * 0.08 + driftA * 0.7 + driftB * 0.3 + bass * 0.5 + colorShift;
    let genColor = psychedelicPalette(paletteT) * (0.8 + mids * 0.35);

    // Depth-aware blend: effect breathes in background, foreground stays crisp
    let fog = 1.0 - exp(-depth * (2.0 + decayRate * 3.0));
    let blended = mix(echo.rgb, genColor, 0.25 + spawnMask * 0.4 + bass * 0.15);
    var color = mix(blended, video.rgb, 0.15 + fog * 0.35);

    // Click shockwave burst
    let clickDist = length(uv01 - mouse);
    let shockwave = mouseDown * exp(-clickDist * clickDist * 350.0) * sin(clickDist * 55.0 - time * 10.0);
    color += vec3<f32>(1.0, 0.75, 0.35) * shockwave * (1.0 + bass * 2.0);
    let rippleCount = min(i32(u.config.y), 50);
    for (var ri = 0; ri < rippleCount; ri++) {
        let event = u.ripples[ri];
        let age = time - event.z;
        if (age > 0.0 && age < 2.5) {
            let radius = age * (0.25 + echoSpacing * 2.0);
            let ring = exp(-abs(distance(uv01, event.xy) - radius) * 100.0) * exp(-age * 1.7) * event.w;
            color += psychedelicPalette(colorShift + age * 0.2) * ring * (0.5 + bass);
        }
    }

    // Treble sparkle
    color += hash21(uv01 * 200.0 + time * 3.0) * treble * 1.5;

    // Temporal accumulation with stable branchless feedback
    let prev = textureLoad(dataTextureC, pixel, 0);
    let trailFade = decayRate;
    let accMix = 0.08 + (1.0 - decayRate) * 0.2;
    let accColor = mix(prev.rgb, color, accMix) * trailFade;

    // Chromatic aberration + tone map
    let delta = uv01 - vec2<f32>(0.5);
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * (1.0 / sqrt(lenSq));
    let caStr = 0.0025 * (1.0 + bass) + depth * 0.0015;
    let shift = dir * caStr;
    color = vec3<f32>(accColor.r + shift.x, accColor.g, accColor.b - shift.y * 0.5);
    color = acesToneMap(color * (1.1 + bass * 0.25));

    // Semantic alpha: interaction intensity + trail density
    let alpha = clamp(luma(color) + spawnMask * 0.35 + abs(shockwave) * 0.5, 0.1, 0.95);
    let output = vec4<f32>(color, alpha);

    textureStore(dataTextureA, pixel, output);
    textureStore(writeTexture, pixel, output);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));

    if (global_id.x == 0u && global_id.y == 0u && hasEnvelope) {
        extraBuffer[133] = bass;
    }
}
