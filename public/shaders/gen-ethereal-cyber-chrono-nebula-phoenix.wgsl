// ----------------------------------------------------------------
// Ethereal Cyber-Chrono Nebula-Phoenix (upgraded: live audio + HDR tamed)
// Category: generative
// ----------------------------------------------------------------
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};
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
const PI: f32 = 3.14159265359;
// Persistent halo-spring state. extraBuffer layout contract:
//   [0..132] engine-owned; this effect uses only shader state [133..137].
//   [133..134] = eased halo position, [135..136] = spring velocity,
//   [137] = initialized flag.
const HALO_POS_X: u32 = 133u;
const HALO_POS_Y: u32 = 134u;
const HALO_VEL_X: u32 = 135u;
const HALO_VEL_Y: u32 = 136u;
const HALO_INIT: u32 = 137u;
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + 0.25 * q;
}
// Hue-preserving clamp: scale by the brightest channel so hue survives.
fn huePreserveClamp(c: vec3<f32>, maxC: f32) -> vec3<f32> {
    let peak = max(c.r, max(c.g, c.b));
    let scale = min(1.0, maxC / max(peak, 1e-4));
    return c * scale;
}
// ACES filmic tonemap (Narkowicz approximation).
fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
    let num = x * (2.51 * x + vec3<f32>(0.03));
    let den = x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14);
    return clamp(num / den, vec3<f32>(0.0), vec3<f32>(1.0));
}
// Clifford-like strange attractor used as a chrono-orbit trap.
// Constants (-1.4, 1.6, 1.0, 0.7, 24 iters) preserved verbatim.
fn attractorTrap(p: vec2<f32>, t: f32, bass: f32) -> f32 {
    var z = p * 2.0;
    var trap = 100.0;
    let a = -1.4 + bass * 0.3;
    let b = 1.6 + sin(t * 0.2) * 0.1;
    let c = 1.0;
    let d = 0.7;
    let orbitTarget = vec2<f32>(0.4 * sin(t), 0.3 * cos(t));
    for (var i = 0; i < 24; i = i + 1) {
        let nx = sin(a * z.y) + c * cos(a * z.x);
        let ny = sin(b * z.x) + d * cos(b * z.y);
        z = vec2<f32>(nx, ny);
        trap = min(trap, length(z - orbitTarget));
    }
    return trap;
}

