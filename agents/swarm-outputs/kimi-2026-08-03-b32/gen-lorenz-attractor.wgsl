// ═══════════════════════════════════════════════════════════════════
//  Lorenz Attractor
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            chromatic-lobes, audio-decay-modulation, depth-output,
//            sdf-tube-orbit, symmetry-fold, orbit-trap-shading
//  Complexity: High
//  Description: Strange attractor density accumulation via per-pixel
//    Monte Carlo orbit integration. Each pixel seeds a short Lorenz
//    trajectory near one of the two equilibrium points; Gaussian
//    kernel splatting onto the x-z projection builds the butterfly.
//    Temporal blending converges to the full attractor over frames.
//    b32 geometry pass: the true 3D Lorenz flow is embodied as a
//    smooth-union capsule chain along a live hero trajectory and
//    sphere-traced with cone-grown LOD; treble mirror-folds the
//    splat plane across the lobe axis.
//  Upgraded: 2026-06-06 / geometry b32: 2026-08-03
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=sigma(8–14), y=rho_mod(0–14), z=glow_radius(+tube radius), w=decay

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
// ─── Geometry budget constants (b32) ───
const HERO_PTS: u32 = 9u;        // hero-orbit anchor count
const HERO_SEGS: u32 = 8u;       // capsule segments = HERO_PTS - 1
const HERO_STRIDE: u32 = 6u;     // RK steps between anchors
const MARCH_STEPS: u32 = 34u;    // sphere-trace budget (early-exit adaptive)
const MARCH_HIT: f32 = 0.003;    // hit epsilon
const MARCH_FAR: f32 = 5.5;      // far plane / ray escape
const SMOOTH_K: f32 = 0.10;      // smooth-union blend radius
const CONE_LOD: f32 = 0.12;      // tube radius growth per unit ray distance
const LORENZ_SCALE: f32 = 0.042; // world-units per Lorenz-unit

// Per-invocation hero orbit (live Lorenz trajectory), filled in main.
var<private> heroOrbit: array<vec3<f32>, 9>;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn lorenz_step(p: vec3<f32>, s: f32, r: f32, b: f32) -> vec3<f32> {
    let dt = 0.010;
    return p + vec3<f32>(s * (p.y - p.x), p.x * (r - p.z) - p.y, p.x * p.y - b * p.z) * dt;
}

// ─── 3D SDF embodiment ───
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Smooth-union tube chain along the hero Lorenz orbit.
fn heroDE(p: vec3<f32>, r: f32) -> f32 {
    var d = sdCapsule(p, heroOrbit[0], heroOrbit[1], r);
    for (var k = 1u; k < HERO_SEGS; k = k + 1u) {
        d = smin(d, sdCapsule(p, heroOrbit[k], heroOrbit[k + 1u], r), SMOOTH_K);
    }
    return d;
}

