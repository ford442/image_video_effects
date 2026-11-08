// ═══════════════════════════════════════════════════════════════════
//  Kryonic Quantum-Aether Fractal-Core
//  Category: generative
//  Features: generative, mouse-driven, audio-reactive, raymarched, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13, 2026-11-08
//  Ideas: frost-rime orbit trap; aether shatter veins along fold mirror planes; fold-count ice grade (§12.2E fold count); ridge translucency (§12.2E SDF curvature); meltwater sheen from the smin blend weight
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

fn fold(p: vec3<f32>) -> vec3<f32> {
    var p_mut = p;
    p_mut = abs(p_mut);
    if (p_mut.x < p_mut.y) { p_mut = p_mut.yxz; }
    if (p_mut.x < p_mut.z) { p_mut = p_mut.zyx; }
    if (p_mut.y < p_mut.z) { p_mut = p_mut.xzy; }
    return p_mut;
}

// ── Idea 3 helper (§12.2E fold count as material): fold() with a reflection counter — mirror
// flips (abs) plus the three axis-sorting swaps. Identical geometry to fold().
fn foldCounted(p: vec3<f32>) -> vec4<f32> {
    var q = abs(p);
    var c = f32(p.x < 0.0) + f32(p.y < 0.0) + f32(p.z < 0.0);
    if (q.x < q.y) { q = q.yxz; c += 1.0; }
    if (q.x < q.z) { q = q.zyx; c += 1.0; }
    if (q.y < q.z) { q = q.xzy; c += 1.0; }
    return vec4<f32>(q, c);
}

fn rot2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash31(p: f32) -> vec3<f32> {
    var p3 = fract(vec3<f32>(p) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + vec3<f32>(33.33));
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn map(p: vec3<f32>, time: f32, scale: f32, melt: f32, audio: f32, shatter: f32) -> f32 {
    var q = p;
    let t = time * 0.2;

    let qxy = rot2D(t) * vec2<f32>(q.x, q.y);
    q.x = qxy.x; q.y = qxy.y;
    let qyz = rot2D(t * 0.7) * vec2<f32>(q.y, q.z);
    q.y = qyz.x; q.z = qyz.y;

    var scale_factor = 1.0;
    // ── Rescue R1: the app feeds 0.5 (JSON has no top-level params), and s = 0.5 is a CONTRACTION —
    // scale_factor = 0.5^5 inflates the DE 32x and the march steps through the fractal, leaving a
    // smooth disc. Expansion factor = 1 + slider, so the fed 0.5 is the authored 1.5 fractal.
    let s = (1.0 + scale) * (1.0 + audio * 0.1);

    for (var i = 0; i < 5; i++) {
        q = fold(q);
        q = q * s - vec3<f32>(1.2, 1.2, 1.2);
        scale_factor *= s;

        let rot = rot2D(t + f32(i) * 0.5);
        let qxz = rot * vec2<f32>(q.x, q.z);
        q.x = qxz.x; q.z = qxz.y;
    }

    var d = length(q) / scale_factor - 0.02;

    let noise_offset = length(sin(p * 10.0 + vec3<f32>(time))) * 0.05 * shatter * audio;
    d += noise_offset;

    let melt_sphere = length(p) - (1.0 + melt);
    d = select(d, smin(d, melt_sphere, max(melt * 2.0, 0.0001)), melt > 0.0);

    return d;
}

// Ideas 1–3: replay map()'s fold loop once at the hit and keep its orbit data.
// x = min orbit radius (rime trap), y = min distance to the sorted-abs mirror planes (shatter seams),
// z = total mirror flips + axis swaps along the orbit (Idea 3: ice grade).
fn foldTraps(p: vec3<f32>, time: f32, scale: f32, audio: f32) -> vec3<f32> {
    var q = p;
    let t = time * 0.2;
    let qxy = rot2D(t) * vec2<f32>(q.x, q.y);
    q.x = qxy.x; q.y = qxy.y;
    let qyz = rot2D(t * 0.7) * vec2<f32>(q.y, q.z);
    q.y = qyz.x; q.z = qyz.y;

    // ── Rescue R1: the app feeds 0.5 (JSON has no top-level params), and s = 0.5 is a CONTRACTION —
    // scale_factor = 0.5^5 inflates the DE 32x and the march steps through the fractal, leaving a
    // smooth disc. Expansion factor = 1 + slider, so the fed 0.5 is the authored 1.5 fractal.
    let s = (1.0 + scale) * (1.0 + audio * 0.1);
    var sf = 1.0;
    var orbit = 1e5;
    var seam = 1e5;
    var folds = 0.0;
    for (var i = 0; i < 5; i++) {
        let a = abs(q);
        let plane = min(min(abs(a.x - a.y), abs(a.x - a.z)), abs(a.y - a.z)) * 0.7071;
        seam = min(seam, plane / sf);
        let fc = foldCounted(q);
        q = fc.xyz;
        folds += fc.w;
        q = q * s - vec3<f32>(1.2, 1.2, 1.2);
        sf *= s;
        orbit = min(orbit, length(q) / sf);
        let rot = rot2D(t + f32(i) * 0.5);
        let qxz = rot * vec2<f32>(q.x, q.z);
        q.x = qxz.x; q.z = qxz.y;
    }
    return vec3<f32>(orbit, seam, folds);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn calcNormal(p: vec3<f32>, time: f32, scale: f32, melt: f32, audio: f32, shatter: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, scale, melt, audio, shatter) - map(p - e.xyy, time, scale, melt, audio, shatter),
        map(p + e.yxy, time, scale, melt, audio, shatter) - map(p - e.yxy, time, scale, melt, audio, shatter),
        map(p + e.yyx, time, scale, melt, audio, shatter) - map(p - e.yyx, time, scale, melt, audio, shatter)
    );
    return normalize(n);
}

