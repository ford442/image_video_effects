// ═══════════════════════════════════════════════════════════════════
//  Hyperdimensional Bismuth Lattice
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-17
//  Ideas: fold-generation hopper terraces; alternating-parity twin-boundary seams; basal cleavage sheen from fold faces; treble micro-serration on later folds; ledge-cast step shadows down the hopper stairs; fresh-cleave silver fronts that strip and regrow the oxide film
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: .x = Complexity, .y = Iridescence, .z = Twist, .w = Speed

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 50.0;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Box SDF
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

struct MapResult {
    d: f32,
    terrace: f32,
    twin: f32,
    cleavage: f32,
    serration: f32,
};

// Fractal folding space
fn map(p: vec3<f32>) -> MapResult {
    var pos = p;
    // Mouse twist
    let twist = clamp(u.zoom_params.z, 0.0, 1.0);

    // Canonical three-band audio; no reserved extraBuffer pseudo-audio.
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioMod = 1.0 + bass * 0.32 + mids * 0.12;

    if (twist > 0.0) {
        let mouse = u.zoom_config.yz;
        let aspect = u.config.z / max(u.config.w, 1.0);
        let mouseWorld = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
        let r = length(pos.xy - mouseWorld);
        let a = twist * audioMod * exp(-r * 0.5);
        let rt = rot(a);
        let xy = vec2<f32>(pos.x * rt[0][0] + pos.y * rt[1][0], pos.x * rt[0][1] + pos.y * rt[1][1]);
        pos.x = xy.x;
        pos.y = xy.y;
    }

    // Audio reactivity for scale
    let pulse = 1.0 + (bass * 0.1);

    // Fractal iterations
    let complexity = clamp(u.zoom_params.x, 0.0, 1.0);
    let iterCount = 4 + i32(round(complexity * 4.0));
    var scale = 1.0;
    var terraceDistance = MAX_DIST;
    var twinSignal = 0.0;
    var cleavageSignal = 0.0;
    var serrationSignal = 0.0;

    // Bismuth-like folding
    for (var i = 0; i < 8; i++) {
        if (i >= iterCount) { break; }

        // Idea 2 — the absolute fold planes are crystallographic twin
        // boundaries. Alternating generations reverse the stronger domain.
        let foldPlane = min(abs(pos.x), min(abs(pos.y), abs(pos.z))) / scale;
        let parity = select(0.68, 1.0, (i % 2) == 0);
        let domain = select(0.72, 1.0, pos.x * pos.y * pos.z >= 0.0);
        twinSignal = max(
            twinSignal,
            (1.0 - smoothstep(0.004, 0.035, foldPlane)) * parity * domain
        );

        pos = abs(pos) - vec3<f32>(0.5 * pulse);

        let ry = rot(PI / 4.0);
        let xz = vec2<f32>(pos.x * ry[0][0] + pos.z * ry[1][0], pos.x * ry[0][1] + pos.z * ry[1][1]);
        pos.x = xz.x;
        pos.z = xz.y;

        let rz = rot(PI / 4.0);
        let xy2 = vec2<f32>(pos.x * rz[0][0] + pos.y * rz[1][0], pos.x * rz[0][1] + pos.y * rz[1][1]);
        pos.x = xy2.x;
        pos.y = xy2.y;

        // Idea 1 — a thin box shell at every fold generation becomes a
        // hopper terrace. Early/older generations retain broader ledges.
        let generation = f32(i) / 7.0;
        let ledgeWidth = mix(0.105, 0.026, generation);
        let outer = sdBox(pos, vec3<f32>(0.5 + ledgeWidth));
        let inner = sdBox(pos, vec3<f32>(max(0.08, 0.5 - ledgeWidth * 0.62)));
        let faceAbs = abs(pos);
        let faceMax = max(faceAbs.x, max(faceAbs.y, faceAbs.z));
        let faceMin = min(faceAbs.x, min(faceAbs.y, faceAbs.z));
        let faceMid = faceAbs.x + faceAbs.y + faceAbs.z - faceMax - faceMin;

        // Idea 4 — later fold generations grow tiny saw teeth along their
        // edges. Early generations skip the work; a triangle wave avoids
        // another transcendental in this hot map.
        var lateFold = 0.0;
        var edgeBand = 0.0;
        var tooth = 0.0;
        var serratedShell = max(outer, -inner);
        if (i >= 4) {
            lateFold = smoothstep(0.42, 1.0, generation);
            edgeBand = smoothstep(0.27, 0.48, faceMid);
            tooth = 1.0 - abs(fract(dot(pos, vec3<f32>(1.0, 1.0, -1.0)) * 23.0
                                    + f32(i) * 0.37) * 2.0 - 1.0);
            let toothDepth = mix(0.010, 0.032, clamp(treble, 0.0, 1.0));
            serratedShell -= toothDepth * lateFold * edgeBand * tooth;
        }
        let ledge = serratedShell / scale;
        terraceDistance = min(terraceDistance, ledge);

        // Idea 3 geometry — broad fold-face interiors identify basal cleavage
        // planes; the view/light-dependent sheen itself is applied in shading.
        let faceInterior = smoothstep(0.045, 0.22, faceMax - faceMid);
        let onLedge = 1.0 - smoothstep(0.002, 0.024, abs(ledge));
        cleavageSignal = max(cleavageSignal, faceInterior * onLedge);
        serrationSignal = max(
            serrationSignal,
            lateFold * edgeBand * tooth * onLedge * (0.35 + 0.65 * clamp(treble, 0.0, 1.0))
        );

        pos = pos * 2.0;
        scale = scale * 2.0;
    }

    let coreDistance = sdBox(pos, vec3<f32>(0.5)) / scale;
    let distance = min(coreDistance, terraceDistance);
    let terraceSignal = 1.0 - smoothstep(0.002, 0.022, abs(terraceDistance));
    return MapResult(distance, terraceSignal, twinSignal, cleavageSignal, serrationSignal);
}

