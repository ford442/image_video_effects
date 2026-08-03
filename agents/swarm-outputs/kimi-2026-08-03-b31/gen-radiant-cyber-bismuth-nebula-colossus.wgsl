// Radiant Cyber-Bismuth Nebula-Colossus — Category: generative
// Upgraded 2026-08-03 (swarm b31, optimizer): canonical uniforms verified,
// dead sliders (Nebula Density, Iridiscent Shift) wired LIVE, hopper-crystal
// octahedron smooth-union into the IFS bismuth lattice, kaleidoscopic
// symmetry-fold star field + volumetric nebula, adaptive steps/LOD, real depth.
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
  zoom_params: vec4<f32>,  // x=Fold Scale, y=Nebula Density, z=Audio Reactivity, w=Iridiscent Shift
  ripples: array<vec4<f32>, 50>,
};
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_DIST: f32 = 12.0;
const BASE_STEPS: i32 = 64;
const STEP_RANGE: f32 = 32.0;   // adaptive steps: 64..96 with Nebula Density
const SMIN_K: f32 = 0.25;       // smooth-union blend radius
const BOX_B: f32 = 1.0;

fn rotX(a: f32) -> mat3x3<f32> {
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, cos(a), -sin(a), 0.0, sin(a), cos(a));
}
fn rotY(a: f32) -> mat3x3<f32> {
    return mat3x3<f32>(cos(a), 0.0, sin(a), 0.0, 1.0, 0.0, -sin(a), 0.0, cos(a));
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
// 2D symmetry-fold (kaleidoscope) for the quantum-storm star field
fn kaleido(uv: vec2<f32>, segments: f32) -> vec2<f32> {
    let seg = TAU / segments;
    let a = abs((atan2(uv.y, uv.x) % seg) - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * length(uv);
}
fn starField(p: vec2<f32>) -> f32 {
    let cell = floor(p);
    let f = fract(p) - 0.5;
    let jitter = vec2<f32>(hash21(cell + 7.0), hash21(cell + 13.0)) - 0.5;
    let star = 1.0 - smoothstep(0.0, 0.08, length(f - jitter * 0.6));
    return star * step(0.9, hash21(cell));
}

// IFS bismuth lattice + smooth-union hopper-crystal octahedra
fn map(pos: vec3<f32>, folds: i32, foldScale: f32, wobble: f32) -> f32 {
    var p = pos;
    let mouse = (u.zoom_config.yz - 0.5) * 2.0; // centered scene plane, y=0 top kept
    p = p - vec3<f32>(mouse, 0.0);
    for (var i = 0; i < folds; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.8, 0.5) * foldScale;
        p = p * rotX(u.config.x * 0.1 + wobble) * rotY(u.config.x * 0.15);
    }
    let boxD = length(max(abs(p) - vec3<f32>(BOX_B), vec3<f32>(0.0))) - 0.2;
    // Bismuth hopper crystals: octahedra nested in the folded frame
    let octD = sdOctahedron(p * 0.7, 0.9) - 0.05;
    return smin(boxD, octD, SMIN_K);
}

fn calcNormal(p: vec3<f32>, folds: i32, foldScale: f32, wobble: f32) -> vec3<f32> {
    let e = vec2<f32>(0.0015, 0.0);
    let dx = map(p + e.xyy, folds, foldScale, wobble) - map(p - e.xyy, folds, foldScale, wobble);
    let dy = map(p + e.yxy, folds, foldScale, wobble) - map(p - e.yxy, folds, foldScale, wobble);
    let dz = map(p + e.yyx, folds, foldScale, wobble) - map(p - e.yyx, folds, foldScale, wobble);
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

    let uv = (vec2<f32>(pixel) - res * 0.5) / res.y;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders — all four live
    let foldScale = u.zoom_params.x;
    let nebDensity = u.zoom_params.y;
    let audioReact = u.zoom_params.z;
    let iridShift = u.zoom_params.w;

    // Adaptive budget: folds 4..6 with Fold Scale, steps 64..96 with Nebula Density
    let folds = 4 + i32(clamp(foldScale * 0.7, 0.0, 2.0));
    let steps = BASE_STEPS + i32(clamp(nebDensity * STEP_RANGE, 0.0, STEP_RANGE));
    let wobble = bass * audioReact * 0.05;

    // Orbiting camera rebuilt from mouse + time
    let camA = (u.zoom_config.y - 0.5) * 1.2 + time * 0.07;
    let dolly = 1.0 - u.zoom_config.w * 0.25; // mouse-down pushes into the storm
    let ro = rotY(camA) * vec3<f32>(0.0, 0.0, -4.5 * dolly);
    let rd = rotY(camA) * normalize(vec3<f32>(uv, 1.0));

    // Raymarch: growing epsilon (LOD) + early exits, volumetric nebula accumulation
    var t = 0.0;
    var hit = false;
    var nebula = 0.0;
    for (var i = 0; i < steps; i++) {
        let p = ro + rd * t;
        let d = map(p, folds, foldScale, wobble);
        let eps = 0.0008 * (1.0 + t * 0.5);
        if (d < eps) { hit = true; break; }
        nebula += exp(-max(d, 0.0) * 2.5) * 0.01 * nebDensity * (1.0 + bass * audioReact);
        if (nebula > 1.6 || t > MAX_DIST) { break; }
        t += d * 0.85;
    }

    var col = vec3<f32>(0.0);
    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p, folds, foldScale, wobble);
        let lig = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let dif = max(dot(n, lig), 0.0);
        let fre = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Cheap soft shadow toward the key light (hit pixels only, 8 taps)
        var shadow = 1.0;
        var st = 0.05;
        for (var s = 0; s < 8; s++) {
            let sd = map(p + lig * st, folds, foldScale, wobble);
            shadow = min(shadow, 8.0 * sd / st);
            st += clamp(sd, 0.05, 0.4);
        }
        shadow = clamp(shadow, 0.15, 1.0);

        // Iridescent thin-film palette — Iridiscent Shift is the phase driver
        let phase = iridShift * TAU + time * 0.3 + fre * 2.5;
        var irid = 0.5 + 0.5 * cos(phase + p.xyx * 2.0 + vec3<f32>(0.0, 2.0, 4.0));
        irid = mix(irid, irid.bgr, fre * 0.6); // thin-film hue flip at grazing angles
        col = irid * (0.2 + dif * shadow * 0.9);
        col += vec3<f32>(1.0, 0.2, 0.8) * bass * audioReact * 0.6 * (0.3 + fre); // auroral emissive
    }

    // Quantum-particle storm: kaleidoscopic star field + nebula haze (Nebula Density)
    let kp = kaleido(uv * 3.0 + vec2<f32>(0.0, time * 0.05), 6.0);
    let stars = starField(kp * 2.0) * (0.4 + treble * audioReact * 0.3);
    var fft = 0.0;
    if (arrayLength(&extraBuffer) > 40u) { fft = extraBuffer[5u + (gid.x + gid.y) % 32u]; }
    let nebCol = mix(vec3<f32>(0.05, 0.02, 0.12), vec3<f32>(0.4, 0.1, 0.6), nebula * 0.6 + fft * 0.2);
    col += (nebCol * nebula * (1.0 + mids * audioReact * 0.4) + vec3<f32>(0.8, 0.9, 1.0) * stars * nebDensity) * select(1.0, 0.4, hit);
    col += vec3<f32>(0.05, 0.02, 0.1) * (1.0 - length(uv)) * 0.5; // deep-space backdrop

    col = acesToneMap(col * 1.25);
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.12 + luma * 0.9, 0.0, 1.0); // semantic alpha
    let depth = select(0.0, clamp(1.0 - t / MAX_DIST, 0.0, 1.0), hit);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, nebula));
}
