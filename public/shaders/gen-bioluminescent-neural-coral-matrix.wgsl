// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Neural-Coral Matrix
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: corallite polyp micro-relief & synaptic action-potential waves; 5-tap gyroid cavern AO (§12.2E) & SDF curvature chromoprotein rims (§12.2E)
//  A packing: ACES display RGBA (read back from exact C for refractory coral afterglow)
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

// SDF for the Neural Coral
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;

    // Guarded, branchless mouse gravity well around camera-relative plane
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let camZ = u.config.x * u.zoom_params.z + 2.2;
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, camZ);
    let delta = p - mouse_pos;
    let distSq = dot(delta, delta);
    let safeDir = delta * inverseSqrt(max(distSq, 0.0001));
    let pull = held / (1.0 + distSq);
    p = p - safeDir * pull * u.zoom_params.y * 0.65;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.5);
    let pulse = sin(u.config.x * 2.0 + p.z * 0.5) * bass;

    // Primary gyroid structure
    let scale = max(u.zoom_params.x, 0.25);
    var d = (dot(sin(p * scale), cos(p.zxy * scale)) + 0.5) / scale;

    // Organic wave distortion scaled by Distortion Intensity
    let distAmt = clamp(u.zoom_params.y, 0.0, 3.0);
    d += sin(p.x * 3.0 + u.config.x) * (0.04 + 0.04 * distAmt);

    // ── Idea 1 (part a): calcareous corallite polyp micro-relief ────────
    // Fine secondary meandroid gyroid pores sculpted onto the coral walls.
    let polypScale = scale * 3.35;
    let corallite = dot(sin(p * polypScale), cos(p.yzx * polypScale)) / max(polypScale, 0.5);
    d += corallite * (0.055 + 0.025 * min(distAmt, 2.0));

    return d - (0.1 + pulse * 0.05);
}

// Raymarching with synaptic pulse glow accumulation
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, mids: f32) -> vec3<f32> {
    var t = 0.0;
    var glow = 0.0;
    var synGlow = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001) { break; }
        if (t > 20.0) { t = -1.0; break; }
        let nearWeight = 0.01 / (0.01 + d * d);
        let wave = pow(0.5 + 0.5 * sin(p.z * 2.3 - u.config.x * (3.1 + mids * 1.6) + sin(p.x * 1.7 + p.y * 1.7)), 5.0);
        glow += nearWeight;
        synGlow += nearWeight * wave;
        t += d * 0.5;
    }
    return vec3<f32>(t, glow, synGlow);
}

// Returns (normal.xyz, SDF mean curvature) from 6 axial + 1 center evaluations (§12.2E)
fn getNormalAndCurvature(p: vec3<f32>) -> vec4<f32> {
    let eps = 0.012;
    let e = vec2<f32>(eps, 0.0);
    let xp = map(p + e.xyy); let xm = map(p - e.xyy);
    let yp = map(p + e.yxy); let ym = map(p - e.yxy);
    let zp = map(p + e.yyx); let zm = map(p - e.yyx);
    let centerD = map(p);
    let n = normalize(vec3<f32>(xp - xm, yp - ym, zp - zm) + vec3<f32>(1e-6));
    let curv = clamp((xp + xm + yp + ym + zp + zm - 6.0 * centerD) / (eps * eps) * 0.035, -1.0, 1.0);
    return vec4<f32>(n, curv);
}

