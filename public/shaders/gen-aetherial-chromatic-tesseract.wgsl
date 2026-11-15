// ═══════════════════════════════════════════════════════════════════
//  Aetherial Chromatic Tesseract
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: fold-count material; thin-film iridescence; box-edge wear
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Folded point in xyz, reflection count in w. The loop is the original four folds.
fn foldPoint(p_in: vec3<f32>, time: f32, bass: f32, mids: f32) -> vec4<f32> {
    var p = p_in;
    var hits = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
        hits = hits + step(p.x, 0.0);
        p.x = abs(p.x) - 1.0;
        let p_yz = p.yz * rot(time * 0.2 + f32(i) * 0.5);
        p.y = p_yz.x;
        p.z = p_yz.y;
        let p_xz = p.xz * rot(time * 0.3 + mids * 0.5);
        p.x = p_xz.x;
        p.z = p_xz.y;
    }
    let scale = 1.0 + bass * 0.2;
    return vec4<f32>(p / scale, hits);
}

fn map(p_in: vec3<f32>, time: f32, bass: f32, mids: f32, fold_complexity: f32) -> f32 {
    let f = foldPoint(p_in, time, bass, mids);
    let scale = 1.0 + bass * 0.2;
    let b = vec3<f32>(fold_complexity);
    let q = abs(f.xyz) - b;
    let d = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
    return d * scale;
}

fn calcNormal(p: vec3<f32>, time: f32, bass: f32, mids: f32, fold_complexity: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy, time, bass, mids, fold_complexity) +
        e.yyx * map(p + e.yyx, time, bass, mids, fold_complexity) +
        e.yxy * map(p + e.yxy, time, bass, mids, fold_complexity) +
        e.xxx * map(p + e.xxx, time, bass, mids, fold_complexity)
    );
}

// ── Idea 2: thin-film. Iridescence Shift is the film thickness.
fn thinFilm(cosT: f32, shift: f32, time: f32) -> vec3<f32> {
    let lam = vec3<f32>(650.0, 550.0, 450.0);
    let thick = 90.0 + shift * 380.0 * (0.82 + 0.18 * sin(time * 0.35));
    let delta = (12.5663706 * 1.38 * thick * max(cosT, 0.05)) / lam;
    let c = cos(delta * 0.5);
    return c * c;
}

fn boxEdge(q: vec3<f32>) -> f32 {
    let ax = smoothstep(0.14, 0.0, abs(q.x));
    let ay = smoothstep(0.14, 0.0, abs(q.y));
    let az = smoothstep(0.14, 0.0, abs(q.z));
    return clamp(ax * ay + ay * az + az * ax, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }
    let coord = vec2<i32>(id.xy);

    var uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;
    let fold_complexity = u.zoom_params.x;
    let iridescence_shift = u.zoom_params.y;
    let gravity_strength = u.zoom_params.z;
    let glow_intensity = u.zoom_params.w;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);

    // Pointer in the same centered frame as uv. The old divide-by-resolution
    // put the well off the ray, so Gravity Strength never moved the picture.
    let aspect = resolution.x / max(resolution.y, 1.0);
    let mouse01 = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseUV = (mouse01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let delta = uv - mouseUV;
    let mDist = length(delta);
    uv = uv + delta / max(mDist, 0.0001) * exp(-mDist * 5.0) * 0.1 * gravity_strength * held;

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var dO = 0.0;
    var p = ro;
    var d = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 100; i = i + 1) {
        p = ro + rd * dO;
        d = map(p, time, bass, mids, fold_complexity);
        glow += (0.01 * glow_intensity * (1.0 + bass)) / (0.01 + abs(d));
        if (d < 0.001 || dO > 20.0) {
            break;
        }
        dO += d;
    }

    var col = vec3<f32>(0.0);
    var ndotv = 0.0;
    var edge = 0.0;
    let hit = dO < 20.0;
    if (hit) {
        let n = calcNormal(p, time, bass, mids, fold_complexity);
        let v = -rd;
        ndotv = max(dot(n, v), 0.0);
        let film = thinFilm(ndotv, iridescence_shift, time);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let h = normalize(lightDir + v);

        // ── Idea 1: fold-count material (§12.2E) ────────────────────
        let folded = foldPoint(p, time, bass, mids);
        let foldAmt = folded.w / 4.0;
        let specPow = mix(32.0, 12.0, foldAmt);
        let spec = pow(max(dot(n, h), 0.0), specPow);

        // Distance shade (the old dO term). Not crevice AO.
        let shade = clamp(dO / 10.0, 0.0, 1.0);
        col = (film * diff * 0.8 + vec3<f32>(spec) * 0.2) * (1.0 - shade * 0.5);
        col = mix(col, col * vec3<f32>(0.72, 0.84, 1.05), foldAmt * 0.55);

        // ── Idea 3: box-edge wear ───────────────────────────────────
        // Two axes of the box q near zero is an edge of this SDF.
        let q = abs(folded.xyz) - vec3<f32>(fold_complexity);
        edge = boxEdge(q);
        col += vec3<f32>(1.0, 0.94, 0.86) * edge * 0.42;
    }

    col += vec3<f32>(0.2, 0.4, 0.8) * glow * 0.1;

    let mapped = aces(max(col, vec3<f32>(0.0)));
    let alpha = select(
        clamp(0.04 + glow * 0.015, 0.0, 0.45),
        clamp(0.22 + ndotv * 0.4 + edge * 0.22 + clamp(glow, 0.0, 4.0) * 0.03, 0.0, 1.0),
        hit
    );
    let outCol = vec4<f32>(mapped, alpha);
    let depth = select(1.0, clamp(dO / 20.0, 0.0, 1.0), hit);
    textureStore(writeTexture, coord, outCol);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outCol);
}
