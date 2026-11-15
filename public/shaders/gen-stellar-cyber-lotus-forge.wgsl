// ═══════════════════════════════════════════════════════════════════
//  Stellar Cyber-Lotus Forge
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: multi-whorl Petal Complexity corolla & etched cyber-vein conduits; stellar core inverse-square forge lighting (§12.2F) & Fresnel–Schlick metallic petal rims (§12.2F)
//  A packing: ACES display RGBA (read back from exact C for stellar forge ember trail)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU_LOTUS: f32 = 6.28318530718;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Polar-folded petal whorl returning (sdf, etched circuit-vein mask)
fn evalPetalWhorl(p: vec3<f32>, count: f32, phaseOffset: f32, reach: f32, lift: f32, scaleW: f32, time: f32) -> vec2<f32> {
    let sector = TAU_LOTUS / max(count, 2.0);
    let ang = atan2(p.z, p.x) - phaseOffset;
    let foldedAng = (fract((ang + sector * 0.5) / sector) - 0.5) * sector;
    let rXZ = length(p.xz);
    var pp = vec3<f32>(cos(foldedAng) * rXZ - reach, p.y - lift, sin(foldedAng) * rXZ);

    // Fold/Curve the petal blade upward toward tip
    pp.y -= sin(pp.x * 2.0 + time) * 0.3 + max(pp.x, 0.0) * lift * 0.45;
    let taper = clamp(pp.x + 0.65, -0.4, 1.4);
    let blade = length(vec3<f32>(pp.x * 0.88, max(0.0, abs(pp.y) - 0.045), pp.z / max(scaleW * (1.15 - taper * 0.32), 0.2)))
              - 0.46 + (pp.x + reach) * 0.16;

    // Branching cyber-circuit venation grooves etched into each petal
    let midrib = exp(-abs(pp.z) * 26.0);
    let lateralVeins = exp(-abs(sin(pp.z * 18.0 - abs(pp.x + 0.25) * 7.5)) * 7.0) * smoothstep(0.45, 0.02, abs(pp.z));
    let vein = clamp(midrib * 0.85 + lateralVeins * 0.75, 0.0, 1.2);
    return vec2<f32>(blade - vein * 0.012, vein);
}

// Returns (signed distance, circuit vein mask, core proximity mask)
fn mapLotus(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;

    // Guarded, branchless mouse gravity pull when held
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    let pull = (1.0 - smoothstep(0.0, 3.0, dist_to_mouse)) * held;
    p = mix(p, mouse_pos, pull * 0.5);

    let rotTime = u.config.x * u.zoom_params.y;
    let xz = rot(rotTime * 0.2) * vec2<f32>(p.x, p.z);
    p.x = xz.x;
    p.z = xz.y;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.5);
    // Central stellar forge core sphere
    let core = length(p) - (0.94 + bass * 0.08);

    // ── Idea 1: live multi-whorl Petal Complexity corolla & cyber-veins ──
    // Wires Petal Complexity (u.zoom_params.z, 1..6; default 3 -> 6 outer petals,
    // matching HEAD) to drive outer + interleaved inner uplifted lotus whorls.
    let complexity = clamp(u.zoom_params.z, 1.0, 6.0);
    let outerCount = max(round(complexity) * 2.0, 2.0);
    let outerWhorl = evalPetalWhorl(p, outerCount, 0.0, 1.2, 0.0, 1.0, rotTime);

    let innerActive = smoothstep(1.2, 2.5, complexity);
    let innerOpen = 0.72 + complexity * 0.07;
    let innerWhorl = evalPetalWhorl(p / innerOpen, outerCount, PI / outerCount, 1.02, 0.34, 0.82, rotTime * 1.15 + 0.8);
    let innerD = mix(10.0, innerWhorl.x * innerOpen, innerActive);

    // Forge stamen crown ringing the core at higher complexity
    let stamenAng = atan2(p.z, p.x);
    let stamenRing = length(vec2<f32>(length(p.xz) - 1.02, p.y - 0.32 - 0.08 * cos(stamenAng * outerCount * 2.0))) - 0.065;
    let stamenD = mix(10.0, stamenRing, smoothstep(2.2, 4.5, complexity));

    let petalsD = smin(outerWhorl.x, smin(innerD, stamenD, 0.18), 0.32);
    let totalD = smin(core, petalsD, 0.45);

    let innerWeight = smoothstep(0.25, -0.15, innerD - outerWhorl.x) * innerActive;
    let veinMask = mix(outerWhorl.y, innerWhorl.y, innerWeight) + smoothstep(0.12, 0.0, abs(stamenD)) * 0.85;
    let coreWeight = smoothstep(0.35, -0.15, core - petalsD);

    return vec3<f32>(totalD, veinMask, coreWeight);
}

