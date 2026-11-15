// ═══════════════════════════════════════════════════════════════════
//  Neon Geode Crystallization
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: stepped bismuth hopper terraces & octahedral cleavage-seam orbit trap (§12.2E); bismuth-oxide Bi2O3 thin-film interference (§12.2F)
//  A packing: ACES display RGBA (read back from exact C for geode plasma shimmer)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Physical Bi2O3 oxide thin-film interference (§12.2F), refractive index n ≈ 2.5
fn bismuthThinFilm(cosT: f32, thicknessNm: f32) -> vec3<f32> {
    let lam = vec3<f32>(650.0, 550.0, 450.0);
    let delta = (4.0 * 3.14159265 * 2.5 * thicknessNm * max(cosT, 0.05)) / lam;
    let c = cos(delta * 0.5);
    return c * c;
}

// Returns (signed distance, octahedral cleavage-seam orbit trap, hopper terrace step)
fn mapCrystal(p_in: vec3<f32>, mids: f32) -> vec3<f32> {
    var p = p_in;

    // Twist based on zoom_params.w
    let twist = u.zoom_params.w;
    let a = twist * p.y;
    let r = rot2D(a);
    let qxy = p.xz * r;
    p = vec3<f32>(qxy.x, p.y, qxy.y);

    // Fold based on zoom_params.y + mid-band audio modulation
    let fold = u.zoom_params.y + mids * 0.25;
    p = abs(p) - vec3<f32>(fold);

    // Branchless octahedral sorting + cleavage-plane orbit trap (§12.2E)
    let swapXY = p.x < p.y;
    p = vec3<f32>(select(p.x, p.y, swapXY), select(p.y, p.x, swapXY), p.z);
    let swapXZ = p.x < p.z;
    p = vec3<f32>(select(p.x, p.z, swapXZ), p.y, select(p.z, p.x, swapXZ));
    let swapYZ = p.y < p.z;
    p = vec3<f32>(p.x, select(p.y, p.z, swapYZ), select(p.z, p.y, swapYZ));
    let seamTrap = min(abs(p.x - p.y), abs(p.y - p.z));

    // Domain repetition
    p = p - floor(p / 4.0) * 4.0 - 2.0;

    // ── Idea 1: stepped bismuth hopper crystal terraces & cleavage seams ──
    // Bismuth rims outgrow face centers, carving concentric stair-stepped hopper recesses.
    let q = abs(p);
    let baseBox = length(max(q - vec3<f32>(1.0), vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)) - 1.0, 0.0);
    let faceMax = max(q.x, max(q.y, q.z));
    let faceMin = min(q.x, min(q.y, q.z));
    let faceMid = q.x + q.y + q.z - faceMax - faceMin;
    let terraceStep = floor(clamp(faceMid, 0.0, 0.98) * 5.0) / 5.0;
    let hopperRecess = smoothstep(0.86, 0.25, faceMid) * (0.14 - 0.025 * floor(faceMid * 5.0));
    let crystalD = max(baseBox, -(baseBox + 0.22 - hopperRecess)) + terraceStep * 0.018;

    // Noise/Displacement for organic plasma veins
    let noise = sin(p.x * 5.0 + u.config.x) * sin(p.y * 5.0) * sin(p.z * 5.0) * 0.075;
    return vec3<f32>(crystalD + noise, seamTrap, terraceStep);
}

fn map(p_in: vec3<f32>, mids: f32) -> f32 {
    return mapCrystal(p_in, mids).x;
}

