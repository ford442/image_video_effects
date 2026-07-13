// ═══════════════════════════════════════════════════════════════════
//  Cyber Rain
//  Category: interactive-mouse
//  Features: upgraded-rgba, rain, neon, wet-glass, mouse-driven,
//            audio-reactive, temporal-feedback, depth-aware,
//            chromatic-aberration, semantic-alpha, gravity-well,
//            click-shockwave, spring-damper, thunder-flash
//  Complexity: High
//  Upgraded: 2026-07-12 (retry expansion)
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

const PREV_PRESS: i32 = 0;
const CLICK_TIME: i32 = 1;
const CLICK_X: i32 = 2;
const CLICK_Y: i32 = 3;
const SMOOTH_X: i32 = 4;
const SMOOTH_Y: i32 = 5;
const VEL_X: i32 = 6;
const VEL_Y: i32 = 7;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    return mix(prev, bass, select(release, attack, bass > prev));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
    let len = length(v);
    return select(v / len, vec2<f32>(0.0), len < 0.0001);
}

fn shockwave(uv: vec2<f32>, clickPos: vec2<f32>, age: f32) -> f32 {
    let radius = age * 0.6;
    let delta = uv - clickPos;
    let dRing = length(delta);
    let arg = (dRing - radius) * 14.0;
    return exp(-arg * arg) * (1.0 - age * 0.8) * 1.8;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let dt = u.config.y;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let isPress = u.zoom_config.w;

    let rainBase = clamp(u.zoom_params.x, 0.0, 1.0);
    let blurStrength = u.zoom_params.y * 0.1;
    let bloomThreshold = u.zoom_params.z;
    let wiperSize = u.zoom_params.w * 0.5;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let prev = textureLoad(dataTextureC, coord, 0);
    let env = bass_env(prev.a, bass, 0.8, 0.15);

    // ---- persistent interactive state ----
    var prevPress = extraBuffer[PREV_PRESS];
    var clickTime = extraBuffer[CLICK_TIME];
    var clickPos = vec2<f32>(extraBuffer[CLICK_X], extraBuffer[CLICK_Y]);
    var smoothMouse = vec2<f32>(extraBuffer[SMOOTH_X], extraBuffer[SMOOTH_Y]);
    var velocity = vec2<f32>(extraBuffer[VEL_X], extraBuffer[VEL_Y]);

    let k = 60.0;
    let d = 10.0;
    let accel = (mouse - smoothMouse) * k - velocity * d;
    velocity = velocity + accel * dt;
    smoothMouse = smoothMouse + velocity * dt;
    let smoothMouse_aspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);

    if (isPress > 0.5 && prevPress <= 0.5) {
        clickTime = time;
        clickPos = mouse;
    }

    extraBuffer[PREV_PRESS] = isPress;
    extraBuffer[CLICK_TIME] = clickTime;
    extraBuffer[CLICK_X] = clickPos.x;
    extraBuffer[CLICK_Y] = clickPos.y;
    extraBuffer[SMOOTH_X] = smoothMouse.x;
    extraBuffer[SMOOTH_Y] = smoothMouse.y;
    extraBuffer[VEL_X] = velocity.x;
    extraBuffer[VEL_Y] = velocity.y;

    let rainIntensity = clamp(rainBase * (1.0 + env * 0.5), 0.0, 1.0);

    // ---- spring-damper wiper follows the cursor smoothly ----
    let distVec = (uv - smoothMouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let wiper = smoothstep(wiperSize, wiperSize * 0.75, dist) * (1.0 - isPress * 0.5);

    // ---- mouse gravity well bends falling rain toward the cursor ----
    let toMouse = smoothMouse_aspect - (uv * vec2<f32>(aspect, 1.0));
    let gravityStrength = smoothstep(0.55, 0.0, length(toMouse)) * (0.08 + env * 0.06);
    let rainBend = safeNormalize(toMouse).x * gravityStrength;

    var blurredColor = vec3<f32>(0.0);
    let samples = 5;
    for (var i = 0; i < samples; i++) {
        let t = f32(i) / f32(samples - 1);
        let offset = (t - 0.5) * blurStrength * 2.0 * (1.0 - wiper);
        let sampleUV = clamp(uv + vec2<f32>(0.0, offset), vec2<f32>(0.0), vec2<f32>(1.0));
        let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let brightness = max(col.r, max(col.g, col.b));
        let bloom = smoothstep(bloomThreshold, 1.0, brightness);
        blurredColor += col * (1.0 + bloom * (2.0 + mids));
    }
    blurredColor /= f32(samples);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    var color = mix(baseColor, blurredColor, rainIntensity * 0.8);

    // ---- falling drops with gravity bend ----
    let rainUV = uv * vec2<f32>(24.0, 2.5) + vec2<f32>(time * (0.2 + rainBend * 4.0), time * (8.0 + env * 12.0));
    let rainNoise = hash12(floor(rainUV));
    let drop = smoothstep(0.88, 0.95, rainNoise) * rainIntensity * (1.0 - wiper);

    // ---- streaks also bend toward the mouse ----
    let streakUV = uv * vec2<f32>(8.0, 40.0) + vec2<f32>(time * 0.3 + rainBend * 2.0, time * 25.0);
    let streak = smoothstep(0.92, 0.98, hash12(floor(streakUV))) * rainIntensity * (1.0 - wiper) * 0.5;

    let rainColor = vec3<f32>(0.45, 0.75, 1.0) + vec3<f32>(0.2, 0.1, 0.0) * env;
    color += rainColor * (drop + streak);

    // ---- click shockwave: a radial splash that momentarily clears rain ----
    let age = time - clickTime;
    var shock = 0.0;
    if (age < 1.25) {
        let click_aspect = vec2<f32>(clickPos.x * aspect, clickPos.y);
        shock = shockwave(uv * vec2<f32>(aspect, 1.0), click_aspect, age);
        color = color + rainColor * shock * (0.7 + treble);
    }

    // ---- thunder flash on strong bass peaks ----
    let flash = smoothstep(0.7, 0.9, env) * (0.0 + 0.25 * fract(time * 16.0));
    color = color + vec3<f32>(0.9, 0.95, 1.0) * flash;

    let wetTrail = mix(prev.rgb * 0.93, color, 0.08 + rainIntensity * 0.1);
    color = mix(color, wetTrail, 0.35 + rainIntensity * 0.3);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let fog = 1.0 - exp(-depth * 2.0);
    color = mix(color, color * 0.6 + rainColor * 0.05, fog * 0.45);

    let delta = uv - vec2<f32>(0.5);
    let dir = delta / (length(delta) + 0.0001);
    let caAmt = (0.002 + depth * 0.0015) * (1.0 + env);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + dir * caAmt, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - dir * caAmt * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    color = vec3<f32>(r, color.g, b);

    color = acesToneMap(color * (0.9 + env * 0.15));

    let alpha = clamp(0.3 + rainIntensity * 0.55 + drop * 0.4 + shock * 0.25, 0.0, 0.95);
    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(wetTrail, env));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
