// ═══════════════════════════════════════════════════════════════════
//  4D Projection Dream Weavers
//  Category: generative
//  Description: Smooth, continuous slicing and projection through
//  higher-dimensional fractals. Mouse controls navigation through
//  the extra two dimensions. Audio affects fractal parameters.
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: Julia DE filaments on the true set boundary; hypercube fold-crease lattice coloured by fold count; 4D-space weave skewed by the rotations
//  A packing: raw HDR peak-hold history RGB, a = coverage (C.a unread; ACES on display only)
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

// Palette escape budget stays maxIter; the DE orbit keeps going to this depth.
const JULIA_DE_ITERS: i32 = 20;
const JULIA_DE_BAIL: f32 = 64.0;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Same four rotations, same order and angles, as the p4 chain in main().
fn rotChain(v: vec4<f32>, aXW: f32, aYZ: f32, aZW: f32, aXY: f32) -> vec4<f32> {
    return rot4XY(rot4ZW(rot4YZ(rot4XW(v, aXW), aYZ), aZW), aXY);
}

// 4D rotation in the XW plane
fn rot4XW(v: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        c * v.x - s * v.w,
        v.y,
        v.z,
        s * v.x + c * v.w
    );
}

// 4D rotation in the YZ plane
fn rot4YZ(v: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        v.x,
        c * v.y - s * v.z,
        s * v.y + c * v.z,
        v.w
    );
}

// 4D rotation in the ZW plane
fn rot4ZW(v: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        v.x,
        v.y,
        c * v.z - s * v.w,
        s * v.z + c * v.w
    );
}

// 4D rotation in the XY plane
fn rot4XY(v: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        c * v.x - s * v.y,
        s * v.x + c * v.y,
        v.z,
        v.w
    );
}

// 4D Mandelbulb-like iteration (quaternion julia variant projected from 4D)
// Returns (palette iter, palette r, DE in 4D units, 1 if the DE orbit escaped).
// .xy are exactly HEAD's result: iteration of the first r > 4 inside maxIter,
// or (maxIter, |z| after maxIter steps).
fn julia4D(c4: vec4<f32>, z0: vec4<f32>, maxIter: i32) -> vec4<f32> {
    var z = z0;
    var dz = 1.0;
    var palIter = f32(maxIter);
    var palR = -1.0;
    var de = 1e3;
    var escaped = 0.0;
    let total = max(maxIter, JULIA_DE_ITERS);

    for (var i = 0; i < total; i++) {
        let r = length(z);
        if (palR < 0.0) {
            if (r > 4.0) {
                palIter = f32(i); palR = r;
            } else if (i == maxIter) {
                palR = r;
            }
        }
        // Idea 1: Julia DE filaments. The same orbit runs past the palette
        // budget so the estimate resolves the true boundary, not the fat
        // maxIter blob (numpy: at maxIter 7 the DE at the blob edge is 7-16 px).
        if (r > JULIA_DE_BAIL) {
            de = 0.5 * r * log(r) / dz;
            escaped = 1.0;
            break;
        }
        // Quaternion squaring: (a,b,c,d)^2 using quaternion algebra
        // z' = z^2 + c, quaternion multiplication
        let a = z.x; let b = z.y; let c = z.z; let d = z.w;
        z = vec4<f32>(
            a*a - b*b - c*c - d*d,
            2.0*a*b,
            2.0*a*c,
            2.0*a*d
        ) + c4;
        // Julia derivative w.r.t. z0: |dz'| = 2|z||dz|. HEAD added the
        // Mandelbrot "+1" (derivative w.r.t. c), which is wrong for a Julia DE.
        dz = 2.0 * r * dz;
    }
    let rEnd = length(z);
    if (palR < 0.0) { palR = rEnd; }
    // Late escapers that ran out of iterations before the big bailout.
    if (escaped < 0.5 && rEnd > 4.0) {
        de = 0.5 * rEnd * log(rEnd) / dz;
        escaped = 1.0;
    }
    return vec4<f32>(palIter, palR, de, escaped);
}

struct HyperFold {
    shellD: f32,   // screen distance to HEAD's |z.xyz| = 1 shell
    crease: f32,   // fold-crease line intensity 0..1
    folds: f32,    // number of box + sphere folds taken
};

fn tangentDist(g: f32, grad: vec2<f32>) -> f32 {
    return abs(g) / max(length(grad), 1e-5);
}

