// ═══════════════════════════════════════════════════════════════════
//  Lorenz Attractor
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            chromatic-lobes, audio-decay-modulation, depth-output,
//            mouse-gravity-well, click-shockwaves, attack-release-envelopes
//  Complexity: High
//  Description: Strange attractor density accumulation via per-pixel
//    Monte Carlo orbit integration. Each pixel seeds a short Lorenz
//    trajectory near one of the two equilibrium points; Gaussian
//    kernel splatting onto the x-z projection builds the butterfly.
//    Temporal blending converges to the full attractor over frames.
//  Upgraded: 2026-07-13
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=sigma(8–14), y=rho_mod(0–14), z=glow_radius, w=decay

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
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn lorenz_step(p: vec3<f32>, s: f32, r: f32, b: f32) -> vec3<f32> {
    let dt = 0.010;
    return p + vec3<f32>(s * (p.y - p.x), p.x * (r - p.z) - p.y, p.x * p.y - b * p.z) * dt;
}

fn palette(t: f32, hueOff: f32) -> vec3<f32> {
    let h = fract(t + hueOff);
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.25, 0.60);
    return clamp(a + b * cos(6.28318 * (c * h + d)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Attack/release envelope follower — state carried through dataTextureC -> dataTextureA
fn envFollow(prev: f32, raw: f32, attack: f32, release: f32) -> f32 {
    let delta = raw - prev;
    let rate = select(release, attack, delta > 0.0);
    return clamp(prev + delta * rate, 0.0, 2.0);
}

// Click bursts / shockwaves from ripple buffer
fn shockwave(uv: vec2<f32>, time: f32) -> f32 {
    var shock = 0.0;
    for (var i: i32 = 0; i < 50; i = i + 1) {
        let rp = u.ripples[i];
        let rippleActive = rp.w > 0.001 && rp.z > 0.0;
        let age = max(time - rp.z, 0.0);
        let d = length(uv - rp.xy);
        let wave = rp.w * exp(-age * 2.0) * exp(-(d - age * 0.2) * (d - age * 0.2) / 0.0025);
        shock = shock + wave * f32(rippleActive);
    }
    return clamp(shock, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Envelope state carried through dataTextureC -> dataTextureA
    let prevData = textureLoad(dataTextureC, coord, 0);
    let eBass   = envFollow(prevData.g, bass,   0.30, 0.03);
    let eMids   = envFollow(prevData.b, mids,   0.25, 0.035);
    let eTreble = envFollow(prevData.a, treble, 0.28, 0.04);

    // Mouse gravity well and click shockwaves
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let mouseVec = uv - mouse;
    let mouseDist = length(mouseVec);
    let gravity = 1.0 / (mouseDist + 0.08);
    let gravityWell = clamp(gravity * 0.04, 0.0, 1.0);
    let shock = shockwave(uv, time) * (1.0 + f32(mouseDown) * 0.5);

    let panX   = (mouse.x - 0.5) * 24.0;
    let panZ   = (mouse.y - 0.5) * 24.0;

    let sigma  = 8.0 + u.zoom_params.x * 6.0;
    let rho    = (24.0 + u.zoom_params.y * 12.0 * (1.0 + eBass * 0.5)) * (1.0 + gravityWell * 0.08);
    let beta   = 8.0 / 3.0;

    let glowR  = max(0.5 + u.zoom_params.z * 1.8 + eMids * 0.4, 0.1) * (1.0 - gravityWell * 0.25);
    let decay  = 0.960 + u.zoom_params.w * 0.030 + eBass * 0.005;

    let viewX = (uv.x - 0.5) * 50.0 + panX + gravityWell * 4.0;
    let viewZ =  uv.y         * 50.0 -  2.0 + panZ;

    let sq   = sqrt(beta * max(rho - 1.0, 0.1));
    let seed = hash22(uv * 73.1 + vec2<f32>(fract(time * 0.04 + 0.13), fract(time * 0.06)));
    let side = select(-1.0, 1.0, seed.x > 0.5);
    var p    = vec3<f32>(
        side * sq + (seed.x - 0.5) * 7.0,
        side * sq + (seed.y - 0.5) * 7.0,
        rho  - 1.0 + (seed.y - 0.5) * 5.0,
    );

    for (var i = 0u; i < 20u; i = i + 1u) {
        p = lorenz_step(p, sigma, rho, beta);
    }

    var contribR = 0.0;
    var contribB = 0.0;
    let invR2   = 1.0 / (glowR * glowR);
    for (var i = 0u; i < 52u; i = i + 1u) {
        p = lorenz_step(p, sigma, rho, beta);
        let dx = p.x - viewX;
        let dz = p.z - viewZ;
        let d2 = dx * dx + dz * dz;
        let g = exp(-d2 * invR2);
        // Chromatic lobe separation: right lobe → R, left lobe → B
        contribR += g * smoothstep(0.0, 2.0, p.x);
        contribB += g * smoothstep(0.0, 2.0, -p.x);
    }
    contribR *= (1.0 / 52.0);
    contribB *= (1.0 / 52.0);

    let prevDensity = prevData.r;
    let accumulated = mix(contribR + contribB + shock * 0.5, prevDensity, clamp(decay, 0.0, 0.999));

    let shimmer  = eTreble * 0.08 * sin(accumulated * 40.0 + time * 3.0);
    let density  = clamp(accumulated * 7.0 + shimmer, 0.0, 1.0);

    // Chromatic palette: warm for right lobe, cool for left
    let warmCol = palette(density, 0.0);
    let coolCol = palette(density, 0.3);
    let lobeMix = smoothstep(-5.0, 5.0, viewX - panX);
    let col = mix(coolCol, warmCol, lobeMix);

    // Temporal color feedback trail via readTexture
    let prevColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let trailBlend = 0.12 + eBass * 0.08 + shock * 0.12;
    let trail = mix(prevColor * decay, col, trailBlend);

    let alpha    = clamp(density * 0.9 + eBass * 0.08 + shock * 0.15, 0.0, 1.0);
    let finalOut = vec4<f32>(acesToneMap(trail * 1.1), alpha);

    textureStore(dataTextureA, coord, vec4<f32>(accumulated, eBass, eMids, eTreble));
    textureStore(writeTexture, coord, finalOut);
    let depth = clamp(density * 0.8, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
