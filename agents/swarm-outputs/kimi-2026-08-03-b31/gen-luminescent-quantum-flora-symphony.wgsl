// Luminescent Quantum-Flora Symphony — Category: generative
// Upgraded 2026-08-03 (swarm b31, optimizer): canonical uniforms fix,
// smooth-union SDF flora (stem + KIFS petals + core bulb), hex-tessellation
// spore field, adaptive raymarch steps + fold LOD, real depth + dataTextureA.
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1, y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // x=Petal Complexity, y=Gravity Twist, z=Spore Density, w=Core Intensity
  ripples: array<vec4<f32>, 50>,
};
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_DIST: f32 = 10.0;
const BASE_STEPS: i32 = 40;
const STEP_RANGE: f32 = 32.0;      // adaptive steps: 40..72 with Petal Complexity
const SMIN_K: f32 = 0.22;          // smooth-union blend radius
const PETAL_R: f32 = 0.5;
const MAT_STEM: f32 = 1.0;  const MAT_PETAL: f32 = 2.0;  const MAT_CORE: f32 = 3.0;
fn rot2D(a: f32) -> mat2x2<f32> {
    return mat2x2<f32>(cos(a), -sin(a), sin(a), cos(a));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}



// 2D hex-tessellation: distance to nearest hex-cell border (spore lattice)
fn hexBorder(p: vec2<f32>) -> f32 {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let a = fract(p / r) * r - h;
    let b = fract((p + h) / r) * r - h;
    let ga = abs(a);
    let gb = abs(b);
    let da = max(dot(ga, vec2<f32>(0.8660254, 0.5)), ga.x);
    let db = max(dot(gb, vec2<f32>(0.8660254, 0.5)), gb.x);
    return 0.5 - min(da, db);
}

// SDF scene: returns vec2(distance, materialID)
fn map(p: vec3<f32>, folds: i32, petal: f32, twist: f32, bass: f32) -> vec2<f32> {
    // Gravity Twist: localized swirl around the mouse anchor (mouse pre-centered)
    let mouse = (u.zoom_config.yz - 0.5) * 2.0; // 0-1 canvas -> -1..1 scene plane, y=0 top kept
    let delta = p.xy - mouse;
    let dist2 = dot(delta, delta);
    let ang = twist * PI / (1.0 + dist2 * 4.0);
    let pw = vec3<f32>(rot2D(ang) * delta + mouse, p.z);

    // Stem: capsule from ground to bloom
    let dStem = sdCapsule(pw, vec3<f32>(0.0, -2.0, 0.0), vec3<f32>(0.0, 0.1, 0.0), 0.09);

    // Emissive core bulb
    let corePulse = 0.16 + bass * 0.05;
    let dCore = length(pw) - corePulse;

    // KIFS petal lattice (fold count = LOD from Petal Complexity)
    let t = u.config.x * 0.5;
    var pos = pw;
    var dPetal = 1000.0;
    for (var i = 0; i < folds; i++) {
        pos.y = abs(pos.y) - petal * 0.2;
        let r = rot2D(t * 0.2 + f32(i) * 0.5 + bass * 0.1);
        let xy = r * pos.xy;
        pos = vec3<f32>(xy, pos.z * 0.96);
        dPetal = smin(dPetal, length(pos) - PETAL_R, SMIN_K);
    }

    // Branchless smooth-union of primitives + material pick
    var d = smin(dStem, dCore, SMIN_K);
    d = smin(d, dPetal, SMIN_K);
    var mat = select(MAT_PETAL, MAT_STEM, dStem < dPetal);
    mat = select(mat, MAT_CORE, dCore < min(dStem, dPetal));
    return vec2<f32>(d, mat);
}

