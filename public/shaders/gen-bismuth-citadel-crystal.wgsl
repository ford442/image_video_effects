// ═══════════════════════════════════════════════════════════════════
//  Bismuth Citadel Crystal
//  Category: advanced-hybrid
//  Features: raymarching, crystal-growth, phase-field, iridescence, temporal
//  Complexity: Very High
//  Chunks From: gen-bismuth-crystal-citadel.wgsl, alpha-crystal-growth-phase.wgsl
//  Created: 2026-04-18
//  By: Agent CB-20 — Generative Nature Enhancer
//  Upgraded: 2026-11-01
//  Ideas: terrace-indexed thin-film oxide (§12.2F); SDF curvature edge wear (§12.2E); kaleidoscope wedge index as oxide zoning (§12.2E)
//  A packing: ACES display RGBA (alpha = metal coverage / fresnel)
// ═══════════════════════════════════════════════════════════════════
//  Endless bismuth crystal canyon where terrace surfaces exhibit
//  dendritic crystal growth patterns from phase-field simulation.
//  Crystal orientation determines surface color via anisotropic
//  thin-film interference.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const IOR_BISMUTH: f32 = 1.8;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ── Idea 1: thin-film oxide interference (§12.2F). Per-channel R(λ) ∝ cos²(δ/2),
// δ = 4π·n·d·cosθ / λ. Replaces the cosine palette: bismuth's colour IS an oxide film.
fn thinFilm(cosT: f32, thicknessNm: f32, n: f32) -> vec3<f32> {
    let lam = vec3<f32>(650.0, 550.0, 450.0);
    let delta = (4.0 * 3.14159265 * n * thicknessNm * max(cosT, 0.05)) / lam;
    let c = cos(delta * 0.5);
    return c * c;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: crystalPhaseField (from alpha-crystal-growth-phase.wgsl) ═══
fn crystalPhaseField(p: vec2<f32>, time: f32, supercooling: f32, anisotropy: f32) -> vec4<f32> {
    // Procedural phase field approximation
    let centerDist = length(p);
    let phase = smoothstep(0.5 + supercooling * 0.3, 0.0, centerDist)
              + 0.3 * smoothstep(0.2, 0.0, abs(p.x - p.y * 0.5))
              + 0.3 * smoothstep(0.2, 0.0, abs(p.x + p.y * 0.5));
    let orientation = atan2(p.y, p.x);
    let impurity = hash31(vec3<f32>(p.x * 10.0, p.y * 10.0, 0.0)) * 0.3;
    let temp = -0.2 + impurity * 0.5;
    return vec4<f32>(clamp(phase, 0.0, 1.0), temp, orientation, impurity);
}

struct Fold {
    p: vec3<f32>,
    wedge: f32,
}

// Kaleidoscope fold shared by map() and the shading pass (so wedge index is available as a material).
fn foldSpace(p_in: vec3<f32>) -> Fold {
    var p = p_in;
    let twist = p.y * 0.05;
    let p_xz = rot(twist) * p.xz;
    p.x = p_xz.x;
    p.z = p_xz.y;
    let spacingY = 4.0;
    p.y = fract(p.y / spacingY + 0.5) * spacingY - spacingY * 0.5;
    let angle = atan2(p.z, p.x);
    let radius = length(p.xz);
    let segments = 6.0;
    let segmentAngle = 6.28318 / segments;
    let a = angle + 3.14159;
    let a_mod = fract(a / segmentAngle) * segmentAngle - segmentAngle * 0.5;
    p.x = radius * cos(a_mod);
    p.z = radius * sin(a_mod);
    return Fold(p, floor(a / segmentAngle));
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    let fo = foldSpace(p_in);
    let p = fo.p;
    let stepSize = u.zoom_params.x * 0.5 + 0.1;
    var pStep = p;
    pStep.x = floor(pStep.x / stepSize) * stepSize + stepSize * 0.5;
    pStep.z = floor(pStep.z / stepSize) * stepSize + stepSize * 0.5;
    pStep.y = floor(pStep.y / stepSize) * stepSize + stepSize * 0.5;
    let basePos = vec3<f32>(2.0, 0.0, 0.0);
    let d1 = sdBox(p - basePos, vec3<f32>(1.0, 1.5, 1.0));
    let innerSize = vec3<f32>(0.8, 1.6, 0.8);
    let inner_hollow = sdBox(p - basePos, innerSize);
    let terraceSize = stepSize * 0.45;
    // Rescue: HEAD tiled the terrace cubes through ALL of space (90 % fill), so every
    // ray hit the grid at t≈0 and the frame was a flat wash. Keep them as a stepped
    // skirt hugging the tower wall instead.
    let d2 = max(sdBox(p - pStep, vec3<f32>(terraceSize)), abs(d1) - stepSize * 1.5);
    var d = max(d1, -inner_hollow);
    d = smin(d, d2 - 0.05, 0.1);
    let crystalPos = vec3<f32>(1.5 + sin(u.config.x * 0.5 + p.y) * 0.2, 0.0, 0.0);
    let d3 = sdBox(p - crystalPos, vec3<f32>(0.3, 0.8, 0.3));
    d = smin(d, d3, 0.2);
    return vec2<f32>(d, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

fn fresnelMetal(cosTheta: f32, F0: vec3<f32>) -> vec3<f32> {
    return F0 + (vec3<f32>(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }
    var uv = (fragCoord * 2.0 - dims) / dims.y;
    let stepSize = u.zoom_params.x * 0.5 + 0.1;
    let speed = u.zoom_params.y;
    let metallic = u.zoom_params.z;
    let iridescence = u.zoom_params.w;
    let oxidePurity = 0.7 + u.zoom_params.x * 0.3;
    let supercooling = mix(0.1, 0.8, u.zoom_params.x);
    let anisotropy = mix(0.0, 0.5, u.zoom_params.y);
    var time = u.config.x * speed;
    var ro = vec3<f32>(0.0, time * 2.0, -5.0);
    // zoom_config.yz is already 0..1 (HEAD divided by dims, parking the light in a corner)
    let mouse01 = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let ta = vec3<f32>(0.0, time * 2.0 + 2.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);
    var t = 0.0;
    var d = 0.0;
    var m = -1.0;
    var steps = 0.0;
    let maxSteps = 100;
    let maxDist = 50.0;
    for (var i = 0; i < maxSteps; i++) {
        var p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        steps += 1.0;
        if (d < 0.001 || t > maxDist) { break; }
        t += d * 0.8;
    }
    var col = vec3<f32>(0.02, 0.02, 0.03);
    col += vec3<f32>(0.05, 0.08, 0.12) * max(0.0, rd.y);
    var alpha = 1.0;
    if (t < maxDist) {
        var p = ro + rd * t;
        let n = calcNormal(p);
        let v = normalize(ro - p);
        let mouseLightPos = vec3<f32>(
            (mouse01.x - 0.5) * 10.0,
            ro.y + 2.0,
            (mouse01.y - 0.5) * 10.0 + 3.0
        );
        let lig = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let l_mouse = normalize(mouseLightPos - p);
        let dif = max(dot(n, lig), 0.0);
        let dif_mouse = max(dot(n, l_mouse), 0.0);
        let hal = normalize(lig - rd);
        let spec = pow(max(dot(n, hal), 0.0), 32.0);
        let ndotv = max(dot(n, v), 0.0);
        let fresnel = pow(1.0 - ndotv, 5.0);

        // ═══ CHUNK: crystal phase-field growth pattern ═══
        let phaseState = crystalPhaseField(p.xz * 0.5, u.config.x, supercooling, anisotropy);
        let phase = phaseState.r;
        let orientation = phaseState.b;
        let impurity = phaseState.a;
        let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);

        // Orientation-based color (from alpha-crystal-growth-phase)
        let orientNorm = fract(orientation / 6.283185307);
        let h6 = orientNorm * 6.0;
        let c = 0.8;
        let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
        var crystalColor: vec3<f32>;
        if (h6 < 1.0) { crystalColor = vec3(c, x, 0.3); }
        else if (h6 < 2.0) { crystalColor = vec3(x, c, 0.3); }
        else if (h6 < 3.0) { crystalColor = vec3(0.3, c, x); }
        else if (h6 < 4.0) { crystalColor = vec3(0.3, x, c); }
        else if (h6 < 5.0) { crystalColor = vec3(x, 0.3, c); }
        else { crystalColor = vec3(c, 0.3, x); }

        // Fold data for the oxide zoning (re-derived at the hit point, same fold as map()).
        let fo = foldSpace(p);
        let stepCell = floor(fo.p / stepSize);
        let terraceId = hash31(stepCell + vec3<f32>(fo.wedge * 7.0, 0.0, 0.0));

        // ── Idea 3: wedge fold index as material (§12.2E). Each of the 6 kaleido wedges
        // grew its own oxide, so the tower ring is not one tower repeated six times.
        let wedgeZone = fract(fo.wedge * 0.381966) * 90.0;

        // ── Idea 1: terrace-indexed thin-film oxide (§12.2F). Every terrace tread is a
        // different film thickness; the iridescence slider scales the spread of the film.
        let interferenceOffset = p.y * 0.1 + p.x * 0.05 + u.config.x * 0.1;
        let filmSpread = mix(0.35, 1.0, iridescence);
        // film also thins toward each tread's lip (hopper growth gradient)
        let treadLip = length(fract(fo.p / stepSize) - vec3<f32>(0.5));
        let filmNm = 190.0 + terraceId * 330.0 * filmSpread + wedgeZone + 110.0 * treadLip + 28.0 * sin(interferenceOffset * 6.28318 + fresnel * iridescence * 3.0);
        let iridColor = thinFilm(ndotv, filmNm, 2.0);

        // ── Idea 2: SDF curvature edge wear (§12.2E). Laplacian of the existing map():
        // convex lips (>0) are polished bare bismuth, crevices (<0) keep thick dark oxide.
        let ce = 0.04;
        let lap = (map(p + vec3<f32>(ce, 0.0, 0.0)).x + map(p - vec3<f32>(ce, 0.0, 0.0)).x
                 + map(p + vec3<f32>(0.0, ce, 0.0)).x + map(p - vec3<f32>(0.0, ce, 0.0)).x
                 + map(p + vec3<f32>(0.0, 0.0, ce)).x + map(p - vec3<f32>(0.0, 0.0, ce)).x
                 - 6.0 * map(p).x) / (ce * ce);
        let wear = smoothstep(4.0, 16.0, lap);
        let crevice = smoothstep(-4.0, -16.0, lap);

        let baseColor = vec3<f32>(0.08, 0.08, 0.1);
        let F0_bismuth = vec3<f32>(0.75, 0.8, 0.85);
        let metalFresnel = fresnelMetal(ndotv, F0_bismuth * metallic);
        var litColor = baseColor * (dif * 0.7 + dif_mouse * 0.5 + 0.2);
        let oxide = iridColor * (1.0 - 0.55 * crevice);
        let silver = vec3<f32>(0.86, 0.88, 0.92) * (0.35 + 0.65 * dif);
        litColor += oxide * (0.2 + 0.8 * fresnel) * oxidePurity * 1.4;
        litColor = mix(litColor, silver, wear * (0.35 + 0.5 * metallic));
        litColor += vec3<f32>(1.0) * spec * metallic;
        // Blend crystal growth colors
        litColor = mix(litColor, crystalColor * (0.5 + 0.5 * dif), interfaceMask * 0.6);
        litColor = mix(litColor, vec3<f32>(0.8, 0.6, 0.4), impurity * 0.2);
        let terracePattern = sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0);
        litColor += vec3<f32>(0.3, 0.5, 0.6) * max(0.0, terracePattern) * fresnel * 0.5;
        col = litColor;
        // Rescue: HEAD's ao was the constant 1 - 100/100 = 0 (always ×0.5); use the real step count.
        let ao = 1.0 - clamp(steps / f32(maxSteps), 0.0, 1.0);
        col *= mix(0.5, 1.0, ao);
        col = mix(col, vec3<f32>(0.02, 0.02, 0.03), 1.0 - exp(-0.015 * t));
        alpha = mix(0.3, 1.0, metallic * 0.7 + fresnel * 0.3);
        alpha = clamp(alpha + wear * 0.15, 0.0, 1.0);
    } else {
        alpha = 0.9;
    }
    col *= 1.0 - 0.3 * length(uv);
    col = acesToneMap(max(col, vec3<f32>(0.0)));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(t / maxDist, 0.0, 0.0, 0.0));
}