// 5-tap SDF ambient occlusion inside gyroid chambers (§12.2E)
fn coralAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 1; i <= 5; i++) {
        let h = 0.02 + 0.09 * f32(i);
        occ += (h - map(p + n * h)) * sca;
        sca *= 0.55;
    }
    return clamp(1.0 - 2.4 * occ, 0.08, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) { return; }
    let pixel = vec2<i32>(id.xy);
    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / max(resolution.y, 1.0);
    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.5);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.5);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.5);

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, time * u.zoom_params.z);
    var rd = normalize(vec3<f32>(uv, 1.0));
    let rxy = rd.xy * rot2D(sin(time * 0.2) * 0.1);
    rd = vec3<f32>(rxy, rd.z);

    var clickBurst = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    let aspect = resolution.x / max(resolution.y, 1.0);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ev = u.ripples[ri];
        let age = time - ev.z;
        let liveMask = f32(age >= 0.0 && age < 2.5);
        let safeAge = max(age, 0.0);
        let evUV = (ev.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
        clickBurst += liveMask * exp(-abs(length(uv - evUV) - safeAge * 0.32) * 36.0) * exp(-safeAge * 1.3);
    }

    let result = raymarch(ro, rd, mids);
    let t = result.x;
    let glow = result.y;
    let synGlow = result.z;

    var color = vec3<f32>(0.0);
    var out_depth = 1.0;
    let biolum = max(u.zoom_params.w, 0.0);

    if (t > 0.0) {
        let p = ro + rd * t;
        // ── Idea 2: 5-tap gyroid cavern AO (§12.2E) & SDF curvature chromoprotein rims (§12.2E) ─
        let nc = getNormalAndCurvature(p);
        let n = nc.xyz;
        let ridgeCrest = clamp(nc.w, 0.0, 1.0);
        let polypPocket = clamp(-nc.w, 0.0, 1.0);
        let ao = coralAO(p, n);

        let lightDir = normalize(vec3<f32>(sin(time), 1.0, cos(time)));
        let diff = max(dot(n, lightDir), 0.0);
        let sss = clamp(map(p + lightDir * 0.2) / 0.2, 0.0, 1.0);
        let fresnel = pow(clamp(1.0 - max(dot(-rd, n), 0.0), 0.0, 1.0), 3.5);
        let baseColor = mix(vec3<f32>(0.018, 0.11, 0.17), vec3<f32>(0.12, 0.045, 0.13), clamp(p.y * 0.5 + 0.5, 0.0, 1.0));

        // ── Idea 1 (part b): synaptic action-potential waves along coral channels ──
        let actionWave = pow(0.5 + 0.5 * sin(p.z * 2.3 - time * (3.1 + mids * 1.6) + sin(p.x * 1.7 + p.y * 1.7)), 6.0);
        let chromoRim = mix(vec3<f32>(0.08, 0.95, 0.85), vec3<f32>(1.05, 0.28, 0.72), clamp(ridgeCrest * 0.8 + mids * 0.25, 0.0, 1.0));

        color = baseColor * (diff * 0.62 + 0.38) * (0.45 + 0.55 * sss) * ao * (1.0 - polypPocket * 0.28);
        color += chromoRim * (ridgeCrest * 0.55 + fresnel * 0.35) * (0.35 + biolum * 0.55 + treble * 0.35) * ao;
        color += mix(vec3<f32>(0.0, 0.82, 1.0), vec3<f32>(0.78, 0.24, 1.05), actionWave)
               * (glow * 0.55 + synGlow * 1.35 + actionWave * 0.45 + clickBurst * 0.9) * biolum * (0.65 + bass * 0.35);
        color = mix(color, vec3<f32>(0.002, 0.014, 0.035), 1.0 - exp(-0.06 * t));
        out_depth = clamp(t / 20.0, 0.0, 1.0);
    } else {
        color = vec3<f32>(0.003, 0.016, 0.04)
              + mix(vec3<f32>(0.0, 0.55, 0.85), vec3<f32>(0.65, 0.2, 0.95), clamp(synGlow / max(glow, 0.001), 0.0, 1.0))
              * glow * 0.055 * (0.4 + biolum * 0.6 + clickBurst);
    }

    let mapped = acesToneMap(max(color, vec3<f32>(0.0)));
    let hitMask = select(0.0, 1.0, t > 0.0);
    let alpha = clamp(hitMask * (0.76 + (1.0 - out_depth) * 0.20) + (1.0 - hitMask) * clamp(glow * 0.06, 0.05, 0.62) + clickBurst * 0.15, 0.05, 0.98);

    let prev = textureLoad(dataTextureC, pixel, 0);
    let refractory = clamp(mix(mapped, max(mapped, prev.rgb * 0.92), 0.16), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, pixel, vec4<f32>(refractory, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(refractory, alpha));
}