fn calcNormal(p: vec3<f32>, folds: i32, petal: f32, twist: f32, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.002, 0.0);
    let dx = map(p + e.xyy, folds, petal, twist, bass).x - map(p - e.xyy, folds, petal, twist, bass).x;
    let dy = map(p + e.yxy, folds, petal, twist, bass).x - map(p - e.yxy, folds, petal, twist, bass).x;
    let dz = map(p + e.yyx, folds, petal, twist, bass).x - map(p - e.yyx, folds, petal, twist, bass).x;
    return normalize(vec3<f32>(dx, dy, dz));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let pixel = vec2<i32>(gid.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders — all four live
    let petal = u.zoom_params.x;
    let twist = u.zoom_params.y;
    let sporeDensity = u.zoom_params.z;
    let coreInt = u.zoom_params.w;

    // Adaptive budget: folds (3..6) and march steps (40..72) scale with complexity
    let folds = 3 + i32(clamp(petal * 0.9, 0.0, 3.0));
    let steps = BASE_STEPS + i32(clamp(petal * STEP_RANGE / 5.0, 0.0, STEP_RANGE));

    // Gentle orbit camera rebuilt from mouse + time
    let camA = (u.zoom_config.y - 0.5) * 0.8 + time * 0.05;
    let rotC = rot2D(camA);
    var ro = vec3<f32>(0.0, 0.1, 3.2);
    var rd = normalize(vec3<f32>(uv, -1.6));
    ro = vec3<f32>(rotC * ro.xz, ro.y).xzy;
    rd = vec3<f32>(rotC * rd.xz, rd.y).xzy;

    // Raymarch with growing epsilon (LOD) + early exits
    var t = 0.0;
    var hit = false;
    var mat = 0.0;
    var spore = 0.0;
    for (var i = 0; i < steps; i++) {
        let p = ro + rd * t;
        let m = map(p, folds, petal, twist, bass);
        let eps = 0.0008 * (1.0 + t * 0.6);
        if (m.x < eps) { hit = true; mat = m.y; break; }
        // Spore volumetric accumulation (Spore Density), saturating early exit
        spore += exp(-max(m.x, 0.0) * 6.0) * 0.012 * sporeDensity;
        if (spore > 1.5 || t > MAX_DIST) { break; }
        t += m.x * 0.9;
    }

    var col = vec3<f32>(0.0);
    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p, folds, petal, twist, bass);
        let lig = normalize(vec3<f32>(0.7, 0.9, 0.6));
        let dif = max(dot(n, lig), 0.0);
        let fre = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        let stemCol = vec3<f32>(0.05, 0.35, 0.15);
        let petalCol = mix(vec3<f32>(0.2, 0.8, 1.0), vec3<f32>(0.9, 0.3, 1.0), 0.5 + 0.5 * sin(time + p.y * 3.0));
        let coreCol = vec3<f32>(0.9, 1.0, 0.8) * coreInt * (1.0 + bass);
        var albedo = select(petalCol, stemCol, mat < 1.5);
        albedo = select(albedo, coreCol, mat > 2.5);
        col = albedo * (0.25 + dif * 0.85);
        col += vec3<f32>(0.3, 0.9, 1.0) * fre * 0.6 * coreInt * 0.25;
    }

    // 2D hex-tessellation spore field (background + halo), LOD-gated by density
    let hexD = hexBorder(uv * 6.0 + vec2<f32>(0.0, time * 0.15));
    let hexGlow = (1.0 - smoothstep(0.0, 0.06, hexD)) * sporeDensity;
    var fft = 0.0;
    if (arrayLength(&extraBuffer) > 40u) { fft = extraBuffer[5u + (gid.x + gid.y) % 32u]; }
    let sporeCol = vec3<f32>(0.15, 0.7, 0.9) * (hexGlow * (0.4 + treble) + spore * (0.6 + fft * 0.5 + mids * 0.3));
    col += sporeCol * select(1.0, 0.35, hit);
    col += vec3<f32>(0.01, 0.03, 0.06) * (1.0 - length(uv)); // abyssal backdrop

    col = acesToneMap(col * 1.2);

    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.12 + luma * 0.9, 0.0, 1.0); // semantic alpha
    let depth = select(0.0, clamp(1.0 - t / MAX_DIST, 0.0, 1.0), hit);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, spore));
}
