// ═══════════════════════════════════════════════════════════════════
//  Crystalline Nebula-Weaver Forge
//  Category: generative
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: real crystal refraction (refract() + short interior march tinted by absorption, driven by Crystal Refraction); pulsing forge core (emissive core in the 1.5 hollow lighting the facets with 1/d² falloff, paced by Core Pulse Speed + bass); woven light threads (filaments along the fold axes, accumulated as a trap in the fold loop)
//  A packing: ACES display RGBA, a = coverage minus transmission (hit) / glow (background); C unread
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: .x = Folding Complexity, .y = Nebula Density, .z = Crystal Refraction, .w = Core Pulse Speed

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 120;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 20.0;
const BOUND_R: f32 = 3.0;   // the folded crystal lives inside this radius
const VOID_R: f32 = 1.5;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 2: forge core radius and brightness (Core Pulse Speed paces, bass kicks)
fn coreState() -> vec2<f32> {
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let rate = 0.8 + u.zoom_params.w * 4.0;
    let beat = 0.5 + 0.5 * sin(u.config.x * rate);
    let pulse = beat * beat * (3.0 - 2.0 * beat) + bass * 0.8;
    return vec2<f32>(0.28 + pulse * 0.08, 0.6 + pulse * 1.4);
}

struct Scene {
    d: f32,       // crystal ∪ core
    crystal: f32, // crystal only
    core: f32,    // core only
    thread: f32,  // Idea 3: distance to the nearest woven thread
    along: f32,   // coordinate along that thread
};

// Kaleidoscopic Iterated Function System (KIFS) fractal
fn mapScene(p_in: vec3<f32>) -> Scene {
    var p = p_in;

    // Apply mouse interaction if held
    if (u.zoom_config.w > 0.5) {
        let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
        let rot_mouse = rot2D(mouse_uv.x * PI);
        let pxz = p.xz * rot_mouse;
        p = vec3<f32>(pxz.x, p.y, pxz.y);

        let rot_mouse_y = rot2D(mouse_uv.y * PI);
        let pyz = p.yz * rot_mouse_y;
        p = vec3<f32>(p.x, pyz.x, pyz.y);
    }

    // Rotate entire structure slowly
    let t = u.config.x * u.zoom_params.w * 0.2;
    let r_base = rot2D(t);
    let pxz = p.xz * r_base;
    p = vec3<f32>(pxz.x, p.y, pxz.y);

    var scale = 1.0;
    var thread = 1e3;
    var along = 0.0;

    // Complexity mapped to zoom_params.x
    let iters = i32(floor(mix(3.0, 7.0, u.zoom_params.x)));

    for(var i = 0; i < iters; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.4, 0.5) * scale;
        let r = rot2D(PI / 4.0 + t * 0.1);
        let pxy = p.xy * r;
        p = vec3<f32>(pxy.x, pxy.y, p.z);
        let pxz2 = p.xz * rot2D(-PI / 6.0);
        p = vec3<f32>(pxz2.x, p.y, pxz2.y);

        // Idea 3: woven light threads — warp (z-running) on even folds, weft
        // (x-running) on odd folds; the trap keeps the nearest one.
        let even = (i & 1) == 0;
        let dl = select(length(p.yz), length(p.xy), even);
        if (dl < thread) {
            thread = dl;
            along = select(p.x, p.z, even) + f32(i) * 1.7;
        }

        scale *= 0.75;
    }

    // Folds and rotations are isometries and p is never scaled, so this is
    // already a true distance (HEAD divided by scale → up to ~4× overestimate).
    let d1 = length(p) - 0.2 * scale;

    // Subtractive central void
    let d2 = length(p_in) - VOID_R;
    let crystal = max(d1, -d2);

    // Idea 2: forge core floating in the hollow
    let core = length(p_in) - coreState().x;

    var s: Scene;
    s.crystal = crystal;
    s.core = core;
    s.d = min(crystal, core);
    s.thread = thread;
    s.along = along;
    return s;
}

fn crystalNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        mapScene(p + e.xyy).crystal - mapScene(p - e.xyy).crystal,
        mapScene(p + e.yxy).crystal - mapScene(p - e.yxy).crystal,
        mapScene(p + e.yyx).crystal - mapScene(p - e.yyx).crystal
    );
    return normalize(n + vec3<f32>(1e-6));
}

// Light the core casts on a point: 1/d² falloff, facing term.
fn coreLight(p: vec3<f32>, n: vec3<f32>, coreI: f32) -> vec3<f32> {
    let toCore = -p;
    let d2 = dot(toCore, toCore);
    let facing = max(dot(n, toCore * inverseSqrt(max(d2, 1e-4))), 0.0);
    return vec3<f32>(1.0, 0.55, 0.2) * coreI * facing / (d2 + 0.35);
}

