// ----------------------------------------------------------------
// Acoustic Obsidian Resonator
// Category: generative
// Features: raymarched, audio-reactive, mouse-driven, upgraded-rgba
// Upgraded: 2026-11-15
// Ideas: conchoidal fracture scars (native); gold schiller sheen + convex-edge wear (§12.2E SDF curvature)
// A packing: display RGBA — ACES display RGB + semantic coverage alpha (A = same display RGBA; nothing reads C)
// Identity: tall obsidian monoliths with an octahedral cavity, domain-repeated and rotating; bass swells the
//           cavity and lights gold emissive, mids crack the surface, a held pointer pulls the lattice.
// ----------------------------------------------------------------
#include "_prelude.wgsl"

// --- HELPER FUNCTIONS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let xc = max(x, vec3<f32>(0.0));
    return clamp((xc * (2.51 * xc + vec3<f32>(0.03))) / (xc * (2.43 * xc + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

// sine-free hash (Hoskins) — the scar origin is evaluated in the march, so keep it cheap
fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var q = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    q = q + vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

// --- PER-PIXEL CONTEXT -------------------------------------------------------------------
// Everything below is constant over the 30-100 march steps of one pixel. HEAD re-derived it inside
// every map() call (two plasmaBuffer loads, a sin/cos pair for the rotation, the spacing maths);
// hoisting it here is what pays for the post-hit shading (trim round, 2026-11-15).
struct Ctx {
    rot: vec2<f32>,       // (cos, sin) of time * rotation_speed
    spacing: f32,         // domain_spacing * 5
    invSpacing: f32,
    octR: f32,            // 1.5 + bass * fracture_scale  (HEAD's cavity swell)
    mids: f32,
    scarAmp: f32,         // Idea 1 relief amplitude (fracture_scale scales it)
    held: f32,            // mouse down
    mouse10: vec2<f32>,   // mouse_uv * 10 (HEAD's pull centre)
    shock: f32,           // shockwave_force
};

fn makeCtx() -> Ctx {
    let a = u.config.x * u.zoom_params.x;
    let spacing = max(u.zoom_params.w * 5.0, 1e-3);
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    return Ctx(
        vec2<f32>(cos(a), sin(a)),
        spacing,
        1.0 / spacing,
        1.5 + bass * u.zoom_params.z,
        clamp(plasmaBuffer[0].y, 0.0, 1.0),
        0.022 * clamp(u.zoom_params.z, 0.0, 2.0),
        select(0.0, 1.0, u.zoom_config.w > 0.5),
        (u.zoom_config.yz * 2.0 - 1.0) * 10.0,
        u.zoom_params.y
    );
}

// Mouse distortion (HEAD's, unchanged; Rescue 2: normalize(p) was unguarded at p == 0)
fn pullP(pos: vec3<f32>, c: Ctx) -> vec3<f32> {
    var p = pos;
    if (c.held > 0.5) {
        let dist = length(p.xy - c.mouse10);
        let pull = exp(-dist * 0.5) * c.shock;
        p = p + p / max(length(p), 1e-4) * pull;
    }
    return p;
}

// Domain repetition -> rotation (HEAD's steps) from the pre-folded coordinate q = p/spacing + 0.5
fn localOf(q: vec3<f32>, c: Ctx) -> vec3<f32> {
    let f = fract(q) * c.spacing - vec3<f32>(0.5 * c.spacing);
    // == f.xy * rot2D(time * rotation_speed)
    return vec3<f32>(f.x * c.rot.x - f.y * c.rot.y, f.x * c.rot.y + f.y * c.rot.x, f.z);
}

// --- SDF MAP ---
fn map(pos: vec3<f32>, c: Ctx) -> f32 {
    let q = pullP(pos, c) * c.invSpacing + vec3<f32>(0.5);
    let p = localOf(q, c);

    let base_box = sdBox(p, vec3<f32>(1.0, 4.0, 1.0));
    let oct = sdOctahedron(p, c.octR);

    var d = max(base_box, -oct);

    // Fracture displacement (HEAD's mids crack). Exactly 0 when mids == 0, so the three sines are
    // skipped at silence (a uniform branch).
    if (c.mids > 0.0) {
        d += sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0) * c.mids * 0.2;
    }

    // ── Idea 1: conchoidal fracture scars (native) ────────────────────
    // Obsidian breaks along curved shells: concentric ripples that radiate from the
    // percussion point of each blow, widening as they go. Each monolith cell gets its own
    // blow origin; the shell relief is a few hundredths of a unit — enough to bend the
    // glossy reflection (below) into arcs, silent or not. `fracture_scale` scales it, so
    // all four sliders are live at silence. Only evaluated near the surface; the cell id is
    // only needed here, so the floor lives inside the branch.
    if (d < 0.2) {
        let org = (hash33(floor(q)) * 2.0 - vec3<f32>(1.0)) * vec3<f32>(1.6, 3.0, 1.6);
        let rr = length(p - org);
        d += sin(rr * 9.0 - 2.2 * sqrt(rr)) * (c.scarAmp / (1.0 + rr * 0.22));
    }
    return d;
}

// --- MAIN COMPUTE ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let uv = (vec2<f32>(id.xy) * 2.0 - res) / min(res.x, res.y);
    let cx = makeCtx();

    var ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x);
    var rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var steps = 0;
    var dEnd = 0.0;   // SDF value at the final march position (≈ the hit residual; used by the curvature tap)
    for (var i = 0; i < 100; i++) {
        let d = map(ro + rd * t, cx);
        dEnd = d;
        if (d < 0.001 || t > 50.0) { break; }
        t += d;
        steps++;
    }

    var col = vec3<f32>(0.0);
    var depth = 1.0;
    var alpha = 0.0;

    if (t < 50.0) {
        let p = ro + rd * t;
        let ao = 1.0 - f32(steps) / 100.0;

        let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
        let mids = cx.mids;
        let emissive_gold = vec3<f32>(1.0, 0.8, 0.2) * (bass * 2.0);

        // HEAD's shading, unchanged: dark glass + gold emissive where the march was cheap.
        col = mix(vec3<f32>(0.02), emissive_gold, smoothstep(0.8, 1.0, ao)) * ao;

        // Rescue 1: HEAD was black at silence (idle meanL 0.008) — the only shading input was the
        // step count, so with no bass the monoliths were invisible. Obsidian is a high-gloss glass
        // that mirrors its surroundings: a 4-tap tetrahedron normal (hit pixels only) drives
        // a Fresnel environment reflection, and the same taps give the curvature for Idea 2.
        // 4-tap tetrahedron stencil: gradient (normal) AND Laplacian from the same four map() calls.
        let e = 0.02;
        let h = e * 0.57735027;
        let t0 = map(p + h * vec3<f32>(1.0, -1.0, -1.0), cx);
        let t1 = map(p + h * vec3<f32>(-1.0, -1.0, 1.0), cx);
        let t2 = map(p + h * vec3<f32>(-1.0, 1.0, -1.0), cx);
        let t3 = map(p + h * vec3<f32>(1.0, 1.0, 1.0), cx);
        let g = vec3<f32>(1.0, -1.0, -1.0) * t0 + vec3<f32>(-1.0, -1.0, 1.0) * t1
              + vec3<f32>(-1.0, 1.0, -1.0) * t2 + vec3<f32>(1.0, 1.0, 1.0) * t3;
        let n = g / max(length(g), 1e-5);
        let ndv = clamp(dot(n, -rd), 0.0, 1.0);
        let fres = 0.04 + 0.96 * (1.0 - ndv) * (1.0 - ndv) * (1.0 - ndv) * (1.0 - ndv) * (1.0 - ndv);
        let rr = reflect(rd, n);
        // world +y is screen-DOWN in this file (uv.y runs down), so "up" is -y. A cool sky gradient
        // plus two soft-box windows: their edges sweep across the glass wherever the scar relief
        // tilts the normal, which is what makes conchoidal arcs readable on black glass.
        let up = -rr.y;
        let sky = mix(vec3<f32>(0.02, 0.025, 0.04), vec3<f32>(0.45, 0.55, 0.80), smoothstep(-0.3, 0.9, up));
        let w1 = smoothstep(0.80, 0.93, dot(rr, normalize(vec3<f32>(0.5, -0.7, -0.5))));
        let w2 = smoothstep(0.86, 0.95, dot(rr, normalize(vec3<f32>(-0.6, -0.4, -0.7))));
        let env = sky + vec3<f32>(1.0, 0.95, 0.85) * 3.0 * w1 + vec3<f32>(0.7, 0.85, 1.0) * 2.0 * w2;
        let gloss = env * fres * 1.6;

        // ── Idea 2: gold schiller + convex-edge wear (§12.2E "SDF curvature") ──
        // Gold-sheen obsidian owes its metallic schiller to oriented inclusions: layered planes
        // that flash at grazing angles. Bands run along the object's own y (they rotate with the
        // monolith) and only show where the view grazes the glass. The 4 normal taps also give
        // the SDF Laplacian κ = 1.5·(Σ₄ d(p+e·uᵢ) − 4·d(p)) / e², with d(p) = the march's final
        // residual (NOT 0: the march stops at d < 0.001, and 4·0.001/e² would swamp κ); convex
        // edges (κ·e large) are chipped bright — more so where the mids crack the glass.
        let lp = localOf(pullP(p, cx) * cx.invSpacing + vec3<f32>(0.5), cx);
        let layer = 0.5 + 0.5 * sin(lp.y * 6.0 + lp.x * 1.3 + 1.7 * sin(lp.z * 2.0));
        let graze = (1.0 - ndv) * (1.0 - ndv) * sqrt(1.0 - ndv);
        let schiller = vec3<f32>(1.0, 0.72, 0.26) * graze * (0.20 + 0.80 * layer) * 0.55;
        let kappa = 1.5 * (t0 + t1 + t2 + t3 - 4.0 * dEnd) / (e * e);   // tetrahedron: Σf = 4f₀ + (2/3)e²∇²f
        let wear = smoothstep(0.12, 0.5, kappa * e);
        let chip = vec3<f32>(1.0, 0.86, 0.62) * wear * (0.30 + 0.5 * mids);

        col = col + gloss + schiller + chip;
        depth = t / 50.0;
        alpha = mix(0.4, 1.0, clamp(ao, 0.0, 1.0));
    }

    let mapped = acesToneMap(col);
    let out_color = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, id.xy, out_color);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, out_color);
}
