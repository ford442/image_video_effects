// ═══════════════════════════════════════════════════════════════════
//  Synaptic Void-Weaver
//  Category: generative
//  Features: mouse-driven, audio-reactive, click-reactive, raymarching, temporal-feedback, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: smin junction soma & orbit-trap firing in map().y (§12.2E); 5-tap fractal SDF AO (§12.2E) & refractory C afterglow
//  A packing: ACES display RGBA (synaptic refractory trail)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Helper: 3D Rotation Matrix
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

// Helper: Smooth Min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Map function (SDF): .x = signed distance, .y = synaptic junction + orbit-trap potential
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    let res = max(u.config.zw, vec2<f32>(1.0));
    let aspect = res.x / res.y;

    // Guarded branchless mouse gravity well (gentle hover warp, full well when held)
    let mouse_pos = vec3<f32>((u.zoom_config.y * 2.0 - 1.0) * aspect, 1.0 - u.zoom_config.z * 2.0, 0.0);
    let deltaM = p - mouse_pos;
    let dist2 = dot(deltaM, deltaM);
    let pull = select(0.08, 0.50, u.zoom_config.w > 0.5);
    p -= deltaM * inverseSqrt(max(dist2, 0.0001)) * (pull / (dist2 + 0.1));

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.5);

    // Domain Warping / Fractal
    var d = 100.0;
    var synapse = 0.0;
    var trap = 1e9;
    let iterations = clamp(i32(u.zoom_params.y), 1, 8);
    let thickness = u.zoom_params.z;
    let rot_speed = u.zoom_params.w;
    let foldRot = rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), u.config.x * rot_speed);

    for (var i = 0; i < iterations; i++) {
        p = abs(p) - 1.0;
        p = p * foldRot;

        let tube = length(p.xy) - thickness - (bass * 0.05);
        // ── Idea 1: synaptic soma junctions & orbit-trap veins in map().y (§12.2E) ──
        let h = clamp(0.5 + 0.5 * (tube - d) / 0.5, 0.0, 1.0);
        let junction = 4.0 * h * (1.0 - h);
        d = smin(d, tube, 0.5) - junction * thickness * 0.22;
        synapse = max(synapse, junction);
        trap = min(trap, length(p.xz));
    }

    let potential = clamp(synapse * 0.68 + exp(-trap * 2.6) * 0.32, 0.0, 1.0);
    return vec2<f32>(d, potential);
}

// Compute Normals
fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let grad = vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    );
    return grad * inverseSqrt(max(dot(grad, grad), 1e-10));
}

// ── Idea 2 (part a): 5-tap fractal SDF ambient occlusion (§12.2E) ──────────
fn calcAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 1; i <= 5; i = i + 1) {
        let h = 0.015 + 0.15 * f32(i) / 5.0;
        occ += (h - map(p + n * h).x) * sca;
        sca *= 0.5;
    }
    return clamp(1.0 - 2.6 * occ, 0.08, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let coord = vec2<i32>(id.xy);
    let uv01 = (vec2<f32>(id.xy) + 0.5) / res;
    let uv = (vec2<f32>(id.xy) * 2.0 - res) / res.y;
    let time = u.config.x;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slight rotation over time
    let cam_rot = rot3D(vec3<f32>(0.0, 1.0, 0.0), time * 0.05);
    ro = ro * cam_rot;
    rd = rd * cam_rot;

    // Click action-potential depolarization wave in screen space
    var clickSpike = 0.0;
    let aspect = res.x / max(res.y, 1.0);
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var r = 0u; r < rippleCount; r = r + 1u) {
        let rip = u.ripples[r];
        let age = time - rip.z;
        if (age >= 0.0 && age < 2.2) {
            let rDist = length((uv01 - rip.xy) * vec2<f32>(aspect, 1.0));
            clickSpike += exp(-abs(rDist - age * 0.32) * 36.0) * exp(-age * 1.1);
        }
    }

    // Raymarching
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = 0.0;
    var hitSurface = 0.0;

    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.5);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.5);

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let d = map(p);

        if (d.x < 0.001) {
            hitSurface = 1.0;
            let n = get_normal(p);
            let ao = calcAO(p, n);
            let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
            let diff = max(dot(n, light_dir), 0.0);

            // Base color: dark obsidian sculpted by fractal crevice AO
            let base_color = vec3<f32>(0.05, 0.05, 0.08);
            let spec = pow(max(dot(reflect(-light_dir, n), -rd), 0.0), 32.0);

            // Emissive layer: cyan/magenta bioluminescence + gold-white burst at synaptic junctions
            let emissive = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(p.z * 5.0 + time) * 0.5 + 0.5);
            let pulse = sin(p.x * 10.0 - time * 5.0) * 0.5 + 0.5;
            let somaFire = d.y * (pulse * (0.85 + mids * 1.1) + clickSpike * 1.6);
            let synapseColor = mix(emissive, vec3<f32>(0.65, 0.95, 1.35), d.y * 0.65);

            col = (base_color + diff * vec3<f32>(0.22)) * ao
                + spec * vec3<f32>(1.0) * (0.35 + 0.65 * ao)
                + synapseColor * (pulse * (0.45 + treble * 1.6) + somaFire * 1.35);
            break;
        }

        t += d.x;
        glow += (0.02 + d.y * 0.014) / (0.01 + d.x * d.x);

        if (t > 10.0) {
            // Background: subtle deep purple glow
            col = vec3<f32>(0.1, 0.0, 0.2) * max(1.0 - length(uv) * 0.5, 0.0);
            break;
        }
    }

    let glowContrib = (vec3<f32>(0.0, 0.5, 1.0) + vec3<f32>(0.35, 0.1, 0.55) * mids * 0.4) * glow * u.zoom_params.x * 0.01;
    col += glowContrib;

    // ── Idea 2 (part b): synaptic refractory afterglow in C & ACES output ──
    let prev = textureLoad(dataTextureC, coord, 0);
    let mapped = acesToneMap(max(col, vec3<f32>(0.0)));
    let refractory = mix(mapped, max(mapped, prev.rgb * 0.86), 0.22);
    let glowDensity = clamp(glow * u.zoom_params.x * 0.008, 0.0, 1.0);
    let alpha = clamp(hitSurface * 0.78 + glowDensity * 0.55 + prev.a * 0.10, 0.12, 0.98);
    let outColor = vec4<f32>(refractory, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(t / 10.0, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