// ── Idea 4 helper (§12.2E SDF curvature): κ ≈ (Σ d(p±e·axis) − 6d)/e², probed at the hit only.
// κ > 0 is a convex ridge/tip, κ < 0 a crease.
fn mapCurv(p: vec3<f32>, time: f32, scale: f32, melt: f32, audio: f32, shatter: f32) -> f32 {
    let e = 0.01;
    let d0 = map(p, time, scale, melt, audio, shatter);
    let sum = map(p + vec3<f32>(e, 0.0, 0.0), time, scale, melt, audio, shatter) + map(p - vec3<f32>(e, 0.0, 0.0), time, scale, melt, audio, shatter)
            + map(p + vec3<f32>(0.0, e, 0.0), time, scale, melt, audio, shatter) + map(p - vec3<f32>(0.0, e, 0.0), time, scale, melt, audio, shatter)
            + map(p + vec3<f32>(0.0, 0.0, e), time, scale, melt, audio, shatter) + map(p - vec3<f32>(0.0, 0.0, e), time, scale, melt, audio, shatter);
    return (sum - 6.0 * d0) / (e * e);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(i32(id.x), i32(id.y));
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }

    let time = u.config.x;
    let audio = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * res;

    let scale_param = u.zoom_params.x; // default 1.5
    let shatter_param = u.zoom_params.y; // default 0.5
    let glow_param = u.zoom_params.z; // default 1.0
    let melt_param = u.zoom_params.w; // default 0.2

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    let m_uv = (mouse - 0.5 * res) / res.y;

    var ro = vec3<f32>(0.0, 0.0, -3.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    var rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Mouse tracking rot
    let mouse_rot_x = rot2D(m_uv.x * PI);
    let rd_xz = mouse_rot_x * vec2<f32>(rd.x, rd.z);
    rd.x = rd_xz.x; rd.z = rd_xz.y;

    let ro_xz = mouse_rot_x * vec2<f32>(ro.x, ro.z);
    ro.x = ro_xz.x; ro.z = ro_xz.y;

    let mouse_dist = length(uv - m_uv);
    let active_melt = melt_param * smoothstep(0.5, 0.0, mouse_dist);

    var t = 0.0;
    var d = 0.0;
    var p = ro;
    var glow = vec3<f32>(0.0);

    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        d = map(p, time, scale_param, active_melt, audio, shatter_param);

        if (d < 0.001 || t > 10.0) { break; }

        t += d * 0.5; // step small for volumetric effect

        // Volumetric aether-fog and shattering glow
        let glow_col = vec3<f32>(0.1, 0.4, 0.9) + vec3<f32>(0.8, 0.2, 0.9) * audio;
        glow += glow_col * 0.02 / (1.0 + d * d * 50.0) * glow_param;
    }

    var col = vec3<f32>(0.0);

    if (t < 10.0) {
        let n = calcNormal(p, time, scale_param, active_melt, audio, shatter_param);

        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let dif = max(dot(n, l), 0.0);
        let reflectionDir = reflect(rd, n);
        let spec = pow(max(dot(reflectionDir, l), 0.0), 32.0);

        let base_col = vec3<f32>(0.05, 0.1, 0.2);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);

        col = base_col * dif + spec * vec3<f32>(0.8, 0.9, 1.0) + fresnel * vec3<f32>(0.2, 0.8, 1.0);

        // Chromatic edges
        // ── Rescue R2: HEAD used (1 - n.z) as the rim term, but the camera looks down +z, so
        // camera-FACING surfaces (n.z ≈ -1) got the maximum (x2) and the whole fractal washed
        // cyan (meanL 0.75, stdL 0.07). Rim = grazing angle to the actual view ray.
        col += vec3<f32>(0.1, 0.5, 0.9) * (1.0 - max(dot(n, -rd), 0.0));

        let traps = foldTraps(p, time, scale_param, audio);

        // Idea 1: frost-rime orbit trap — tight fold tips crust white, recesses sink to glacial blue
        let rime = 1.0 - smoothstep(0.0, 0.06, traps.x);
        let frost = mix(vec3<f32>(0.02, 0.12, 0.35), vec3<f32>(0.85, 0.95, 1.0), rime);
        col = mix(col, col * 0.4 + frost * (0.35 + dif * 0.9), 0.55) + vec3<f32>(0.9, 0.97, 1.0) * rime * spec * 1.5;

        // Idea 2: aether shatter veins — plasma cracks along the fold mirror seams, thawed inside the melt
        let veinWidth = 0.004 + 0.012 * shatter_param * (1.0 + treble * 0.6);
        let vein = (1.0 - smoothstep(0.0, veinWidth, traps.y)) * (1.0 - smoothstep(0.0, 0.6, active_melt));
        let veinCol = mix(vec3<f32>(0.2, 0.9, 1.0), vec3<f32>(0.95, 0.25, 1.0), clamp(mids + 0.5 * sin(time * 1.3 + traps.x * 60.0) + 0.5, 0.0, 1.0));
        col += veinCol * vein * shatter_param * (1.2 + audio * 1.5);

        // ── Idea 3: fold-count ice grade. Frozen water's grade follows how often it was
        // fractured: points mirrored few times are clear glacial ice (deep blue, tight
        // glint), points mirrored many times are opaque snow-ice (matte white, broad).
        let grade = smoothstep(17.5, 23.0, traps.z);   // measured: p10 18.8, median 21.8, p98 23.6
        let clearIce = 1.0 - grade;
        col = mix(col, col * 0.45 + vec3<f32>(0.01, 0.08, 0.30) * (0.5 + dif), clearIce * 0.8);
        col += vec3<f32>(0.8, 0.92, 1.0) * pow(max(dot(reflectionDir, l), 0.0), 96.0) * clearIce * 2.5;
        col = mix(col, col * 0.7 + vec3<f32>(0.55, 0.64, 0.76) * (0.25 + 0.75 * dif), grade * 0.35);

        // ── Idea 4: ridge translucency. Thin convex ridges let the aether core light through;
        // thick flanks stay opaque. Outward-facing ridges are back-lit by the core at the origin.
        let kap = mapCurv(p, time, scale_param, active_melt, audio, shatter_param);
        let ridge = smoothstep(40.0, 160.0, kap);
        let backlit = clamp(dot(n, normalize(p + vec3<f32>(1e-4))), 0.0, 1.0);
        col += vec3<f32>(0.55, 1.0, 1.0) * ridge * (0.4 + 0.6 * backlit) * (0.5 + glow_param) * (1.0 + 0.5 * audio);

        // ── Idea 5: meltwater sheen. smin's blend weight h (how deep into the melt blend this
        // point is) becomes a wet mask: water darkens the ice and carries a tight highlight.
        let meltK = max(active_melt * 2.0, 0.0001);
        let dPure = map(p, time, scale_param, 0.0, audio, shatter_param);
        let meltSphere = length(p) - (1.0 + active_melt);
        let hBlend = max(meltK - abs(dPure - meltSphere), 0.0) / meltK;
        let wet = select(0.0, hBlend * hBlend, active_melt > 0.0);
        col = mix(col, col * 0.5 + vec3<f32>(0.01, 0.05, 0.16), wet * 0.7);
        col += vec3<f32>(0.9, 0.97, 1.0) * pow(max(dot(reflectionDir, l), 0.0), 128.0) * wet * 2.0;
    }

    col += glow;

    // deep cyan, glacial blue, void black
    col = mix(col, vec3<f32>(0.0, 0.05, 0.1), smoothstep(0.0, 10.0, t));
    col += vec3<f32>(0.05, 0.0, 0.1) * treble * 0.3;

    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let semantic_alpha = clamp(luma * 1.6 + length(glow) * 0.3, 0.05, 0.98);
    let outDepth = clamp(t / 10.0, 0.0, 1.0);
    let display = acesToneMap(col * 1.2);

    textureStore(writeTexture, coords, vec4<f32>(display, semantic_alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(display, semantic_alpha));
}
