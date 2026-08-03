// ═══════════════════════════════════════════════════════════════════
//  Peter de Jong Attractor
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            chromatic-parameters, audio-morph-speed, depth-from-density,
//            sdf-tube-orbit, kaleidoscope-fold, orbit-trap-shading
//  Complexity: High
//  Description: Strange attractor density accumulation for the 2D
//    Peter de Jong map: x' = sin(a·y)−cos(b·x), y' = sin(c·x)−cos(d·y).
//    Parameters slowly morph through time, producing an infinite
//    gallery of intricate lace-work patterns — butterflies, snowflakes,
//    spirographs — as the attractor topology continuously transforms.
//    Temporal Monte Carlo builds density per frame; bass warps geometry.
//    b32 geometry pass: a 3D-lifted hero orbit is embodied as a
//    smooth-union tube SDF and sphere-traced with cone-grown LOD
//    radius; treble folds the splat plane into a kaleidoscope.
//  Upgraded: 2026-06-06 / geometry b32: 2026-08-03
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=speed_a, y=speed_b, z=glow_radius(+tube radius), w=decay

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
const HERO_PTS: u32 = 8u;        // hero-orbit anchor count
const HERO_SEGS: u32 = 7u;       // capsule segments = HERO_PTS - 1
const HERO_STRIDE: u32 = 4u;     // map iterations between anchors
const MARCH_STEPS: u32 = 36u;    // sphere-trace budget (early-exit adaptive)
const MARCH_HIT: f32 = 0.0035;   // hit epsilon
const MARCH_FAR: f32 = 6.0;      // far plane / ray escape
const SMOOTH_K: f32 = 0.14;      // smooth-union blend radius
const CONE_LOD: f32 = 0.12;      // tube radius growth per unit ray distance
const FOLD_COUNT: f32 = 6.0;     // kaleidoscope wedge count

// Per-invocation hero orbit (3D-lifted de Jong ribbon), filled in main.
var<private> heroOrbit: array<vec3<f32>, 8>;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var q = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    q = q + dot(q, q.yzx + 33.33);
    return fract((q.xx + q.yz) * q.zy);
}

