// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Aether-Pulsar
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive, click-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27, 2026-10-25
//  Ideas: spin-locked twin jet lobes above/below the disk plane; Keplerian
//         azimuthal shear striping on the accretion disk noise;
//         shockwave-triggered core brightness flare tying clicks into the
//         pulsar material itself; Henyey-Greenstein jet beaming (§12.2F);
//         relativistic Doppler boost + blue/red shift on the disk (§12.1 t2)
//  HEAD fixes: orbit camera now aimed at the origin and y-up (was upside-down,
//         pulsar cut off); non-persisting extraBuffer cursor spring removed
//  A packing: display RGBA (unchanged)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Pulsar Spin Rate, y=Beam Intensity, z=Accretion Density, w=Color Shift

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotate3DY(angle: f32) -> mat3x3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat3x3<f32>(
        c, 0.0, -s,
        0.0, 1.0, 0.0,
        s, 0.0, c
    );
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D noise for fluid core and debris
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

// Henyey–Greenstein phase (4π-normalised: mean over the sphere is 1)
fn hgPhase(cosA: f32, g: f32) -> f32 {
    let g2 = g * g;
    let den = max(1.0 + g2 - 2.0 * g * cosA, 0.02);
    return (1.0 - g2) / (den * sqrt(den));
}

