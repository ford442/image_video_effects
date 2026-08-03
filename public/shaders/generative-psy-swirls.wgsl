// ═══════════════════════════════════════════════════════════════════
//  Generative Psy Swirls
//  Category: generative
//  Features: audio-reactive, mouse-interactive, psychedelic, chromatic, temporal-layer-memory,
//            upgraded-rgba, aces-tone-map, chromatic-hue-separation, audio-twist,
//            domain-warped-swirl, mids-hue-fan, feedback-clamp
//  Complexity: High
//  Upgraded: 2026-08-03 (Batch 34: sprung interaction, guarded ripples,
//            non-filtering feedback loads, generated relief depth)
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ── Value noise & fbm for the swirl domain warp ───────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),                       hash21(i + vec2<f32>(1.0, 0.0)), s.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x),
        s.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// One swirl arm layer in polar space. hueShift fans the layer's hue
// rotation so mids energy spreads layers into rainbow fringes.
fn layeredSwirlLayer(uv: vec2<f32>, time: f32, twist: f32, freq: f32,
                     offset: vec2<f32>, hueShift: f32) -> vec3<f32> {
    let d = length(uv - offset);
    let a = atan2(uv.y - offset.y, uv.x - offset.x);
    let swirl = a + d * twist * freq - time * 0.5;
    let arm = sin(swirl * 3.0) * 0.5 + 0.5;
    let distRipple = sin(d * 10.0 - time * 2.0) * 0.5 + 0.5;
    let val = arm * distRipple;
    let hue = fract(d * 0.5 + time * 0.1 + hueShift);
    return hsv2rgb(vec3<f32>(hue, 0.8, val));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let coord = vec2<i32>(global_id.xy);

    // ── Sliders (saved-preset contract: ids/defaults unchanged) ──
    // twist          -> vortex twist strength (bass adds a kick)
    // layers         -> number of stacked swirl layers
    // frequency      -> polar arm frequency + domain warp scale
    // depthReduction -> how much scene depth flattens the twist
    let twist = u.zoom_params.x * 4.0 * (1.0 + bass * 0.3);
    let layers = u.zoom_params.y * 5.0 + 2.0;
    let freq = u.zoom_params.z * 2.0 + 0.5;
    let depthReduction = u.zoom_params.w;

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let adjustedTwist = twist * (1.0 - depth * depthReduction);

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouse = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouse) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouse += mouseVelocity * springDt;
    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = time;
    }
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let m = (mouse - 0.5) * vec2<f32>(aspect, 1.0);

    // ── Domain warp: fbm offset bends the swirl arms so they ──────
    // breathe instead of rotating rigidly. Frequency slider scales
    // the warp field; treble adds shimmer to the warp drift.
    let warpScale = 1.5 + freq * 1.5;
    let warpDrift = vec2<f32>(time * 0.11, -time * 0.08) * (1.0 + treble * 0.2);
    let warp = vec2<f32>(
        fbm(p * warpScale + warpDrift, 3),
        fbm(p * warpScale * 1.37 + vec2<f32>(5.2, 1.3) - warpDrift.yx, 3)
    );
    let warpStrength = 0.10 + u.zoom_params.z * 0.10 + bass * 0.03;
    p = p + (warp - vec2<f32>(0.5)) * warpStrength;

    // ── Multi-layer swirl with mids-driven chromatic hue fan ──────
    var rLayer = vec3<f32>(0.0);
    var gLayer = vec3<f32>(0.0);
    var bLayer = vec3<f32>(0.0);
    for (var i: i32 = 0; i < i32(layers); i = i + 1) {
        let fi = f32(i);
        let offset = m * fi * 0.1 + vec2<f32>(
            sin(time * 0.3 + fi * 1.2) * 0.1,
            cos(time * 0.2 + fi * 0.8) * 0.1
        );
        // Per-layer hue stagger grows with mids: layers fan out into
        // rainbow fringes on musical peaks.
        let hueFan = fi * mids * 0.06;
        rLayer += layeredSwirlLayer(p, time, adjustedTwist, freq + fi * 0.2 + treble * 0.1,
                                    offset + vec2<f32>(fi * 0.02, 0.0), hueFan + mids * 0.10);
        gLayer += layeredSwirlLayer(p, time, adjustedTwist, freq + fi * 0.2,
                                    offset, hueFan * 0.5);
        bLayer += layeredSwirlLayer(p, time, adjustedTwist, freq + fi * 0.2 - bass * 0.1,
                                    offset - vec2<f32>(fi * 0.02, 0.0), hueFan - mids * 0.10);
    }
    let invLayers = 1.0 / layers;
    rLayer *= invLayers;
    gLayer *= invLayers;
    bLayer *= invLayers;

    var color = vec3<f32>(rLayer.r, gLayer.g, bLayer.b);

    var clickSwirl = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rp = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0);
        let rd = length(p - rp);
        let rt = time - ripple.z;
        if (rt >= 0.0 && rt < 1.7) {
            let ring = exp(-abs(rd - rt * 0.26) * 72.0) * exp(-rt * 1.7);
            clickSwirl = max(clickSwirl, ring);
        }
    }
    color += vec3<f32>(0.5, 0.3, 0.9) * clickSwirl * (0.35 + treble * 0.18);

    // ── Temporal swirl layer accumulation: previous color fades ───
    // in for trails. FEEDBACK CLAMP: the memory write is clamped
    // pre-tint at 1.2 (luma-echo-warp lesson) so accumulated color
    // can never blow up across frames.
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    let trail = mix(color, prev * 0.92, 0.04 + mids * 0.02);
    let trailClamped = clamp(trail, vec3<f32>(0.0), vec3<f32>(1.2));
    let trailTinted = trailClamped * vec3<f32>(0.98, 0.99, 1.02);
    textureStore(dataTextureA, coord,
                 vec4<f32>(min(trailTinted, vec3<f32>(1.2)), 1.0));

    color = mix(color, prev * 0.92, 0.04 + mids * 0.02);

    let reliefDepth = clamp(length(color) * 0.42 + clickSwirl * 0.16, 0.0, 1.0);
    let alpha = clamp(length(color) * 0.72 + bass * 0.05 + clickSwirl * 0.12, 0.0, 0.96);

    color = acesToneMap(color * 1.1);
    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(reliefDepth, 0.0, 0.0, 0.0));
}