fn de_jong(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    return vec2<f32>(sin(a * p.y) - cos(b * p.x), sin(c * p.x) - cos(d * p.y));
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

// Smooth-union tube chain along the hero orbit; r carries the LOD radius.
fn heroDE(p: vec3<f32>, r: f32) -> f32 {
    var d = sdCapsule(p, heroOrbit[0], heroOrbit[1], r);
    for (var k = 1u; k < HERO_SEGS; k = k + 1u) {
        d = smin(d, sdCapsule(p, heroOrbit[k], heroOrbit[k + 1u], r), SMOOTH_K);
    }
    return d;
}

// ─── 2D symmetry fold: mirror-folded kaleidoscope wedge ───
fn kalei(p: vec2<f32>, folds: f32) -> vec2<f32> {
    let seg = TAU / folds;
    let ang = abs(fract(atan2(p.y, p.x) / seg + 0.5) - 0.5) * seg;
    return vec2<f32>(cos(ang), sin(ang)) * length(p);
}

fn palette(t: f32, hueOff: f32) -> vec3<f32> {
    let h = fract(t + hueOff);
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 0.9);
    let d = vec3<f32>(0.10, 0.40, 0.65);
    return clamp(a + b * cos(TAU * (c * h + d)), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let uv    = vec2<f32>(gid.xy) / res;
    let time  = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let amp    = 1.8 + bass * 0.4;
    let sa     = 0.03 + u.zoom_params.x * 0.07;
    let sb     = 0.02 + u.zoom_params.y * 0.06;
    let a      = amp * sin(time * sa);
    let b      = amp * sin(time * sb + 1.1);
    let c      = amp * sin(time * sa * 1.33 + 2.2 + mids * 0.5);
    let d      = amp * sin(time * sb * 1.57 + 3.3);

    let glowR  = max(0.015 + u.zoom_params.z * 0.045, 0.005);
    let tubeR  = 0.018 + u.zoom_params.z * 0.05;  // glow slider also fattens the tubes
    let decay  = 0.965 + u.zoom_params.w * 0.025;

    let mouse  = u.zoom_config.yz;
    let zoom   = 1.0 + u.zoom_config.w * 1.5;
    let centre = (mouse - 0.5) * 2.0;
    let viewPos = (uv - 0.5) * (4.0 / zoom) + centre;

    // Kaleidoscope fold layer: treble blends the splat plane into wedges
    let foldAmt  = clamp(treble * 0.45, 0.0, 0.5);
    let splatPos = mix(viewPos, kalei(viewPos, FOLD_COUNT) + centre, foldAmt);

    let seed   = hash22(uv * 131.7 + vec2<f32>(fract(time * 0.031), fract(time * 0.041 + 0.5)));
    var p      = seed * 4.0 - 2.0;

    // Chromatic parameter separation: R uses a+b offset, B uses c+d offset
    var contribR = 0.0;
    var contribB = 0.0;
    let invR2   = 1.0 / (glowR * glowR);

    for (var i = 0u; i < 128u; i = i + 1u) {
        p = de_jong(p, a, b, c, d);
        let ddx = p.x - splatPos.x;
        let ddy = p.y - splatPos.y;
        let d2 = ddx * ddx + ddy * ddy;
        let g = exp(-d2 * invR2);
        // Parameter-channel split
        contribR += g * (1.0 + sin(f32(i) * 0.1 + a) * 0.3);
        contribB += g * (1.0 + cos(f32(i) * 0.1 + c) * 0.3);
    }
    contribR *= (1.0 / 128.0);
    contribB *= (1.0 / 128.0);

    let prevDensity = textureLoad(dataTextureC, coord, 0).r;
    let accumulated = mix(contribR + contribB, prevDensity, clamp(decay, 0.0, 0.999));

    // ─── Hero orbit: lift a slow orbit into 3D (z breathes with the map) ───
    var q2 = vec2<f32>(0.13, 0.27);
    var zLift = 0.0;
    for (var k = 0u; k < HERO_PTS; k = k + 1u) {
        for (var j = 0u; j < HERO_STRIDE; j = j + 1u) {
            q2 = de_jong(q2, a, b, c, d);
            zLift = mix(zLift, sin(q2.x * c + q2.y * d), 0.25);
        }
        heroOrbit[k] = vec3<f32>(q2.x * 0.55, q2.y * 0.55, zLift * 0.45);
    }

    // ─── Sphere-trace the tube chain (early-exit adaptive, cone LOD) ───
    let camAng = time * 0.11 + bass * 0.35;
    let ro = vec3<f32>(sin(camAng) * 2.1, 0.30 + mids * 0.12, cos(camAng) * 2.1);
    let fw = normalize(vec3<f32>(0.0) - ro);
    let rt = normalize(cross(fw, vec3<f32>(0.0, 1.0, 0.0)));
    let upv = cross(rt, fw);
    let ruv = (uv - 0.5) * vec2<f32>(res.x / res.y, 1.0) * (1.9 / zoom);
    let rd = normalize(fw * 1.5 + rt * ruv.x + upv * ruv.y);

    var t = 0.0;
    var hit = false;
    var glow3d = 0.0;
    for (var i = 0u; i < MARCH_STEPS; i = i + 1u) {
        let pos = ro + rd * t;
        let h = heroDE(pos, tubeR * (1.0 + t * CONE_LOD));
        glow3d += exp(-max(h, 0.0) * 14.0) * 0.012;   // proximity aura
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
        // Orbit-trap shading: stripe along the lifted orbit coordinate
        let trap = fract(pos.z * 1.6 + length(pos.xy) * 0.8 + time * 0.04);
        let baseCol = palette(trap, fract(time * 0.015) + 0.45);
        let lig = normalize(vec3<f32>(0.6, 0.8, -0.4));
        let dif = max(dot(n, lig), 0.0);
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 2.5 + bass * 2.0);
        tubeCol = baseCol * (0.25 + dif * 0.75) + palette(trap + 0.3, 0.0) * rim * (0.6 + bass * 0.5);
        tubeDepth = clamp(1.0 - t / MARCH_FAR, 0.0, 1.0);
    }

    let hueOff  = fract(time * 0.015);
    let density = clamp(accumulated * 10.0, 0.0, 1.0);
    let warmCol = palette(density, hueOff);
    let coolCol = palette(density, hueOff + 0.2);
    let chromaMix = smoothstep(0.0, 1.0, contribR - contribB + 0.5);
    var col     = mix(coolCol, warmCol, chromaMix);
    col += palette(hueOff + 0.6, 0.1) * glow3d * (1.0 + bass);   // tube aura bleed
    col = mix(col, tubeCol * 1.4, select(0.0, 0.85, hit));       // branchless composite

    let alpha    = clamp(density * 0.85 + bass * 0.12 + select(0.0, 0.55, hit) + glow3d * 0.5, 0.0, 1.0);
    let finalOut = vec4<f32>(acesToneMap(col * 1.1), alpha);

    textureStore(dataTextureA, coord, vec4<f32>(accumulated, hueOff, tubeDepth, alpha));
    textureStore(writeTexture, coord, finalOut);
    let depth = max(clamp(density * 0.9, 0.0, 1.0), tubeDepth * 0.95);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
