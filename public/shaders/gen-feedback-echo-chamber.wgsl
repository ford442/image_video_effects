// ═══════════════════════════════════════════════════════════════════════════════
//  Gen Feedback Echo Chamber v4 — Interactivist Upgrade
//  Category: feedback/temporal
//  Features: gravity-well, shockwave, bass-envelope, domain-warp, depth-fog,
//            psychedelic-palette, chromatic-aberration, temporal-echo
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

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let delta = uv - vec2<f32>(0.5);
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * (1.0 / sqrt(lenSq));
    let shift = dir * strength;
    return vec3<f32>(color.r + shift.x, color.g, color.b - shift.y * 0.5);
}

fn psychedelicPalette(t: f32) -> vec3<f32> {
    let hue = fract(t);
    let sat = clamp(0.72 + 0.28 * sin(TAU * (t * 0.137 + 0.19)), 0.45, 1.0);
    let val = 1.0 + 0.18 * sin(TAU * (t * 0.071 + 0.43));
    let rgb = clamp(abs(fract(vec3<f32>(hue) + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let smoothRgb = rgb * rgb * (vec3<f32>(3.0) - 2.0 * rgb);
    return mix(vec3<f32>(val), smoothRgb * val, sat);
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

    let bassRaw = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let prevEnv = extraBuffer[0];
    let bass = bass_env(prevEnv, bassRaw, 0.8, 0.15);

    let accumulationRate = u.zoom_params.x;
    let echoScale = u.zoom_params.y * 0.06;
    let intensity = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);

    // Luma-keyed spawn from bright video regions
    let lumaVid = luma(video.rgb);
    let spawnMask = smoothstep(0.45, 0.85, lumaVid) * (0.25 + treble * 0.75);

    // Mouse gravity well + fBM domain-warped drift
    let gWell = gravityWell(uv01, mouse, 0.015 + mouseDown * 0.055);
    var warpedUV = uv01 + gWell * (0.02 + echoScale * 2.0);
    let drift = vec2<f32>(
        fbm(warpedUV * 8.0 + time * 0.2, 3),
        fbm(warpedUV * 8.0 - time * 0.17 + vec2<f32>(5.2, 1.3), 3)
    );
    warpedUV += drift * (0.015 + mids * 0.02);

    // Echo displacement from feedback
    let wobble = vec2<f32>(
        sin(time * 0.5 * (1.0 + mids * 0.3) + warpedUV.y * 6.0) * echoScale * (1.0 + bass * 0.3),
        cos(time * 0.35 * (1.0 + mids * 0.3) + warpedUV.x * 6.0) * echoScale * (1.0 + bass * 0.2)
    );
    let echoUV = fract(warpedUV + wobble);
    let echo = textureSampleLevel(dataTextureC, u_sampler, echoUV, 0.0);

    // Psychedelic generative color
    let paletteT = time * 0.08 + fbm(warpedUV * 5.0 + bass * 0.5, 3) + colorShift;
    let genColor = psychedelicPalette(paletteT) * intensity;

    // Depth-aware blend: effect breathes in background, foreground stays crisp
    let fog = 1.0 - exp(-depth * (2.0 + accumulationRate * 3.0));
    let blended = mix(echo.rgb, genColor, 0.25 + spawnMask * 0.4 + bass * 0.15);
    var color = mix(blended, video.rgb, 0.15 + fog * 0.35);

    // Click shockwave burst
    let clickDist = length(uv01 - mouse);
    let shockwave = mouseDown * exp(-clickDist * clickDist * 350.0) * sin(clickDist * 55.0 - time * 10.0);
    color += vec3<f32>(1.0, 0.75, 0.35) * shockwave * (1.0 + bass * 2.0);

    // Treble sparkle
    color += hash21(uv01 * 200.0 + time * 3.0) * treble * 1.5;

    // Temporal accumulation
    let prev = textureLoad(dataTextureC, pixel, 0);
    let trailFade = 0.92 - accumulationRate * 0.08;
    let accColor = mix(prev.rgb, color, 0.08 + accumulationRate * 0.05) * trailFade;

    // Chromatic aberration + tone map
    let caStr = 0.0025 * (1.0 + bass) + depth * 0.0015;
    color = genChromaticShift(accColor, uv01, caStr);
    color = acesToneMap(color * (1.1 + bass * 0.25));

    // Semantic alpha: interaction intensity + trail density
    let alpha = clamp(luma(color) + spawnMask * 0.35 + abs(shockwave) * 0.5, 0.1, 0.95);
    let output = vec4<f32>(color, alpha);

    textureStore(dataTextureA, pixel, output);
    textureStore(writeTexture, pixel, output);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));

    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[0] = bass;
    }
}
