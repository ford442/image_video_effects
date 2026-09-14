// ═══════════════════════════════════════════════════════════════════
//  Prismatic Bismuth Lattice
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: hopper terrace ledges (concentric square step grooves on each skeletal box face); oxide tarnish-order thin film (Bi2O3 thickness grows toward outer terraces, RGB wavelengths, clicks launch oxidation fronts)
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Complexity, .y = Iridescence, .z = Crystal Scale, .w = Fog Density
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Analytic inverse of acesToneMap so display-space history in C decodes back to linear.
fn acesInverse(yIn: vec3<f32>) -> vec3<f32> {
    let y = clamp(yIn, vec3<f32>(0.0), vec3<f32>(0.98));
    let qa = 2.43 * y - vec3<f32>(2.51);
    let qb = 0.59 * y - vec3<f32>(0.03);
    let disc = max(qb * qb - 4.0 * qa * (0.14 * y), vec3<f32>(0.0));
    return max((-qb - sqrt(disc)) / (2.0 * qa), vec3<f32>(0.0));
}

fn iterCount(complexity: f32) -> i32 {
    // Complexity default 3 -> 4 fold iterations (the original fixed count).
    return clamp(i32(round(complexity)) + 1, 2, 7);
}

// Bismuth hopper crystal distance estimator
fn bismuthDE(pos: vec3<f32>, time: f32, audioReact: f32) -> vec2<f32> {
    let crystalScale = max(u.zoom_params.z, 0.1);
    var p = pos / crystalScale;
    let scale = 1.5 + audioReact * 0.2;
    var d = 1e10;
    var id = 0.0;
    let iters = iterCount(u.zoom_params.x);

    // Fractal folding for hopper growth patterns
    for (var i = 0; i < iters; i = i + 1) {
        p = abs(p) - vec3<f32>(0.5, 0.5, 0.5) * scale;

        // Rotate
        let c = cos(time * 0.1);
        let s = sin(time * 0.1);
        p = vec3<f32>(c*p.x - s*p.z, p.y, s*p.x + c*p.z);

        // Hopper stepping (staircase structure)
        let stepSize = 0.2;
        p -= round(p / stepSize) * stepSize * 0.1;

        // Box distance
        let q = abs(p) - vec3<f32>(0.4);
        let boxD = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);

        if (boxD < d) {
            d = boxD;
            id = f32(i);
        }
    }

    return vec2<f32>(d * 0.5 * crystalScale, id);
}

// Re-runs the fold and returns the local frame point of the winning hopper box.
fn bismuthLocal(pos: vec3<f32>, time: f32, audioReact: f32) -> vec3<f32> {
    let crystalScale = max(u.zoom_params.z, 0.1);
    var p = pos / crystalScale;
    let scale = 1.5 + audioReact * 0.2;
    var d = 1e10;
    var local = p;
    let iters = iterCount(u.zoom_params.x);
    for (var i = 0; i < iters; i = i + 1) {
        p = abs(p) - vec3<f32>(0.5, 0.5, 0.5) * scale;
        let c = cos(time * 0.1);
        let s = sin(time * 0.1);
        p = vec3<f32>(c*p.x - s*p.z, p.y, s*p.x + c*p.z);
        p -= round(p / 0.2) * 0.2 * 0.1;
        let q = abs(p) - vec3<f32>(0.4);
        let boxD = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
        if (boxD < d) {
            d = boxD;
            local = p;
        }
    }
    return local;
}

// Idea 1: hopper terrace ledges. Bismuth hopper crystals grow edges faster than
// face centers, leaving concentric square stair-steps on every face. Returns
// (groove darkness, terrace level 0..1 from center to rim).
fn hopperTerrace(local: vec3<f32>) -> vec2<f32> {
    let a = abs(local);
    // Dominant axis = face the point lies on; the other two span the face.
    var face = vec2<f32>(a.y, a.z);
    if (a.y >= a.x && a.y >= a.z) {
        face = vec2<f32>(a.x, a.z);
    } else if (a.z >= a.x && a.z >= a.y) {
        face = vec2<f32>(a.x, a.y);
    }
    let cheb = max(face.x, face.y) / 0.4; // 0 at face center, 1 at rim
    let steps = 5.0;
    let s = cheb * steps;
    let edge = abs(fract(s) - 0.5) * 2.0; // 1 on ledge line, 0 mid-terrace
    let groove = smoothstep(0.75, 0.98, edge);
    return vec2<f32>(groove, clamp(floor(s) / steps, 0.0, 1.0));
}

// Thin-film interference iridescence
fn iridescence(thickness: f32, normal: vec3<f32>, viewDir: vec3<f32>) -> vec3<f32> {
    let cosTheta = abs(dot(normal, viewDir));
    let pathLength = thickness / max(cosTheta, 0.1);

    // Phase shift colors
    return vec3<f32>(
        0.5 + 0.5 * cos(pathLength * 3.0 + 0.0),
        0.5 + 0.5 * cos(pathLength * 3.0 + 2.0),
        0.5 + 0.5 * cos(pathLength * 3.0 + 4.0)
    );
}

// Idea 2: Bi2O3 oxide tarnish order. Two-beam thin-film reflectance with Snell
// refraction into a high-index oxide (n ~ 2.45) evaluated at red/green/blue
// wavelengths; thickness in nm sweeps the gold -> magenta -> blue -> green order.
fn oxideFilm(thicknessNm: f32, normal: vec3<f32>, viewDir: vec3<f32>) -> vec3<f32> {
    let nFilm = 2.45;
    let cosI = clamp(abs(dot(normal, viewDir)), 0.0, 1.0);
    let sinT = sqrt(max(1.0 - cosI * cosI, 0.0)) / nFilm;
    let cosT = sqrt(max(1.0 - sinT * sinT, 0.0));
    let opd = 2.0 * nFilm * thicknessNm * cosT;
    let lambda = vec3<f32>(650.0, 532.0, 450.0);
    // Phase flip at the air/oxide interface (pi) -> cos term sign.
    return vec3<f32>(0.5) - 0.5 * cos(2.0 * PI * opd / lambda);
}