// SDF silhouette: cybernetic phoenix body, wings and tail.
// Hand-tuned constants preserved verbatim.
fn sdPhoenix(p: vec2<f32>, wingspan: f32) -> f32 {
    let body = length(vec2<f32>(p.x * 4.0, max(0.0, abs(p.y) - 0.22))) - 0.06;
    let wingY = p.y - 0.12;
    let wingX = abs(p.x) - 0.06;
    let wingUV = rot(0.25 + wingspan * 2.0) * vec2<f32>(wingX, wingY);
    let wing = length(vec2<f32>(wingUV.x * 0.35 / wingspan, wingUV.y * 2.5)) - 0.12;
    let tailUV = vec2<f32>(p.x * 2.0, p.y + 0.35);
    let tail = length(vec2<f32>(tailUV.x, max(0.0, -tailUV.y))) - 0.1 + 0.08 * sin(p.y * 20.0);
    return min(min(body, wing), tail);
}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let res = vec2<f32>(dims);
    let uv01 = vec2<f32>(id.xy) / res;
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / min(res.x, res.y);

    let time = u.config.x;
    // LIVE AUDIO: plasmaBuffer[0] = [bass, mid, treble, level] FFT bands.
    // u.config.y is the ripple COUNT (near-constant), not sound — the old
    // "audio" read was dead; bass/treble now drive the reaction for real.
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let rawMouse = u.zoom_config.yz;
    let wingspan = clamp(u.zoom_params.x, 0.05, 0.5);
    let plasma = clamp(u.zoom_params.y, 0.1, 1.0);
    let chronoMix = clamp(u.zoom_params.z, 0.0, 1.0);
    let spinRate = clamp(u.zoom_params.w, 0.0, 1.0);

    // Critically-damped spring halo: thread (0,0) integrates once per
    // frame, every thread reads the eased center so the phoenix's
    // attention glides instead of snapping to the cursor.
    let hasSpring = arrayLength(&extraBuffer) >= 138u;
    var mouse = rawMouse;
    if (id.x == 0u && id.y == 0u && hasSpring) {
        var haloPos = vec2<f32>(extraBuffer[HALO_POS_X], extraBuffer[HALO_POS_Y]);
        var haloVel = vec2<f32>(extraBuffer[HALO_VEL_X], extraBuffer[HALO_VEL_Y]);
        if (extraBuffer[HALO_INIT] < 0.5) {
            haloPos = rawMouse;
            haloVel = vec2<f32>(0.0);
        }
        let omega = 7.0;   // spring natural frequency
        let dt = 0.016;    // fixed step keeps the semi-implicit spring stable
        let accel = omega * omega * (rawMouse - haloPos) - 2.0 * omega * haloVel;
        haloVel += accel * dt;
        haloPos += haloVel * dt;
        extraBuffer[HALO_POS_X] = haloPos.x;
        extraBuffer[HALO_POS_Y] = haloPos.y;
        extraBuffer[HALO_VEL_X] = haloVel.x;
        extraBuffer[HALO_VEL_Y] = haloVel.y;
        extraBuffer[HALO_INIT] = 1.0;
    }
    if (hasSpring) {
        mouse = vec2<f32>(extraBuffer[HALO_POS_X], extraBuffer[HALO_POS_Y]);
    }

    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
    let inDepthUV = clamp(uv01, vec2<f32>(0.0), vec2<f32>(1.0));
    let inDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, inDepthUV, 0.0).r;

    // Domain-warped FBM nebula background; bass breathes through the gas.
    let warp = domainWarp(uv * 2.0 + vec2<f32>(time * 0.02), time * 0.05);
    let previous = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    var nebula = fbm(warp * 3.0, 5);
    nebula += 0.5 * fbm(warp * 6.0 + bass + mids * 0.4, 4);
    nebula = mix(previous.b, nebula, 0.32 + mids * 0.18);
    let bgColor = vec3<f32>(0.08, 0.05, 0.15) * nebula * (1.0 + bass * 2.0);

    // Strange-attractor chrono fractal: bass wobbles the orbit constant,
    // treble drives the shimmer of the chrono glow.
    let trapNow = attractorTrap(uv * 1.5, time, bass);
    let trap = mix(previous.r, trapNow, 0.65 + treble * 0.2);
    let shimmer = 0.85 + 0.3 * sin(time * 9.0 + trap * 14.0) * treble;
    let chronoGlow = exp(-trap * 6.0) * (0.5 + 0.5 * treble) * shimmer * (0.35 + chronoMix * 0.65);

    // Phoenix SDF and orbit-trap coloring.
    var p = uv;
    p = rot(mouse.x * 2.0 + time * (0.05 + spinRate * 0.35)) * p;
    let dNow = sdPhoenix(p, wingspan);
    let d = mix(previous.g, dNow, 0.78 + mids * 0.12);
    let edge = abs(d);
    let density = smoothstep(0.12, 0.0, d);
    let shell = exp(-edge * 12.0);

    // Click ripple rings: expanding shockwaves that momentarily flare
    // the wing plasma as the ring sweeps across it.
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleFlare = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        let ringRadius = age * 0.7;
        let ringDist = length(uv01 - rp.xy);
        let ring = exp(-abs(ringDist - ringRadius) * 28.0) * exp(-age * 2.2) * step(0.0, age);
        rippleFlare += ring;
    }
    rippleFlare = min(rippleFlare, 1.5);

    // Bass-driven wing plasma pulse, kicked harder by click ripples.
    let wingPulse = 1.0 + bass * 1.6 + rippleFlare * 2.0 * plasma;

    // Cosmic palette driven by orbit traps and audio.
    let pal = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(0.0, 0.33, 0.67) * PI * 2.0 + time * 0.5 - trap * 2.0);
    var phoenixColor = pal * (density + shell * 0.6 * wingPulse);
    phoenixColor += vec3<f32>(1.0, 0.4, 0.1) * chronoGlow * plasma;
    phoenixColor += vec3<f32>(1.0, 0.55, 0.2) * rippleFlare * shell * plasma * 1.5;

    // Spring-eased phoenix attention halo (was a snap-to-mouse glow).
    let mouseDist = length(uv01 - mouse);
    let mouseGlow = exp(-mouseDist * 20.0) * (0.3 + bass);
    phoenixColor += vec3<f32>(0.4, 0.8, 1.0) * mouseGlow;

    // Composite over video background.
    var color = mix(video.rgb, phoenixColor, clamp(density + shell * 0.5, 0.0, 1.0));
    color = mix(color, bgColor, 0.35 * (1.0 - density));

    // HDR taming: hue-preserving clamp at ~2.0, then ACES before store.
    color = huePreserveClamp(color, 2.0);
    color = acesTonemap(color);

    // Meaningful alpha: emission + occlusion, not forced to 1.0.
    let alpha = clamp(density + shell * 0.4 + chronoGlow * 0.2, 0.0, 1.0);

    // Depth: phoenix in front, input depth preserved where transparent.
    let depth = mix(inDepth, 0.2 + density * 0.6, clamp(density + shell * 0.5, 0.0, 1.0));

    textureStore(writeTexture, id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(trap, d, nebula, alpha));
}