// --- SDFs ---
fn map(p: vec3<f32>) -> vec2<f32> {
    let t = u.config.x * u.zoom_params.x;
    let audio = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Core (Sphere twisted by Y)
    var q_core = p;
    q_core = rotate3DY(t + q_core.y * 0.5) * q_core;
    let core_noise = noise3(q_core * 2.0 + t) * (0.18 + audio * 0.35 + mids * 0.12);
    let d_core = length(q_core) - 1.0 - core_noise;

    // Accretion disk (Torus with noise/folds)
    var q_disk = p;
    q_disk.y += noise3(q_disk * 1.5 - t * 0.5) * 0.3 * audio;
    let d2 = vec2<f32>(length(q_disk.xz) - 2.5, q_disk.y);
    let diskThickness = mix(0.22, 0.68, u.zoom_params.z);
    let d_disk_base = length(d2) - diskThickness;
    // Keplerian shear: inner radii wind faster than outer ones, warping the
    // noise sample azimuthally so the disk shows spiral banding instead of
    // static noise.
    let diskRadius = length(q_disk.xz);
    let shearAngle = -diskRadius * u.zoom_params.x * 1.4 + t * 0.5;
    let shearRot = rotate2D(shearAngle);
    let shearedXZ = shearRot * q_disk.xz;
    let d_disk = d_disk_base + noise3(vec3<f32>(shearedXZ.x, q_disk.y, shearedXZ.y) * 4.0) * mix(0.32, 0.08, u.zoom_params.z);

    // Smoothmin between core and disk where they might interact
    let d = smin(d_core, d_disk, 0.5);

    var mat_id = 0.0;
    if d_disk < d_core {
        mat_id = 1.0; // Disk
    }

    return vec2<f32>(d, mat_id);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p).x;
    return normalize(vec3<f32>(
        map(p + e.xyy).x - d,
        map(p + e.yxy).x - d,
        map(p + e.yyx).x - d
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= resolution.x || fragCoord.y >= resolution.y) {
        return;
    }

    var uv = (fragCoord - 0.5 * resolution) / resolution.y;

    let time = u.config.x;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

    // HEAD fix: the camera used to sit at a fixed (0,2,-6) looking straight down +z with
    // y-down uv, so the pulsar was upside-down and cut off at the top; the extraBuffer
    // cursor spring never persisted. Orbit camera aimed at the origin, y-up, cursor-driven.
    let azim = (rawMouse.x - 0.5) * 6.28;
    let elev = clamp(0.3217 + (0.5 - rawMouse.y) * 2.4, -1.35, 1.35);
    let camR = 7.6;
    let ro = camR * vec3<f32>(sin(azim) * cos(elev), sin(elev), -cos(azim) * cos(elev));
    let fwd = -ro / camR;
    let camRight = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let camUp = cross(fwd, camRight);
    let rd = normalize(camRight * uv.x - camUp * uv.y + fwd);

    // ── Idea 1 (§12.2F Henyey–Greenstein): relativistic jet beaming. A jet pointing at the
    // viewer is boosted, one pointing away is dimmed; edge-on stays 1.0 so the default
    // 3/4 view keeps its old brightness and only looking down a jet flares it.
    let hgNorm = hgPhase(0.0, 0.4);
    let beamUp = clamp(hgPhase(-rd.y, 0.4) / hgNorm, 0.4, 3.5);
    let beamDown = clamp(hgPhase(rd.y, 0.4) / hgNorm, 0.4, 3.5);

    // Raymarching
    var t = 0.0;
    var d: vec2<f32>;
    var p = ro;
    var glow = 0.0;
    var hit = false;

    for(var i=0; i<80; i++) {
        p = ro + rd * t;
        d = map(p);

        // Volumetric beams — spin-locked twin jets: the two lobes above and
        // below the disk plane carry a slight brightness asymmetry driven by
        // Pulsar Spin Rate, so it reads as a bipolar jet pair, not one tube.
        let jetLobe = sign(p.y + 0.0001);
        let jetAsym = (1.0 + jetLobe * (u.zoom_params.x - 0.5) * 0.7) * select(beamDown, beamUp, jetLobe > 0.0);
        let beam_dist = length(p.xz) - 0.2 * (1.0 + p.y * 0.1);
        glow += exp(-abs(beam_dist) * 7.0) * 0.025 * u.zoom_params.y * (1.0 + plasmaBuffer[0].z * 0.5) * jetAsym;

        if(d.x < 0.001) { hit = true; break; }
        if(t > 20.0) { break; }
        t += max(abs(d.x) * 0.55, 0.002);
    }

    var col = vec3<f32>(0.0);
    let audio = plasmaBuffer[0].x;

    // Click shockwave shells — computed early so the core material itself can
    // flare when a shell passes through it, not just a screen-space overlay.
    let uv01 = (fragCoord + vec2<f32>(0.5)) / resolution;
    var pulsarShock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.6) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(resolution.x / resolution.y, 1.0);
            let shell = exp(-abs(length(delta) - age * 0.3) * 76.0) * exp(-age * 1.9);
            pulsarShock = max(pulsarShock, shell);
        }
    }

    if (hit) {
        let palette = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(0.0, 2.1, 4.2) + u.zoom_params.w * 6.28318);
        // Base color
        if d.y < 0.5 { // Core
            col = mix(vec3<f32>(0.08, 0.25, 0.75), palette, 0.45) + palette * abs(p.y) * 0.35;
            // Shockwave-triggered core flare: a passing click shell briefly
            // spikes the core's own brightness instead of staying screen-only.
            col += palette * pulsarShock * 1.6;
        } else { // Disk
            col = mix(vec3<f32>(0.15, 0.65, 0.8), palette, 0.35) * (1.0 + audio * 0.5);
            // ── Idea 2 (§12.1 tactic 2): Doppler boost + shift on the disk. The tangential
            // direction is the same sense as the Keplerian shear; the limb moving toward the
            // camera is brighter and bluer, the receding limb dimmer and warmer.
            let rr = max(length(p.xz), 0.5);
            let vdir = vec3<f32>(-p.z, 0.0, p.x) / rr;
            let beta = clamp(0.62 * (0.3 + 0.7 * u.zoom_params.x) / sqrt(rr), 0.0, 0.6);
            let dop = 1.0 / (sqrt(1.0 - beta * beta) * (1.0 - beta * dot(vdir, -rd)));
            col *= clamp(dop * dop, 0.4, 2.2);
            col *= mix(vec3<f32>(1.12, 0.96, 0.82), vec3<f32>(0.82, 0.98, 1.2), clamp(0.5 + (dop - 1.0) * 2.5, 0.0, 1.0));
        }

        // Lighting
        let n = calcNormal(p);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
        col *= diff + 0.18;
        col += palette * fresnel * 0.55;
    }

    // Add volumetric glow
    col += vec3<f32>(0.1, 0.8, 1.0) * glow;

    col += vec3<f32>(0.4, 0.9, 1.4) * pulsarShock * (0.7 + plasmaBuffer[0].z * 0.35);
    let coord = vec2<i32>(id.xy);
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(max(col, vec3<f32>(0.0)), prev.rgb * 0.9, clamp(0.025 + plasmaBuffer[0].y * 0.008, 0.0, 0.05));
    col = acesToneMap(col * 1.08);
    let _alpha = clamp(select(0.05, 0.76, hit) + glow * 0.12 + pulsarShock * 0.2, 0.0, 0.96);
    let outColor = vec4<f32>(col, _alpha);
    let _depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