// Glow seen along a ray from the core (closest-approach falloff).
fn coreGlowAlong(ro: vec3<f32>, rd: vec3<f32>, coreR: f32, coreI: f32) -> vec3<f32> {
    let tc = max(-dot(ro, rd), 0.0);
    let dist = length(ro + rd * tc);
    let g = exp(-max(dist - coreR, 0.0) * 3.0);
    return vec3<f32>(1.0, 0.5, 0.18) * coreI * g;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) + 0.5 - 0.5 * res) / res.y;
    let time = u.config.x;
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let refrAmt = clamp(u.zoom_params.z, 0.0, 1.0);
    let cs = coreState();

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching. Inside the crystal's bound the step is capped so the
    // volume terms (nebula, threads, core haze) are sampled evenly.
    var t = 0.0;
    var i = 0;
    var nebulaAcc = 0.0;
    var threadAcc = 0.0;
    var coreHaze = 0.0;
    var hitCore = false;
    var hit = false;
    let threadRate = 1.0 + u.zoom_params.w * 3.0;
    for(i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        let s = mapScene(p);
        let d = s.d;
        let inside = length(p) < BOUND_R;
        let stepLen = select(d * 0.8, min(d * 0.8, 0.2), inside);

        nebulaAcc += exp(-max(s.crystal, 0.0) * 4.0);
        if (inside) {
            // Idea 3: threads shimmer with light running along them
            let weave = 0.55 + 0.45 * sin(s.along * 6.0 - time * threadRate);
            threadAcc += 0.0008 / (s.thread * s.thread + 0.0008) * weave * stepLen;
            coreHaze += exp(-max(s.core, 0.0) * 2.5) * stepLen;
        }

        if(abs(d) < SURF_DIST) {
            hit = true;
            hitCore = s.core <= s.crystal;
            break;
        }
        if (t > MAX_DIST) { break; }
        t += stepLen;
    }

    var color = vec3<f32>(0.0);
    var alpha = 0.0;

    // Nebula accumulation (volumetric approximation)
    let nebula_density = u.zoom_params.y;
    let nebula_glow = nebulaAcc / f32(MAX_STEPS) * nebula_density * 2.0;
    let glow_color = vec3<f32>(0.2, 0.5, 1.0) * mix(0.1, 1.0, u.zoom_params.w);
    let background = vec3<f32>(0.02, 0.01, 0.05) + length(uv) * vec3<f32>(0.05, 0.02, 0.1);

    let p = ro + rd * t;
    if (hit && hitCore) {
        // Idea 2: the forge core itself — white-hot centre, orange limb
        let n = normalize(p);
        let limb = max(dot(n, -rd), 0.0);
        color = mix(vec3<f32>(1.0, 0.35, 0.08), vec3<f32>(1.0, 0.9, 0.7), limb) * cs.y * 2.0;
        alpha = 1.0 - 0.2 * (1.0 - limb);
    } else if (hit) {
        let n = crystalNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(ro - p);

        // Refraction/Iridescence (zoom_params.z)
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);
        let iridescence = 0.5 + 0.5 * cos(3.0 * p.x + vec3<f32>(0.0, 2.0, 4.0) + t * u.zoom_params.z);

        let spec = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 32.0) * (1.0 + treble);

        color = diff * vec3<f32>(0.8, 0.9, 1.0) * 0.1 + spec * vec3<f32>(1.0) + fresnel * iridescence;
        color = mix(color, glow_color, 0.3); // Mix with internal glow

        // Idea 2: facets lit by the core (1/d² falloff)
        color += coreLight(p, n, cs.y) * 0.35;

        // Idea 1: real crystal refraction — bend into the crystal, march to the
        // far face, absorb by thickness, bend out and see what lies behind.
        let ior = 1.0 + refrAmt * 0.7;
        var rdIn = refract(rd, n, 1.0 / ior);
        if (dot(rdIn, rdIn) < 1e-4) { rdIn = rd; }
        var ti = 0.004;
        for (var k = 0; k < 16; k++) {
            let di = -mapScene(p + rdIn * ti).crystal;
            if (di < SURF_DIST) { break; }
            ti += max(di, 0.002);
            if (ti > 1.2) { break; }
        }
        let pOut = p + rdIn * ti;
        let nOut = -crystalNormal(pOut); // inward-facing at the exit face, opposes rdIn
        var rdOut = refract(rdIn, nOut, ior);
        if (dot(rdOut, rdOut) < 1e-4) { rdOut = reflect(rdIn, nOut); } // total internal reflection
        let absorb = exp(-ti * vec3<f32>(3.0, 1.3, 0.5) * (1.0 + refrAmt * 3.0));
        let behind = background + coreGlowAlong(pOut, rdOut, cs.x, cs.y) + glow_color * 0.15;
        let transmit = behind * absorb * (1.0 - fresnel);
        color += transmit * refrAmt * 1.5;

        alpha = clamp(1.0 - refrAmt * 0.35 * (1.0 - fresnel), 0.3, 1.0);
    } else {
        // Deep space background with slight gradient
        color = background;
    }

    // Add volumetric nebula glow
    color += glow_color * nebula_glow;
    // Idea 2: haze around the core
    color += vec3<f32>(1.0, 0.5, 0.2) * coreHaze * cs.y * 0.12;
    // Idea 3: woven threads — gold light, mids brighten the weave
    color += vec3<f32>(1.0, 0.78, 0.4) * threadAcc * 0.25 * (0.6 + mids * 1.2);

    let display = acesToneMap(max(color, vec3<f32>(0.0)));
    if (!hit) {
        alpha = clamp(dot(display, vec3<f32>(0.299, 0.587, 0.114)) * 1.5, 0.0, 0.8);
    }
    let depth = select(0.0, clamp(1.0 - t / MAX_DIST, 0.0, 1.0), hit);

    textureStore(writeTexture, global_id.xy, vec4<f32>(display, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