// Idea 5 — short soft-shadow march toward the key light, so each upper
// hopper ledge throws a crisp step shadow onto the terrace below it.
fn ledgeShadow(ro: vec3<f32>, rd: vec3<f32>) -> f32 {
    var res = 1.0;
    var t = 0.02;
    for (var i = 0; i < 10; i++) {
        let h = map(ro + rd * t).d;
        res = min(res, 10.0 * h / t);
        t += clamp(h, 0.015, 0.16);
        if (res < 0.02 || t > 1.6) { break; }
    }
    return clamp(res, 0.0, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy).d - map(p - e.xyy).d,
        map(p + e.yxy).d - map(p - e.yxy).d,
        map(p + e.yyx).d - map(p - e.yyx).d
    );
    return normalize(n);
}

// Branchless cosine palette for thin-film interference
fn palette(t: f32, iridescence: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557) + vec3<f32>(iridescence);
    return a + b * cos(2.0 * PI * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp(
        (x * (a * x + b)) / (x * (c * x + d) + e),
        vec3<f32>(0.0),
        vec3<f32>(1.0)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let speed = clamp(u.zoom_params.w, 0.0, 1.0);
    let t = u.config.x * (0.5 + speed * 1.5);

    // Normalized pixel coordinates (from -1 to 1)
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    // Ray origin and direction
    let ro = vec3<f32>(0.0, 0.0, -3.0 + t);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Raymarching
    var d0 = 0.0;
    var p = ro;
    var i = 0;
    for (i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * d0;
        let dS = map(p).d;
        d0 += dS;
        if (dS < SURF_DIST || d0 > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.0);
    var alpha = 0.0;
    var depth = 0.0;

    if (d0 < MAX_DIST) {
        let surface = map(p);
        let n = calcNormal(p);
        let v = -rd; // View direction
        let ndotv = max(dot(n, v), 0.0);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let ndotl = max(dot(n, lightDir), 0.0);
        let h = normalize(lightDir + v);
        let spec = pow(max(dot(n, h), 0.0), 32.0);

        // Idea 6 — fresh-cleave fronts: periodic slabs sweep toward the
        // camera; just behind each front the oxide is stripped to bare
        // silver-pink bismuth, and the film (and its interference order)
        // regrows with age until the next front arrives. Bass widens the cleave.
        let oxideAge = fract(p.z * 0.2 + t * 0.09);
        let filmGrowth = smoothstep(0.0, 0.16, oxideAge);
        let freshEdge = 1.0 - smoothstep(0.0, 0.05 + clamp(plasmaBuffer[0].x, 0.0, 1.0) * 0.03, oxideAge);
        let bareMetal = vec3<f32>(0.86, 0.78, 0.80);

        // Iridescent coloring
        let iridescence = clamp(u.zoom_params.y, 0.0, 1.0);
        // Base color based on normal, view, and depth
        let phase = ndotv * 2.0 + length(p) * 0.1 + oxideAge * 0.18;
        let albedo = mix(bareMetal, palette(phase, iridescence), filmGrowth);
        let terraceFilm = palette(
            phase + surface.terrace * 0.17 + plasmaBuffer[0].y * 0.08,
            iridescence
        );
        let twinFilm = palette(
            phase + 0.34 + plasmaBuffer[0].z * 0.12,
            iridescence
        );

        // Simple Ambient Occlusion
        let aoStep = 0.1;
        let ao = clamp(map(p + n * aoStep).d / aoStep, 0.0, 1.0);

        // Pointable Idea 5: ledge-cast step shadows on the direct light only.
        var lit = 1.0;
        if (ndotl > 0.0) { lit = ledgeShadow(p + n * 0.004, lightDir); }
        let stepShadow = mix(0.35, 1.0, lit);
        col = albedo * (ndotl * 0.8 * stepShadow + 0.2) * ao + vec3<f32>(spec) * 0.5 * stepShadow;
        // Pointable Idea 1: broad outer-generation hopper ledges catch film.
        col += terraceFilm * surface.terrace * (0.3 + spec * 0.65);
        // Pointable Idea 2: alternating fold domains share spectral seams.
        col += twinFilm * surface.twin * (0.22 + pow(1.0 - ndotv, 3.0));
        // Pointable Idea 3: basal cleavage sheen follows broad fold faces,
        // brightening only where the geometric normal resolves to one face.
        let foldFace = smoothstep(0.68, 0.96, max(abs(n.x), max(abs(n.y), abs(n.z))));
        let cleavageLobe = surface.cleavage * foldFace
            * (0.35 * pow(1.0 - ndotv, 2.0) + 0.65 * pow(max(dot(n, h), 0.0), 12.0));
        col += mix(vec3<f32>(0.72, 0.82, 0.92), terraceFilm, 0.42) * cleavageLobe * 0.62;
        // Pointable Idea 4: treble-cut late-generation teeth catch a fine rim.
        col += twinFilm * surface.serration * (0.08 + 0.22 * plasmaBuffer[0].z);
        // Pointable Idea 6: film terms fade in with oxide age; the cleave
        // edge itself catches a bright bare-metal glint.
        col = mix(albedo * (ndotl * 0.8 * stepShadow + 0.2) * ao + vec3<f32>(spec) * 0.5 * stepShadow,
                  col, filmGrowth);
        col += bareMetal * freshEdge * (0.18 + spec * 0.8) * stepShadow;

        // Fog
        col = mix(col, vec3<f32>(0.05, 0.05, 0.1), 1.0 - exp(-0.02 * d0 * d0));
        depth = clamp(1.0 - d0 / MAX_DIST, 0.0, 1.0);
        alpha = clamp(
            0.58 + depth * 0.28 + surface.terrace * 0.08 + surface.twin * 0.06
                + surface.cleavage * 0.025 + surface.serration * 0.025,
            0.0,
            1.0
        );
    }

    let coord = vec2<i32>(id.xy);
    let display = acesToneMap(col);
    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(display, alpha));
}