// ─── 2D symmetry fold: mirror across the lobe axis (x = 0) ───
fn mirror_fold(x: f32, amt: f32) -> f32 {
    return mix(x, abs(x), amt);
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

    let sigma  = 8.0 + u.zoom_params.x * 6.0;
    let rho    = 24.0 + u.zoom_params.y * 12.0 * (1.0 + bass * 0.5);
    let beta   = 8.0 / 3.0;

    let glowR  = max(0.5 + u.zoom_params.z * 1.8 + mids * 0.4, 0.1);
    let tubeR  = 0.012 + u.zoom_params.z * 0.035;  // glow slider also fattens the tubes
    let decay  = 0.960 + u.zoom_params.w * 0.030 + bass * 0.005;

    let mouse  = u.zoom_config.yz;
    let panX   = (mouse.x - 0.5) * 24.0;
    let panZ   = (mouse.y - 0.5) * 24.0;

    // Mirror symmetry fold across the lobe axis, blended by treble
    let foldAmt = clamp(treble * 0.5, 0.0, 0.6);
    let viewX = mirror_fold((uv.x - 0.5) * 50.0 + panX, foldAmt);
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

    let prevDensity = textureLoad(dataTextureC, coord, 0).r;
    let accumulated = mix(contribR + contribB, prevDensity, clamp(decay, 0.0, 0.999));

    // ─── Hero orbit: a live 3D Lorenz trajectory, time-offset per frame ───
    var hp = vec3<f32>(0.9 + sin(time * 0.23) * 0.4, 1.0, max(rho - 1.0, 1.0));
    for (var k = 0u; k < HERO_PTS; k = k + 1u) {
        for (var j = 0u; j < HERO_STRIDE; j = j + 1u) {
            hp = lorenz_step(hp, sigma, rho, beta);
        }
        heroOrbit[k] = (hp - vec3<f32>(0.0, 0.0, rho * 0.5)) * LORENZ_SCALE;
    }

    // ─── Sphere-trace the tube chain (early-exit adaptive, cone LOD) ───
    let camAng = time * 0.09 + bass * 0.3;
    let ro = vec3<f32>(sin(camAng) * 2.0, 0.25 + mids * 0.1, cos(camAng) * 2.0);
    let fw = normalize(vec3<f32>(0.0) - ro);
    let rt = normalize(cross(fw, vec3<f32>(0.0, 1.0, 0.0)));
    let upv = cross(rt, fw);
    let ruv = (uv - 0.5) * vec2<f32>(res.x / res.y, 1.0) * 1.8;
    let rd = normalize(fw * 1.5 + rt * ruv.x + upv * ruv.y);

    var t = 0.0;
    var hit = false;
    var glow3d = 0.0;
    for (var i = 0u; i < MARCH_STEPS; i = i + 1u) {
        let pos = ro + rd * t;
        let h = heroDE(pos, tubeR * (1.0 + t * CONE_LOD));
        glow3d += exp(-max(h, 0.0) * 16.0) * 0.012;   // proximity aura
        if (h < MARCH_HIT) { hit = true; break; }
        t += h * 0.85;
        if (t > MARCH_FAR) { break; }
    }

    var tubeCol = vec3<f32>(0.0);
    var tubeDepth = 0.0;
    if (hit) {
        let pos = ro + rd * t;
        let eps = vec2<f32>(0.004, 0.0);
        let n = normalize(vec3<f32>(
            heroDE(pos + eps.xyy, tubeR) - heroDE(pos - eps.xyy, tubeR),
            heroDE(pos + eps.yxy, tubeR) - heroDE(pos - eps.yxy, tubeR),
            heroDE(pos + eps.yyx, tubeR) - heroDE(pos - eps.yyx, tubeR)));
        // Orbit-trap shading: stripe by arc position, tinted per lobe
        let trap = fract(length(pos.xy) * 2.2 + pos.z * 1.4 + time * 0.05);
        let lobeT = smoothstep(-0.25, 0.25, pos.x);
        let baseCol = mix(palette(trap, 0.3), palette(trap, 0.0), lobeT);
        let lig = normalize(vec3<f32>(0.5, 0.8, -0.5));
        let dif = max(dot(n, lig), 0.0);
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 2.5 + bass * 2.0);
        tubeCol = baseCol * (0.25 + dif * 0.75) + palette(trap + 0.5, 0.2) * rim * (0.6 + bass * 0.5);
        tubeDepth = clamp(1.0 - t / MARCH_FAR, 0.0, 1.0);
    }

    let shimmer  = treble * 0.08 * sin(accumulated * 40.0 + time * 3.0);
    let density  = clamp(accumulated * 7.0 + shimmer, 0.0, 1.0);

    // Chromatic palette: warm for right lobe, cool for left
    let warmCol = palette(density, 0.0);
    let coolCol = palette(density, 0.3);
    let lobeMix = smoothstep(-5.0, 5.0, viewX - panX);
    var col = mix(coolCol, warmCol, lobeMix);
    col += palette(density + 0.55, 0.15) * glow3d * (1.0 + bass);  // tube aura bleed
    col = mix(col, tubeCol * 1.4, select(0.0, 0.85, hit));         // branchless composite

    let alpha    = clamp(density * 0.9 + bass * 0.08 + select(0.0, 0.55, hit) + glow3d * 0.5, 0.0, 1.0);
    let finalOut = vec4<f32>(acesToneMap(col * 1.1), alpha);

    textureStore(dataTextureA, coord, vec4<f32>(accumulated, tubeDepth, glow3d, alpha));
    textureStore(writeTexture, coord, finalOut);
    let depth = max(clamp(density * 0.8, 0.0, 1.0), tubeDepth * 0.95);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
