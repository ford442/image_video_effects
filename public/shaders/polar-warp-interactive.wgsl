// ═══════════════════════════════════════════════════════════════════
//  Polar Warp Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, upgraded-rgba, audio-reactive, depth-aware, multi-ripple,
//            temporal-feedback, chromatic-aberration, aces-tone-map
//  Complexity: Medium
//  Upgraded: bass envelope smoothing, mouse-velocity trails, feedback blend,
//            chromatic aberration, ACES tone mapping, semantic alpha
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
const EPS: f32 = 1e-3;

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
    for (var i: i32 = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}
fn rippleAngle(uv: vec2<f32>, aspect: f32, time: f32, rp: vec4<f32>, decay: f32) -> f32 {
    let age = time - rp.z;
    if (age <= 0.0 || age >= 3.0) { return 0.0; }
    let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
    return sin(rd * 30.0 - age * 10.0) * exp(-age * decay * 3.0) * 0.1 * rp.w;
}
fn chromaticShift(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let center = vec2<f32>(0.5);
    let dir = normalize((uv - center) + vec2<f32>(0.001));
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

    let uv = vec2<f32>(pixel) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    let mouseRaw = u.zoom_config.yz;
    let mouse = select(mouseRaw, vec2<f32>(0.5), mouseRaw.x < 0.0);

    let bassRaw = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Temporal state read-back: smoothed bass envelope + previous mouse position
    let prev = textureLoad(dataTextureC, pixel, 0);
    let bassSmooth = bass_env(prev.r, bassRaw, 0.8, 0.15);
    let mouseVel = mouse - prev.gb;
    let mouseSpeed = length(mouseVel);

    // Mouse now modulates warp, spiral and trail blend; bassSmooth drives pulse
    let warpStrength = u.zoom_params.x * (1.0 + bassSmooth * 0.5);
    let spiralAmount = u.zoom_params.y * 5.0 * (1.0 + mouseSpeed * 2.0);
    let rippleDecay = u.zoom_params.z;
    let pinchExpand = u.zoom_params.w * (1.0 + bassSmooth * 0.3);

    var diff = uv - mouse;
    diff.x *= aspect;
    let radius = length(diff);
    let angle = atan2(diff.y, diff.x);

    // Hide the polar singularity and still commit state for this pixel
    if (radius < EPS) {
        textureStore(writeTexture, pixel, vec4<f32>(0.0));
        textureStore(writeDepthTexture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        textureStore(dataTextureA, pixel, vec4<f32>(bassSmooth, mouse.x, mouse.y, mouseSpeed));
        return;
    }

    // Polar distortion: radius warped by Param1 + pinch from Param4
    let zoom = 0.1 + warpStrength * 2.0;
    let r_new = pow(radius, 1.0 / zoom) - pinchExpand;
    var a_new = angle + radius * spiralAmount + time * 0.1;

    // Click-triggered ripple bursts from u.ripples
    for (var i: i32 = 0; i < 50; i = i + 1) {
        a_new += rippleAngle(uv, aspect, time, u.ripples[i], rippleDecay);
    }

    // Map polar coordinates back into UV space with mirrored-repeat edges
    let tunnel_u = (a_new / PI) * 2.0;
    let tunnel_v = 1.0 / (r_new + EPS);
    let fuv = fract(vec2<f32>(tunnel_u, tunnel_v));
    let sampleUV = abs(fuv * 2.0 - 1.0);

    // Organic drift driven by treble + mouse motion vector
    let drift = vec2<f32>(
        fbm(sampleUV * 8.0 + time * 0.1, 2),
        fbm(sampleUV * 8.0 + time * 0.13 + 5.0, 2)
    ) * (0.01 + treble * 0.02) + mouseVel * 0.25;

    // Chromatic aberration scaled by bass envelope and mouse velocity
    let caStr = 0.003 * (1.0 + bassSmooth) + mouseSpeed * 0.02;
    var col = chromaticShift(clamp(sampleUV + drift, vec2<f32>(0.0), vec2<f32>(1.0)), caStr);

    // Depth-aware compositing and radial fade around the singularity
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let depthFade = mix(0.7, 1.0, depth);
    let fade = smoothstep(0.0, 0.1, radius);
    let warpDistort = abs(r_new - radius) + abs(a_new - angle);

    // ACES tone map with audio-reactive exposure boost
    col = acesToneMap(col * (0.9 + mids * 0.2 + bassSmooth * 0.15) * depthFade);

    // Temporal feedback trail: previous frame bleeds through, increased by motion
    let trailDecay = 0.94 - treble * 0.02;
    let trailMix = 0.25 + mouseSpeed * 0.5;
    col = mix(prev.rgb * trailDecay, col, trailMix);

    // Semantic alpha encodes interaction intensity + distortion + depth
    let alpha = mix(luma(col), 0.85, smoothstep(0.5, 1.5, warpDistort)) * fade * depthFade * (0.7 + mouseSpeed * 2.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(bassSmooth, mouse.x, mouse.y, alpha));
}
