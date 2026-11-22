// ═══════════════════════════════════════════════════════════════════
//  Aetheric Tachyon Lattice
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15, 2026-11-22
//  Ideas: fold-count material (§12.2E); junction nodes; axial tachyon packets that
//         travel along each strut (nearest-tube axis); soft inverse-square aether
//         halo integrated along the march (§12.2F)
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

// x = tube distance, y = fold count, z = junction, w = coordinate ALONG the nearest tube
fn mapEx(p_in: vec3<f32>) -> vec4<f32> {
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
    // ── Idea 3 (2026-11-22): which strut, and where along it ─────────
    // d1 = tube along z, d2 = tube along y, d3 = tube along x. The argmin the
    // lattice already computes (and discarded) names the nearest strut's axis;
    // the matching folded coordinate is the position along it.
    let on1 = d1 <= d2 && d1 <= d3;
    let on2 = !on1 && d2 <= d3;
    let axial = select(select(p.x, p.y, on2), p.z, on1);
    return vec4<f32>(dmin, folds, junction, axial);
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
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

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

    // ── Idea 4 (2026-11-22): soft inverse-square aether halo (§12.2F) ──
    // I / (d² + r0²) integrated along the ray with the tracer's own step
    // length: every strut is a glow source whose aura lights the void around
    // it. r0 is the core radius (tied to the tube thickness) so the aura has
    // no singularity on the strut skin.
    var halo = 0.0;
    let r0 = 0.04 + u.zoom_params.z * 1.0;

    for (var i = 0; i < 100; i++) {
        steps = i;
        p = ro + rd * t;
        let d = map(p);
        if (d < 0.001 || t > 20.0) { break; }
        let stepLen = d * 0.7;
        halo += stepLen / (d * d + r0 * r0);
        t += stepLen;
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

        // ── Idea 3 (2026-11-22): axial tachyon packets ───────────────
        // The checker above is an isotropic standing pattern; nothing flows
        // ALONG a strut. Beads of light now run down each tube's own axis
        // (info.w), blue-white that warms to the ember hue in deep folds.
        // A mirrored fold reverses the direction across its plane. Mids set
        // the brightness of the stream.
        let packetPhase = info.w * 7.0 - time * speed * 2.5;
        let packet = pow(0.5 + 0.5 * sin(packetPhase), 10.0);
        let packetCol = mix(vec3<f32>(0.65, 0.9, 1.0), vec3<f32>(1.0, 0.7, 0.35), foldAmt * 0.7);
        let packets = packetCol * packet * 1.4 * (0.55 + mids * 1.1);

        col = (baseColor * diff + emit + packets) * ao;
        col += vec3<f32>(0.85, 0.95, 1.0) * info.z * (0.5 + bass * 0.4 + treble * 0.5);
        out_depth = clamp(t / 20.0, 0.0, 1.0);
        coverage = clamp(0.35 + length(emit + packets) * 0.22 + info.z * 0.4, 0.0, 1.0);
    }

    // Idea 4: the aura lights hits and the void alike; treble lifts it.
    let haloAmt = halo * 0.002 * (0.7 + treble * 0.8);
    col += vec3<f32>(0.10, 0.55, 0.80) * haloAmt;
    coverage = clamp(coverage + haloAmt * 0.8, 0.0, 1.0);

    col = aces(max(col, vec3<f32>(0.0)));
    let outCol = vec4<f32>(col, coverage);

    textureStore(writeTexture, id.xy, outCol);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, outCol);
}