fn get_normal(p: vec3<f32>, mids: f32) -> vec3<f32> {
    let e = vec2<f32>(0.002, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, mids) - map(p - e.xyy, mids),
        map(p + e.yxy, mids) - map(p - e.yxy, mids),
        map(p + e.yyx, mids) - map(p - e.yyx, mids)
    ) + vec3<f32>(1e-6));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(id.x), f32(id.y));
    if (coord.x >= dims.x || coord.y >= dims.y) { return; }
    let pixel = vec2<i32>(id.xy);

    let uv = (coord - 0.5 * dims) / max(min(dims.x, dims.y), 1.0);
    let time = u.config.x;

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.5);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.5);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.5);

    var ro = vec3<f32>(0.0, 0.0, -5.0 + time * 0.5);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let mouseSteer = (u.zoom_config.yz - vec2<f32>(0.5)) * (0.12 + held * 0.55);
    var rd = normalize(vec3<f32>(uv.x + mouseSteer.x, uv.y - mouseSteer.y, 1.0));

    var clickSurge = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    let aspect = dims.x / max(dims.y, 1.0);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ev = u.ripples[ri];
        let age = time - ev.z;
        let liveMask = f32(age >= 0.0 && age < 2.6);
        let safeAge = max(age, 0.0);
        let evUV = (ev.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
        clickSurge += liveMask * exp(-abs(length(uv - evUV) - safeAge * 0.34) * 34.0) * exp(-safeAge * 1.25);
    }

    var dO = 0.0;
    var steps: i32 = 0;
    var hit = false;
    var minSeam = 10.0;
    var cavGlow = 0.0;

    for (var i = 0; i < 100; i = i + 1) {
        steps = i;
        let p = ro + rd * dO;
        let resM = mapCrystal(p, mids);
        let dS = resM.x;
        minSeam = min(minSeam, resM.y);
        cavGlow += 0.008 / (0.025 + dS * dS);
        if (dS < 0.0012) { hit = true; break; }
        if (dO > 100.0) { break; }
        dO += dS * 0.85;
    }

    let intensity = u.zoom_params.x + bass * 0.55;
    let bloomParam = max(u.zoom_params.z, 0.1);
    let stepBloom = (f32(steps) / 100.0) * bloomParam * (0.38 + treble * 0.85);
    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * dO;
        let info = mapCrystal(p, mids);
        let seamTrap = info.y;
        let terraceStep = info.z;
        let out_n = get_normal(p, mids);

        let lightDir = normalize(vec3<f32>(0.85, 0.95, -0.75));
        let viewDir = -rd;
        let cosView = max(dot(viewDir, out_n), 0.05);
        let diff = max(dot(out_n, lightDir), 0.0);
        let halfVec = normalize(lightDir + viewDir);
        let spec = pow(max(dot(out_n, halfVec), 0.0), 44.0);

        // ── Idea 2: bismuth-oxide Bi2O3 thin-film interference (§12.2F) ─────
        let oxideNm = 185.0 + terraceStep * 170.0 + seamTrap * 48.0 + mids * 24.0;
        let filmCol = bismuthThinFilm(cosView, oxideNm);
        let fresnel = 0.18 + 0.82 * pow(1.0 - cosView, 4.0);
        let metallicBase = mix(vec3<f32>(0.08, 0.42, 0.95), filmCol * 1.35, 0.72);

        // Erupting neon plasma along octahedral cleavage-plane orbit trap
        let veinMask = exp(-seamTrap * 7.5);
        let pulseWave = 0.65 + 0.35 * sin(time * 3.4 - length(p.xy) * 1.8);
        let seamPlasma = mix(vec3<f32>(1.1, 0.18, 0.85), vec3<f32>(0.18, 0.95, 1.15), clamp(terraceStep, 0.0, 1.0))
                       * veinMask * pulseWave * (0.45 + intensity * 1.15 + clickSurge * 1.1);

        let distFog = exp(-0.028 * dO);
        col = (metallicBase * (0.22 + diff * 0.88) * (0.45 + intensity * 0.75)
            + filmCol * (spec * 1.35 + fresnel * 0.48) * (0.6 + bass * 0.4)
            + seamPlasma) * distFog
            + vec3<f32>(1.0, 0.22, 0.82) * stepBloom * 0.75;
    } else {
        let nearVein = exp(-minSeam * 3.5);
        col = vec3<f32>(0.008, 0.012, 0.026)
            + mix(vec3<f32>(0.18, 0.52, 1.0), vec3<f32>(1.0, 0.22, 0.82), nearVein)
            * (cavGlow * 0.018 * bloomParam + stepBloom * 0.32 + clickSurge * 0.35) * (0.5 + intensity * 0.6);
    }

    let mapped = acesToneMap(max(col, vec3<f32>(0.0)));
    let normDepth = select(1.0, clamp(dO / 100.0, 0.0, 1.0), hit);
    let hitMask = select(0.0, 1.0, hit);
    let alpha = clamp(hitMask * (0.82 + (1.0 - normDepth) * 0.16) + (1.0 - hitMask) * clamp(cavGlow * 0.02 + stepBloom * 0.35, 0.06, 0.68), 0.06, 0.98);

    let prev = textureLoad(dataTextureC, pixel, 0);
    let outCol = clamp(mix(mapped, max(mapped, prev.rgb * 0.90), 0.14), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, pixel, vec4<f32>(outCol, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(normDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(outCol, alpha));
}