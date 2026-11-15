// ═══════════════════════════════════════════════════════════════════
//  Aetheric Tachyon Lattice
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: fold-count material (§12.2E); junction nodes
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rot2D(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// x = tube distance, y = fold count, z = junction
fn mapEx(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    let foldCount = u.zoom_params.x;
    let thickness = u.zoom_params.z;

    var folds = 0.0;
    let iters = i32(foldCount);
    for (var i = 0; i < 6; i++) {
        if (i >= iters) { break; }
        // ── Idea 1: fold-count material (§12.2E) ─────────────────────
        // Each reflection already taken. Count the signs abs() consumes.
        let reflected = step(p, vec3<f32>(0.0));
        folds += reflected.x + reflected.y + reflected.z;
        p = abs(p) - 1.0;
        let rxy = p.xy * rot2D(0.5); p = vec3<f32>(rxy, p.z);
        let rxz = p.xz * rot2D(0.3); p = vec3<f32>(rxz.x, p.y, rxz.y);
    }

    let d1 = length(p.xy) - thickness;
    let d2 = length(p.xz) - thickness;
    let d3 = length(p.yz) - thickness;
    let dmin = min(d1, min(d2, d3));
    let dmax = max(d1, max(d2, d3));
    let dmid = d1 + d2 + d3 - dmin - dmax;
    // ── Idea 2: junction nodes ───────────────────────────────────────
    // The two nearest tubes are both close: a vertex of the lattice.
    let junction = exp(-max(dmid, 0.0) * 14.0) * exp(-max(dmin, 0.0) * 6.0);
    return vec3<f32>(dmin, folds, junction);
}

fn map(p: vec3<f32>) -> f32 {
    return mapEx(p).x;
}

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let g = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return g / max(length(g), 0.0001);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;
    let time = u.config.x;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    var ro = vec3<f32>(0.0, 0.0, -3.0 + time * 0.2);
    var rd = normalize(vec3<f32>(uv, 1.0));

    if (u.zoom_config.w > 0.5) {
        let mouse_uv = (u.zoom_config.yz - 0.5) * vec2<f32>(res.x / max(res.y, 1.0), 1.0);
        let dist = length(uv - mouse_uv);
        let warp = 0.5 / (dist * dist + 0.1);
        let rxy = rd.xy * rot2D(warp * 0.1);
        rd = vec3<f32>(rxy, rd.z);
    }

    var t = 0.0;
    var steps: i32 = 0;
    var p = ro;

    for (var i = 0; i < 100; i++) {
        steps = i;
        p = ro + rd * t;
        let d = map(p);
        if (d < 0.001 || t > 20.0) { break; }
        t += d * 0.7;
    }

    var col = vec3<f32>(0.0);
    var coverage = 0.04;
    var out_depth = 1.0;

    if (t < 20.0) {
        let info = mapEx(p);
        let n = get_normal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        var diff = max(dot(n, l), 0.0);
        let ao = 1.0 - f32(steps) / 100.0;

        var baseColor = vec3<f32>(0.1, 0.15, 0.2);

        let speed = u.zoom_params.y;
        let tachyonVal = sin(p.x * 10.0 + time * speed) * sin(p.y * 10.0 + time * speed) * sin(p.z * 10.0 + time * speed);
        let emissionMult = 1.0 + bass * 2.0;

        var emitColor = vec3<f32>(0.0, 1.0, 1.0);
        if (tachyonVal > 0.5) {
            emitColor = vec3<f32>(1.0, 0.0, 1.0);
        } else if (tachyonVal < -0.5) {
            emitColor = vec3<f32>(0.2, 0.5, 1.0);
        }

        let foldAmt = clamp(info.y / 12.0, 0.0, 1.0);
        emitColor = mix(emitColor, vec3<f32>(1.0, 0.45, 0.12), foldAmt * 0.65);
        diff *= mix(1.0, 0.5, foldAmt);

        emitColor = mix(emitColor, vec3<f32>(1.0, 0.8, 0.2), bass * 0.5);
        let emit = emitColor * abs(tachyonVal) * emissionMult;

        col = (baseColor * diff + emit) * ao;
        col += vec3<f32>(0.85, 0.95, 1.0) * info.z * (0.5 + bass * 0.4);
        out_depth = clamp(t / 20.0, 0.0, 1.0);
        coverage = clamp(0.35 + length(emit) * 0.22 + info.z * 0.4, 0.0, 1.0);
    }

    col = aces(max(col, vec3<f32>(0.0)));
    let outCol = vec4<f32>(col, coverage);

    textureStore(writeTexture, id.xy, outCol);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, outCol);
    textureStore(dataTextureB, id.xy, vec4<f32>(0.0));
}