fn calcNormal(pos: vec3<f32>, time: f32, audioReact: f32) -> vec3<f32> {
    let eps = 0.001;
    let e = vec2<f32>(eps, 0.0);
    return normalize(vec3<f32>(
        bismuthDE(pos + e.xyy, time, audioReact).x - bismuthDE(pos - e.xyy, time, audioReact).x,
        bismuthDE(pos + e.yxy, time, audioReact).x - bismuthDE(pos - e.yxy, time, audioReact).x,
        bismuthDE(pos + e.yyx, time, audioReact).x - bismuthDE(pos - e.yyx, time, audioReact).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<u32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }

    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Complexity (zoom_params.x) and Crystal Scale (zoom_params.z) are read inside bismuthDE.
    let irid = u.zoom_params.y;
    let fogDensity = u.zoom_params.w;

    // Mouse: always steers the key light; held orbits the camera around the crystal.
    let mouse = u.zoom_config.yz;
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

    let zoom = (3.0 + irid * 2.0) * (1.0 - held * 0.15);
    let theta = time * 0.2 + held * (mouse.x - 0.5) * PI * 1.5;
    let phi = sin(time * 0.1) * 0.5 + held * (mouse.y - 0.5) * 1.2;
    let camPos = vec3<f32>(cos(theta) * cos(phi) * zoom, sin(phi) * zoom, sin(theta) * cos(phi) * zoom);

    let targetPos = vec3<f32>(0.0);
    let camForward = normalize(targetPos - camPos);
    let camRight = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), camForward));
    let camUp = cross(camForward, camRight);
    let rd = normalize(uv.x * camRight + uv.y * camUp + 1.5 * camForward);

    var t = 0.0;
    var hit = false;
    var id = 0.0;

    for (var i: i32 = 0; i < 80; i = i + 1) {
        let pos = camPos + rd * t;
        let de = bismuthDE(pos, time, bass);

        if (de.x < 0.001) {
            hit = true;
            id = de.y;
            break;
        }

        t += de.x;
        if (t > 10.0) { break; }
    }

    // Click ripples: oxidation fronts sweeping outward across the screen.
    var oxFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let age = time - r.z;
        if (age >= 0.0 && age < 2.0) {
            let dlt = (uvFull - r.xy) * vec2<f32>(aspect, 1.0);
            oxFront = max(oxFront, exp(-abs(length(dlt) - age * 0.5) * 40.0) * exp(-age * 1.5));
        }
    }

    let inputColor = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0);
    var finalRGB = inputColor.rgb;
    var coverage = 0.0;
    var depth = 0.0;

    if (hit) {
        let pos = camPos + rd * t;
        let normal = calcNormal(pos, time, bass);

        let lightDir = normalize(vec3<f32>(0.5 + (mouse.x - 0.5) * 1.5, 1.0 - (mouse.y - 0.5), 0.3));
        let diffuse = max(dot(normal, lightDir), 0.0);
        let specular = pow(max(dot(normal, normalize(lightDir - rd)), 0.0), 64.0);

        // Hopper terraces in the winning box's local frame.
        let local = bismuthLocal(pos, time, bass);
        let terrace = hopperTerrace(local);

        let thickness = (5.0 + id * 2.0 + mids * 5.0) * (0.5 + irid) + oxFront * 6.0; // Audio-reactive iridescent thickness
        let iridColor = iridescence(thickness, normal, -rd);

        // Outer terraces cooled first -> thicker oxide; mids breathe the film.
        let oxideNm = 60.0 + terrace.y * 220.0 * (0.5 + irid) + id * 25.0 + mids * 40.0 + oxFront * 180.0;
        let oxide = oxideFilm(oxideNm, normal, -rd);
        let filmColor = mix(iridColor, oxide, 0.45);

        let ledgeShade = 1.0 - terrace.x * 0.55;
        let ledgeGlint = terrace.x * specular * 2.0 + terrace.x * treble * 0.25;
        let shadedColor = filmColor * (diffuse + 0.2) * ledgeShade
            + vec3<f32>(1.0) * specular * (1.0 + treble * 0.4) + vec3<f32>(ledgeGlint);

        let fogStart = clamp(7.0 - fogDensity * 10.0, 0.5, 9.0); // default 0.2 -> 5.0
        let hitAlpha = 1.0 - smoothstep(fogStart, 10.0, t);

        finalRGB = mix(inputColor.rgb, shadedColor, hitAlpha);
        coverage = hitAlpha;
        depth = clamp(1.0 - t / 10.0, 0.0, 1.0);
    }

    // Temporal Trails (exact load, display-space history decoded back to linear)
    let maxC = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);
    let prevCoord = clamp(vec2<i32>(global_id.xy), vec2<i32>(0), maxC);
    let prev = textureLoad(dataTextureC, prevCoord, 0);
    let prevColor = acesInverse(prev.rgb);
    finalRGB = mix(finalRGB, prevColor, 0.6);

    let display = acesToneMap(finalRGB * (1.0 + bass * 0.12));
    // Alpha = crystal coverage (fog-attenuated) plus lingering trail density and oxidation fronts.
    let finalAlpha = clamp(coverage * 0.85 + prev.a * 0.35 + oxFront * 0.3, 0.02, 1.0);
    let outColor = vec4<f32>(display, finalAlpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