fn map(p_in: vec3<f32>) -> f32 {
    return mapLotus(p_in).x;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.0025, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ) + vec3<f32>(1e-6));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }
    let pixel = vec2<i32>(id.xy);
    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / max(resolution.y, 1.0);
    let rawTime = u.config.x;

    // Ray setup (exact framing preserved)
    let ro = vec3<f32>(0.0, 2.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var p = ro;
    var t = 0.0;
    var glow = 0.0;
    var hit = false;

    for (var i = 0; i < 68; i++) {
        p = ro + rd * t;
        let d = map(p);
        if (d < 0.006) { hit = true; break; }
        if (t > 15.0) { break; }
        glow += 0.05 / (0.1 + d * d + max(d, 0.0) * 0.5);
        t += d * 0.8;
    }

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.5);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.5);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.5);
    let bloom_intensity = u.zoom_params.x * (1.0 + bass * 2.0);
    let veinParam = max(u.zoom_params.w, 0.0);

    var clickForge = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    let aspect = resolution.x / max(resolution.y, 1.0);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ev = u.ripples[ri];
        let age = rawTime - ev.z;
        let liveMask = f32(age >= 0.0 && age < 2.6);
        let safeAge = max(age, 0.0);
        let evUV = (ev.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
        clickForge += liveMask * exp(-abs(length(uv - evUV) - safeAge * 0.30) * 38.0) * exp(-safeAge * 1.3);
    }

    var col = vec3<f32>(0.006, 0.01, 0.024);
    if (hit) {
        let hitInfo = mapLotus(p);
        let veinMask = hitInfo.y;
        let coreWeight = hitInfo.z;
        let n = getNormal(p);
        let viewDir = -rd;
        let radialDist = length(p);

        // ── Idea 2: stellar core inverse-square forge lighting (§12.2F) & Fresnel–Schlick (§12.2F) ─
        let toCore = -p * inverseSqrt(max(dot(p, p), 0.001));
        let coreFacing = max(dot(n, toCore) * 0.6 + 0.4, 0.0);
        let coreFalloff = (1.35 + bass * 0.95 + clickForge * 1.6) / (dot(p, p) + 0.55);
        let skyLight = normalize(vec3<f32>(0.45, 0.85, -0.55));
        let skyDiff = max(dot(n, skyLight), 0.0);
        let spec = pow(max(dot(n, normalize(skyLight + viewDir)), 0.0), 36.0);
        let fresnel = 0.06 + 0.94 * pow(clamp(1.0 - max(dot(viewDir, n), 0.0), 0.0, 1.0), 5.0);

        let petalAlloy = mix(vec3<f32>(0.09, 0.19, 0.48), vec3<f32>(0.78, 0.12, 0.58), clamp(radialDist * 0.32, 0.0, 1.0));
        let coreIncandescence = mix(vec3<f32>(1.25, 0.58, 0.12), vec3<f32>(1.45, 1.18, 0.65), clamp(bass * 0.5 + 0.3, 0.0, 1.0));

        // Travelling stellar plasma pulse along etched petal circuit veins
        let veinPulse = 0.62 + 0.38 * sin(radialDist * 8.0 - rawTime * (3.2 + mids * 2.0));
        let veinGlow = vec3<f32>(1.15, 0.84, 0.22) * (veinMask * veinPulse * 0.65 + glow * 0.015) * veinParam * (1.0 + bass * 0.85 + mids * 0.35);

        let petalLit = petalAlloy * (0.20 + skyDiff * 0.58)
                     + vec3<f32>(1.15, 0.62, 0.18) * coreFacing * coreFalloff * 0.55
                     + mix(vec3<f32>(0.32, 0.78, 1.15), vec3<f32>(1.05, 0.28, 0.85), clamp(radialDist * 0.35, 0.0, 1.0)) * (fresnel * 0.78 + spec * (0.55 + treble * 0.45));
        col = mix(petalLit, coreIncandescence * (0.85 + coreFalloff * 0.45), coreWeight) + veinGlow;
    }

    col += vec3<f32>(0.22, 0.52, 0.88) * glow * 0.012 * bloom_intensity;
    col += vec3<f32>(1.1, 0.72, 0.28) * clickForge * (0.28 + bloom_intensity * 0.22);

    let mapped = acesToneMap(max(col, vec3<f32>(0.0)));
    let normDepth = select(1.0, clamp(t / 15.0, 0.0, 1.0), hit);
    let hitMask = select(0.0, 1.0, hit);
    let alpha = clamp(hitMask * (0.84 + (1.0 - normDepth) * 0.14) + (1.0 - hitMask) * clamp(glow * 0.015 * (0.35 + bloom_intensity), 0.05, 0.65) + clickForge * 0.14, 0.05, 0.98);

    let prev = textureLoad(dataTextureC, pixel, 0);
    let emberTrail = clamp(mix(mapped, max(mapped, prev.rgb * 0.91), 0.15), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, pixel, vec4<f32>(emberTrail, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(normDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(emberTrail, alpha));
}
