// ═══════════════════════════════════════════════════════════════════
//  Mouse Ink Bleed
//  Category: interactive-mouse
//  Features: upgraded-rgba, mouse-driven, audio-reactive, ink-diffusion,
//            organic, domain-warp, temporal-feedback, depth-aware,
//            gravity-well, click-shockwave, spring-damper, emergent-feedback,
//            aces-tone-map, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-30
//  Updated: 2026-07-12 (retry expansion)
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
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
    return p + strength * q;
}
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    return mix(prev, bass, select(release, attack, bass > prev));
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    let f = fract(sin(dot(p, vec2<f32>(17.0, 43.0))) * 144.7);
    return fract(f * 0.5 + 0.5);
}
fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
    let len = length(v);
    return select(v / len, vec2<f32>(0.0), len < 0.0001);
}
fn shockwave(uv: vec2<f32>, clickPos: vec2<f32>, age: f32) -> vec2<f32> {
    let radius = age * 0.5;
    let delta = uv - clickPos;
    let dRing = length(delta);
    let arg = (dRing - radius) * 14.0;
    let ring = exp(-arg * arg);
    let strength = ring * (1.0 - age * 0.833) * 0.06;
    return safeNormalize(delta) * strength;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let pixel = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;
    let dt = u.config.y;
    let mouse = u.zoom_config.yz;
    let isPress = u.zoom_config.w;

    let spread = mix(0.01, 0.5, clamp(u.zoom_params.x, 0.0, 1.0));
    let turbulence = clamp(u.zoom_params.y, 0.0, 1.0);
    let decay = mix(0.85, 0.995, clamp(u.zoom_params.z, 0.0, 1.0));
    let colorIntensity = clamp(u.zoom_params.w, 0.0, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let prev = textureLoad(dataTextureC, pixel, 0);
    let env = bass_env(prev.a, bass, 0.8, 0.15);

    // ---- persistent interactive state (spring-damper + click burst) ----
    var prevPress = extraBuffer[PREV_PRESS];
    var clickTime = extraBuffer[CLICK_TIME];
    var clickPos = vec2<f32>(extraBuffer[CLICK_X], extraBuffer[CLICK_Y]);
    var smoothMouse = vec2<f32>(extraBuffer[SMOOTH_X], extraBuffer[SMOOTH_Y]);
    var velocity = vec2<f32>(extraBuffer[VEL_X], extraBuffer[VEL_Y]);

    let k = 64.0;
    let d = 10.0;
    let accel = (mouse - smoothMouse) * k - velocity * d;
    velocity = velocity + accel * dt;
    smoothMouse = smoothMouse + velocity * dt;

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

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let dist = length(uv - mouse);
    let activeBrush = smoothstep(spread * 0.6, spread * 0.08, dist) * (0.6 + isPress * 1.2);
    let inkRadius = activeBrush * (0.7 + env * 0.5);

    let warpUv = domainWarp(uv * (3.0 + turbulence * 5.0) + vec2<f32>(time * 0.05), turbulence * (1.0 + treble), 3);
    let gradX = fbm(warpUv + vec2<f32>(0.02, 0.0), 3) - fbm(warpUv - vec2<f32>(0.02, 0.0), 3);
    let gradY = fbm(warpUv + vec2<f32>(0.0, 0.02), 3) - fbm(warpUv - vec2<f32>(0.0, 0.02), 3);
    var displacement = vec2<f32>(gradX, gradY) * inkRadius * spread * 2.5;

    // ---- mouse gravity well (smooth, lagging center) ----
    let toWell = smoothMouse - uv;
    let wellDist = length(toWell);
    let gravityRadius = spread * 1.6;
    let gravityStrength = smoothstep(gravityRadius, 0.0, wellDist) * (0.04 + env * 0.03 + bass * 0.02);
    let angle = atan2(toWell.y, toWell.x);
    let vortex = vec2<f32>(-sin(angle), cos(angle)) * gravityStrength * (0.5 + isPress * 0.8);
    displacement = displacement + toWell * gravityStrength * 3.0 + vortex;

    // ---- click shockwave ----
    let age = time - clickTime;
    var shockStrength = 0.0;
    if (age < 1.2) {
        displacement = displacement + shockwave(uv, clickPos, age) * (1.0 + env);
        let radius = age * 0.5;
        let delta = uv - clickPos;
        let dRing = length(delta);
        let arg = (dRing - radius) * 14.0;
        shockStrength = exp(-arg * arg) * (1.0 - age * 0.833) * 2.5;
    }

    // ---- emergent feedback loop: previous color energy warps current ink ----
    let feedbackEnergy = length(prev.rgb);
    displacement = displacement + safeNormalize(displacement) * feedbackEnergy * 0.015 * (1.0 + mids);

    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let inkTint = vec3<f32>(0.18, 0.12, 0.28) + vec3<f32>(0.1, 0.05, 0.12) * env;
    let inkColor = mix(vec3<f32>(luminance), color * inkTint, 0.4 + mids * 0.2);
    color = mix(color, inkColor, inkRadius * colorIntensity);

    let edgeGlow = smoothstep(0.1, 0.6, inkRadius) * (1.0 - smoothstep(0.4, 0.9, inkRadius));
    color = color + vec3<f32>(0.06, 0.03, 0.1) * edgeGlow * colorIntensity * (0.8 + mids * 0.4);

    // ---- shockwave ink splash ----
    color = color + inkTint * shockStrength * colorIntensity * (0.8 + treble);

    let trail = mix(prev.rgb * decay, color, 0.08 + inkRadius * 0.25);
    color = mix(color, trail, 0.55);

    let fog = 1.0 - exp(-depth * 2.5);
    color = mix(color, color * 0.65 + vec3<f32>(0.02), fog * 0.35);

    color = acesToneMap(color * (0.95 + env * 0.15));
    color = color + (ign(vec2<f32>(global_id.xy)) - 0.5) * 0.006;

    let effect = inkRadius * 0.7 + edgeGlow * 0.5 + shockStrength * 0.4;
    let semantic_alpha = clamp(baseColor.a * (0.5 + effect * 0.6), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(color, semantic_alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, env));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