// 4D hypercube lattice escape
// Idea 2: hypercube fold lattice. tA / tB are dz/d(screen x) and dz/d(screen y)
// in the fractal's own coordinates; they ride through every fold so the
// crease and shell distances below are true screen-space distances.
fn hypercubeFractal(p4: vec4<f32>, t: f32, bass: f32, mids: f32, tA0: vec4<f32>, tB0: vec4<f32>) -> HyperFold {
    var z = p4;
    var tA = tA0;
    var tB = tB0;
    let fold = 1.2 + bass * 0.3;
    let lineW = 0.004;
    var crease = 0.0;
    var folds = 0.0;

    for (var i = 0; i < 6; i++) {
        // Crease hyperplanes |z_c| = fold of the first two live folds
        // (iteration 0 almost never folds: |p4 * 0.5| < 1.2). Later ones are too dense.
        if (i >= 1 && i <= 2) {
            let sg = sign(z);
            let g = abs(z) - vec4<f32>(fold);
            let dx = tangentDist(g.x, vec2<f32>(sg.x * tA.x, sg.x * tB.x));
            let dy = tangentDist(g.y, vec2<f32>(sg.y * tA.y, sg.y * tB.y));
            let dzc = tangentDist(g.z, vec2<f32>(sg.z * tA.z, sg.z * tB.z));
            let dw = tangentDist(g.w, vec2<f32>(sg.w * tA.w, sg.w * tB.w));
            let dmin = min(min(dx, dy), min(dzc, dw));
            let weight = select(0.55, 1.0, i == 1);
            crease = max(crease, weight * smoothstep(lineW, 0.0, dmin));
        }
        let outside = abs(z) > vec4<f32>(fold);
        let flip = select(vec4<f32>(1.0), vec4<f32>(-1.0), outside);
        folds += dot(select(vec4<f32>(0.0), vec4<f32>(1.0), outside), vec4<f32>(1.0));
        tA *= flip;
        tB *= flip;
        // Box fold in 4D
        z = clamp(z, vec4<f32>(-fold), vec4<f32>(fold)) * 2.0 - z;
        // Sphere fold
        let r2 = dot(z, z);
        let minR2 = 0.4 + mids * 0.2;
        let fixedR2 = 1.0;
        if (r2 < minR2) {
            tA *= fixedR2 / minR2;
            tB *= fixedR2 / minR2;
            z *= fixedR2 / minR2;
            folds += 1.0;
        } else if (r2 < fixedR2) {
            // Inversion Jacobian: (I - 2 z z^T / r2) * fixedR2 / r2
            tA = (tA - z * (2.0 * dot(z, tA) / r2)) * (fixedR2 / r2);
            tB = (tB - z * (2.0 * dot(z, tB) / r2)) * (fixedR2 / r2);
            z *= fixedR2 / r2;
            folds += 1.0;
        }
        // Scale and offset
        let sc = 1.5 + bass * 0.3;
        tA = tA * sc + tA0;
        tB = tB * sc + tB0;
        z = z * sc + p4;
    }
    let lz = max(length(z.xyz), 1e-5);
    let n = z.xyz / lz;
    let shellD = tangentDist(lz - 1.0, vec2<f32>(dot(n, tA.xyz), dot(n, tB.xyz)));
    return HyperFold(shellD, crease, folds);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvA = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let zoomLevel     = u.zoom_params.x * 2.0 + 0.5;   // 0.5..2.5
    let rotSpeed      = u.zoom_params.y * 0.4 + 0.05;   // 0.05..0.45
    let colorShift    = u.zoom_params.z;                 // 0..1
    let detailLevel   = u.zoom_params.w;                 // 0..1

    // Clicks kick the hyperslice phase without changing persistent state.
    let aspectFix = vec2<f32>(aspect, 1.0);
    var phaseKick = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = t - ripple.z;
        if (age < 0.0 || age > 2.2) { continue; }
        let front = abs(length((uv - ripple.xy) * aspectFix) - age * 0.68);
        phaseKick += exp(-front * 58.0) * (1.0 - age / 2.2);
    }

    // Mouse controls the W and extra dimension navigation
    let mousePos = vec2<f32>(u.zoom_config.y - 0.5, u.zoom_config.z - 0.5);
    let w_dim = mousePos.x * PI * 1.5; // extra dimension W from mouse X
    let v_dim = mousePos.y * PI * 1.5; // extra dimension V from mouse Y

    // Scale UV into 4D space
    let transport = vec2<f32>(sin(t * (1.7 + rotSpeed * 2.0)), cos(t * (1.3 + rotSpeed))) * (0.08 + bass * 0.025);
    let xy = (uvA + transport) / zoomLevel;

    // 4D point: XY from screen, ZW from time and mouse
    var p4 = vec4<f32>(
        xy.x,
        xy.y,
        cos(t * (rotSpeed * 0.5 + 0.35) + w_dim + phaseKick * 0.35) * (0.8 + mids * 0.3),
        sin(t * (rotSpeed * 0.4 + 0.28) + v_dim - phaseKick * 0.28) * (0.8 + bass * 0.3)
    );

    // Apply 4D rotations driven by time and audio
    p4 = rot4XW(p4, t * rotSpeed + bass * 0.5);
    p4 = rot4YZ(p4, t * rotSpeed * 0.7 + mids * 0.3);
    p4 = rot4ZW(p4, t * rotSpeed * 0.5 + treble * 0.4);
    p4 = rot4XY(p4, t * rotSpeed * 0.3);

    // Screen axes carried into 4D: p4 is linear in uvA (z/w are per-frame
    // constants), so d p4 / d uvA = rotChain(e_x | e_y) / zoomLevel.
    let aXW = t * rotSpeed + bass * 0.5;
    let aYZ = t * rotSpeed * 0.7 + mids * 0.3;
    let aZW = t * rotSpeed * 0.5 + treble * 0.4;
    let aXY = t * rotSpeed * 0.3;
    let ex4 = rotChain(vec4<f32>(1.0, 0.0, 0.0, 0.0), aXW, aYZ, aZW, aXY) / zoomLevel;
    let ey4 = rotChain(vec4<f32>(0.0, 1.0, 0.0, 0.0), aXW, aYZ, aZW, aXY) / zoomLevel;

    // Julia set constant: slowly navigates 4D parameter space
    let juliaC = vec4<f32>(
        -0.1 + sin(t * 0.11 + bass * 0.5) * 0.3,
        0.65 + cos(t * 0.07 + mids * 0.3) * 0.15,
        sin(t * 0.09 + w_dim * 0.5) * 0.2,
        cos(t * 0.13 + v_dim * 0.5) * 0.15
    );

    let maxIter = i32(4.0 + detailLevel * 8.0 + bass * 2.0);
    let juliaResult = julia4D(juliaC, p4, maxIter);
    let juliaIter = juliaResult.x;
    let juliaR    = juliaResult.y;
    // Idea 1: DE converted to screen units (rotations are isometries).
    let juliaDE   = juliaResult.z * zoomLevel;
    let filament  = exp(-juliaDE / 0.004) * juliaResult.w;

    // Hypercube fractal for structural detail
    let hcScale = 0.5 + treble * 0.2;
    let hyper = hypercubeFractal(p4 * hcScale, t, bass, mids, ex4 * hcScale, ey4 * hcScale);

    // Coloring: smooth iteration count + exterior distance
    let smoothIter = juliaIter + 1.0 - log2(log2(juliaR + 1.0) + 1.0);
    let normIter = smoothIter / f32(maxIter);

    // Ethereal color palette
    let hueBase = colorShift + normIter * 1.5 + t * 0.03;
    let r = 0.5 + 0.5 * cos(hueBase * TAU + 0.0 + bass * 1.0);
    let g = 0.5 + 0.5 * cos(hueBase * TAU + 2.094 + mids * 0.8);
    let b = 0.5 + 0.5 * cos(hueBase * TAU + 4.189 + treble * 1.2);
    var color = vec3<f32>(r, g, b);

    // Interior: deep dark with inner glow
    if (juliaIter >= f32(maxIter)) {
        let innerGlow = exp(-length(p4) * 2.0) * (0.3 + bass * 0.4);
        color = vec3<f32>(0.05, 0.02, 0.08) + vec3<f32>(0.2, 0.1, 0.5) * innerGlow;
    }

    // Hypercube structural overlay
    // Idea 2: shell + fold creases as screen-true lines, no treble gate
    // (HEAD: * treble * 0.5 -> invisible at audio 0), hue stepped by fold count.
    let shellLine = smoothstep(0.004, 0.0, hyper.shellD);
    let structuralLine = max(shellLine, hyper.crease) * (0.3 + treble * 0.5);
    let foldHue = colorShift + hyper.folds * 0.085 + t * 0.03;
    let foldCol = 0.5 + 0.5 * cos(TAU * (vec3<f32>(foldHue) + vec3<f32>(0.0, 0.333, 0.667)));
    color += mix(vec3<f32>(0.8, 0.9, 1.0), foldCol, 0.7 * hyper.crease) * structuralLine;

    // Velocity-stretched lattice afterimages are analytic projections of the
    // current hyperslice, not additional fractal evaluations.
    let transportVelocity = vec2<f32>(
        cos(t * (1.7 + rotSpeed * 2.0)) * (1.7 + rotSpeed * 2.0),
        -sin(t * (1.3 + rotSpeed)) * (1.3 + rotSpeed)
    );
    let velocityDir = normalize(transportVelocity + vec2<f32>(0.001));
    // Idea 3: 4D-space weave. The two families are hyperplanes p4.x = n·π/k and
    // p4.y = n·π/k of the rotated 4D point; their screen gradients are
    // (ex4.x, ey4.x) and (ex4.y, ey4.y), so XW / YZ rotations shear them off
    // perpendicular and spread a family as its axis turns edge-on.
    // k = 34 * 1.3 (default zoom) keeps HEAD's spacing and width unrotated.
    let weaveK = 44.2;
    let gradX = length(vec2<f32>(ex4.x, ey4.x)) * weaveK;
    let gradY = length(vec2<f32>(ex4.y, ey4.y)) * weaveK;
    let lagStep4 = ex4 * velocityDir.x + ey4 * velocityDir.y;
    var latticeTrail = 0.0;
    for (var li = 0; li < 4; li++) {
        let lag = f32(li) * 0.028;
        let lp = p4 - lagStep4 * lag;
        let dX = abs(sin(lp.x * weaveK)) / max(gradX, 1e-4);
        let dY = abs(sin(lp.y * weaveK)) / max(gradY, 1e-4);
        let lattice = min(dX, dY);
        latticeTrail += smoothstep(0.12 / 34.0, 0.0, lattice) * (1.0 - f32(li) * 0.2);
    }
    color += vec3<f32>(0.2 + treble * 0.3, 0.45, 1.0) * latticeTrail * 0.12;

    // Dimensional depth fog: further W/V coordinates are hazier
    let dimFog = 1.0 - exp(-abs(p4.w) * 0.8);
    color = mix(color, vec3<f32>(0.05, 0.03, 0.1), dimFog * 0.4);

    // Edge sharpening: bright boundary between inside/outside.
    // Idea 1: HEAD's smoothstep(maxIter-1.5, maxIter-0.5, iter) was 1 on every
    // interior pixel (flat cream interior); the DE filament hugs the real edge.
    color += vec3<f32>(1.0, 0.95, 0.8) * filament * (0.9 + mids * 0.4);

    // Exact history load at the advected texel (HEAD filtered rgba32float).
    let historyUV = clamp(uv - velocityDir * (0.004 + rotSpeed * 0.008), vec2<f32>(0.002), vec2<f32>(0.998));
    let resI = vec2<i32>(res);
    let historyCoord = clamp(vec2<i32>(floor(historyUV * res)), vec2<i32>(0), resI - vec2<i32>(1));
    let advectedPrev = textureLoad(dataTextureC, historyCoord, 0);
    let temporal = clamp(max(color, advectedPrev.rgb * 0.9), vec3<f32>(0.0), vec3<f32>(5.0));

    // Semantic alpha: slice coverage (set interior, filament, creases) plus
    // how slowly the exterior escaped; far W haze thins it.
    let interiorMask = select(0.0, 1.0, juliaIter >= f32(maxIter));
    let coverage = max(max(interiorMask, filament), structuralLine);
    let alpha = clamp((coverage + clamp(normIter, 0.0, 1.0) * 0.65 + latticeTrail * 0.1) * (1.0 - dimFog * 0.25), 0.15, 1.0);
    textureStore(dataTextureA, global_id.xy, vec4<f32>(temporal, alpha));

    // Depth: near = 1 on the set and its filament, exterior recedes with escape speed.
    let setNear = max(max(interiorMask, filament), clamp(normIter, 0.0, 1.0) * 0.7);
    let generatedDepth = clamp(0.15 + setNear * 0.7 - dimFog * 0.12, 0.0, 1.0);
    textureStore(writeTexture, global_id.xy, vec4<f32>(acesToneMap(temporal), alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(generatedDepth, 0.0, 0.0, 0.0));
}
