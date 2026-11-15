// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Mycelial Nexus
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: hermite noise on the existing warp; junction bulbs; hypha-axis pulse; three-tap crevice AO (§12.2E)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// --- IMPLEMENTATION SKELETON ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn hashLattice(i: vec3<f32>) -> f32 {
    let n = i.x + i.y * 157.0 + 113.0 * i.z;
    return fract(sin(n) * 43758.5453123);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    // ── Idea 1: hermite weights this function already built ───────
    let u = f * f * (3.0 - 2.0 * f);
    let n000 = hashLattice(i);
    let n100 = hashLattice(i + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = hashLattice(i + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = hashLattice(i + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = hashLattice(i + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = hashLattice(i + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = hashLattice(i + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = hashLattice(i + vec3<f32>(1.0, 1.0, 1.0));
    let x00 = mix(n000, n100, u.x);
    let x10 = mix(n010, n110, u.x);
    let x01 = mix(n001, n101, u.x);
    let x11 = mix(n011, n111, u.x);
    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pp = p;
    for(var i=0; i<4; i++) {
        f += w * noise3D(pp);
        w *= 0.5;
        pp *= 2.0;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> f32 {
    var pos = p;

    if (u.zoom_config.w > 0.5) {
        let mouseWorld = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (u.zoom_config.z - 0.5) * -5.0, 0.0);
        let dist = length(pos - mouseWorld);
        let pull = 1.0 / (1.0 + dist * dist);
        pos = mix(pos, mouseWorld, pull * 0.2);
    }

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let thickness = 0.05 + bass * 0.05;

    pos += fbm(pos * u.zoom_params.x + u.config.x * u.zoom_params.z) * 0.5;
    let cell = fract(pos) - 0.5;

    let d1 = length(cell.xy) - thickness;
    let d2 = length(cell.yz) - thickness;
    let d3 = length(cell.xz) - thickness;

    // ── Idea 2: junction bulbs ─────────────────────────────────────
    // The three tubes already cross at the cell centre. A sphere there
    // is the node, smin'd with the same lattice.
    let node = length(cell) - thickness * 2.15;
    let d = smin(smin(smin(d1, d2, 0.1), d3, 0.1), node, 0.14);
    return d;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return n / max(length(n), 1e-4);
}

fn aoThree(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 1; i <= 3; i = i + 1) {
        let h = 0.02 + 0.08 * f32(i) / 3.0;
        occ = occ + (h - map(p + n * h)) * sca;
        sca = sca * 0.55;
    }
    return clamp(1.0 - 2.2 * occ, 0.0, 1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }
    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;

    let time = u.config.x * 0.5;
    let ro = vec3<f32>(sin(time) * 2.0, cos(time*0.5) * 2.0, time * 2.0);
    let ta = ro + vec3<f32>(sin(time*0.7), cos(time*0.3), 1.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    let rd = normalize(uv.x * cu + uv.y * cv + 1.0 * cw);

    var t = 0.0;
    var d = 0.0;
    var p = ro;
    for(var i=0; i<80; i++) {
        p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.02, 0.01, 0.05);

    if (d < 0.001) {
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        let sss = smoothstep(0.0, u.zoom_params.w, map(p + lightDir * 0.1)) * u.zoom_params.w;

        let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
        // ── Idea 3: hypha-axis pulse ───────────────────────────────
        // The tube axis is the normal's quiet component. The flash
        // travels along that tube instead of only along z.
        let nAbs = abs(n);
        let useX = nAbs.x <= nAbs.y && nAbs.x <= nAbs.z;
        let useY = nAbs.y < nAbs.x && nAbs.y <= nAbs.z;
        let axisCoord = select(select(p.z, p.y, useY), p.x, useX);
        let emit = pow(max(sin(axisCoord * 10.0 - u.config.x * 5.0), 0.0), 4.0) * treble * u.zoom_params.y;

        let baseCol = mix(vec3<f32>(0.1, 0.4, 0.8), vec3<f32>(0.1, 0.8, 0.4), fract(p.z * 0.2));
        // ── Idea 4: three-tap crevice AO (§12.2E) ──────────────────
        // Darkens the lit body in the smin joint. The emit stays bright.
        let occ = aoThree(p, n);
        col = baseCol * (diff + sss * 0.5) * occ + emit * vec3<f32>(0.2, 1.0, 0.8) * 2.0;
    }

    let fog = 1.0 - exp(-0.05 * t);
    col = mix(col, vec3<f32>(0.02, 0.01, 0.05), fog);
    let hit = d < 0.001;
    let alpha = clamp(select(0.04, 0.62, hit) * (1.0 - fog * 0.45), 0.02, 1.0);
    let mapped = aces(max(col, vec3<f32>(0.0)));
    let outColor = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, vec2<i32>(id.xy), outColor);
    textureStore(dataTextureA, vec2<i32>(id.xy), outColor);
    let depthOut = select(1.0, clamp(t / 20.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
