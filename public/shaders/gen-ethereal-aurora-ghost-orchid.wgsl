// ═══════════════════════════════════════════════════════════════════
//  Ethereal-Aurora Ghost-Orchid
//  Category: generative
//  Features: mouse-driven, audio-reactive, click-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-10-25
//  Ideas: bass bloom lifts the red 630 nm oxygen band ceiling and unfurls petals;
//         raymarch hit distance written as depth; metastable per-channel persistence
//         (630 nm red lingers, 557 green / 428 blue fade faster); auroral vertical
//         ray striations, density from Petal Complexity; 3rd pass (2026-10-25):
//         additive domain twist along the stem axis (§12.2E); soft inverse-square
//         stamen light, petal root gain + volumetric halo (§12.2F); sharp lower
//         auroral border (§12.1 physics). HEAD fixes: upside-down view / mirrored
//         pole, racy extraBuffer[133..138] spring (never persisted) removed.
//  A packing: ACES display RGB blended with exact C read; alpha = aurora
//             emission/shock/held coverage (semantic, never 1.0)
//  Enrichment: aurora altitude physics (557.7 / 630.0 / 427.8 nm bands)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn smax(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotY(angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat3x3<f32>(
        c, 0.0, s,
        0.0, 1.0, 0.0,
        -s, 0.0, c
    );
}

fn snoise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_smooth = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);
    let n = p.x + p.y * 157.0 + p.z * 113.0;

    let v1 = mix(hash1(n + 0.0), hash1(n + 1.0), f_smooth.x);
    let v2 = mix(hash1(n + 157.0), hash1(n + 158.0), f_smooth.x);
    let v3 = mix(hash1(n + 113.0), hash1(n + 114.0), f_smooth.x);
    let v4 = mix(hash1(n + 270.0), hash1(n + 271.0), f_smooth.x);

    let res1 = mix(v1, v2, f_smooth.y);
    let res2 = mix(v3, v4, f_smooth.y);
    return mix(res1, res2, f_smooth.z) * 2.0 - 1.0;
}

fn map(p_in: vec3<f32>, time: f32, audio_react: f32, mouse_pos: vec2<f32>, bass: f32) -> f32 {
    var p = p_in;

    // Mouse Interaction: Magnetic field disturbance
    let mouse_world = vec3<f32>((mouse_pos.x - 0.5) * 5.0, (mouse_pos.y - 0.5) * -5.0, 0.0);
    let dist_mouse = length(p.xy - mouse_world.xy);
    let pull = smoothstep(3.0, 0.0, dist_mouse);
    // Magnetic field line spiral distortion
    let spiral = sin(atan2(p.y - mouse_world.y, p.x - mouse_world.x) * 3.0 + dist_mouse * 2.0 - time * 2.0);
    p.x -= pull * (mouse_world.x - p.x) * 0.5 + spiral * pull * 0.3;
    p.y -= pull * (mouse_world.y - p.y) * 0.5 + spiral * pull * 0.3;

    // Solar wind particle density driven by bass
    let solarWind = 1.0 + bass * 2.0;
    p.z += sin(p.x * solarWind + time) * 0.05 * pull;

    // ── Idea 1: additive domain twist (§12.2E). The stem axis is z, so petals spiral
    // as they bend away from the flower; Audio Reactivity still owns the motion.
    let twistXY = rot2(p.z * (0.3 + 0.15 * audio_react)) * p.xy;
    p.x = twistXY.x;
    p.y = twistXY.y;

    // Stem
    let stem_d = length(p.xy) - 0.05 + p.z * 0.01;

    // Petals
    var petal_d = 100.0;
    let num_petals = 5.0;
    for (var i = 0.0; i < num_petals; i += 1.0) {
        let angle = (i / num_petals) * PI * 2.0 + time * 0.2;
        var q = p;
        let q_xy = rot2(angle) * q.xy;
        q.x = q_xy.x;
        q.y = q_xy.y;

        q.y -= 0.5;

        // Bend
        q.z -= q.y * q.y * 0.5;

        // Unfurl with audio
        q.x += sin(q.y * 5.0 + time) * 0.2 * audio_react;

        let d = length(vec3<f32>(q.x, smax(0.0, abs(q.y) - 1.5, 0.2), q.z)) - 0.05 - smax(0.0, 1.0 - abs(q.y), 0.5) * 0.1;
        petal_d = smin(petal_d, d, 0.2);
    }

    // Core Stamen
    var core_d = length(p) - 0.2 - audio_react * 0.1;

    // Combine and add noise displacement
    var d = smin(stem_d, petal_d, 0.5);
    d = smin(d, core_d, 0.3);

    let disp = snoise(p * 2.0 + vec3<f32>(time * 0.5, time * 0.2, time * 0.1)) * 0.1;

    return d + disp;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    // HEAD fix: flip y so the orchid stands upright and the pole follows the cursor.
    let uv = vec2<f32>(fragCoord.x - 0.5 * res.x, 0.5 * res.y - fragCoord.y) / res.y;
    let uv01 = (fragCoord + 0.5) / res;
    let time = u.config.x;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = bass * 0.5 + mids * 0.3 + treble * 0.2;
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

    // HEAD fix: the extraBuffer[133..138] spring/envelope never persisted (the buffer is
    // re-uploaded each frame) and (0,0) wrote it while other pixels read it. The pole
    // follows the cursor directly and the bloom envelope is the live bass.
    let pole = mouse;
    let bloomEnv = bass;

    let petal_complex = u.zoom_params.x;
    let aurora_int = u.zoom_params.y;
    let audio_react = u.zoom_params.z * (audio + bloomEnv * 0.5);
    let pollen_dens = u.zoom_params.w;

    var ro = vec3<f32>(0.0, 0.0, -5.0 + held * 0.65);
    var rd = normalize(vec3<f32>(uv, 1.0));

    ro = rotY(time * 0.1) * ro;
    rd = rotY(time * 0.1) * rd;

    var t = 0.0;
    var d = 0.0;
    var col = vec3<f32>(0.0);
    var emission = vec3<f32>(0.0);
    var hitT = -1.0;
    var haloAcc = 0.0;

    // Raymarching
    for (var i = 0; i < 64; i += 1) {
        let p = ro + rd * t;
        d = map(p, time, audio_react, pole, bass);

        if (d < 0.01) {
            // Altitude-based aurora emission physics
            let altitude = clamp(p.y * 0.5 + 0.5, 0.0, 1.0);

            // Green (557.7 nm): oxygen at lower altitude (100-240 km)
            let greenOxygen = vec3<f32>(0.2, 1.0, 0.3);
            // Red (630.0 nm): oxygen above 240 km
            let redOxygen = vec3<f32>(1.0, 0.1, 0.1);
            // Purple/blue (427.8 nm): nitrogen at lower altitudes
            let blueNitrogen = vec3<f32>(0.4, 0.2, 1.0);

            // Idea 2nd-pass B: auroral ray striations. Noise depends on x/z (and only very
            // slowly on y), so brightness forms vertical curtains that drift with time.
            // Petal Complexity sets ray density. Remapped to mean ~1 so default emission stays close.
            let ray_n = 0.5 + 0.5 * snoise(vec3<f32>(p.x * petal_complex * 1.5 + p.y * 0.15,
                                                     p.z * petal_complex * 1.5,
                                                     -time * 0.7));
            let ray = mix(0.45, 1.6, ray_n * ray_n * (3.0 - 2.0 * ray_n));

            // Altitude-based color gradient
            var aurora_col: vec3<f32>;
            let redCeil = 0.7 - clamp(bloomEnv, 0.0, 1.0) * 0.2;
            if (d < 0.01 && hitT < 0.0) { hitT = t; }
            if (altitude < 0.4) {
                aurora_col = mix(blueNitrogen, greenOxygen, altitude / 0.4);
            } else if (altitude < redCeil) {
                aurora_col = mix(greenOxygen, redOxygen, (altitude - 0.4) / max(redCeil - 0.4, 0.01));
            } else {
                aurora_col = redOxygen;
            }

            // Magnetic field line curvature modulates color
            let fieldLine = sin(p.x * PI * 3.0) * 0.5 + 0.5;
            aurora_col = mix(aurora_col, aurora_col * vec3<f32>(1.2, 0.9, 1.1), fieldLine * 0.3);

            // Solar wind intensity = bass-driven particle density
            let solarWindInt = 1.0 + bass * 3.0;
            // ── Idea 3: sharp lower auroral border (§12.1 physics): electron penetration
            // ends abruptly, so the lower edge of a curtain is crisp, the upper edge soft.
            let lowerBorder = mix(0.3, 1.0, smoothstep(0.08, 0.2, altitude));
            // ── Idea 2: soft inverse-square stamen light (§12.2F), petals brighten toward the core.
            let stamenGain = 1.0 + 0.7 * 0.6 / (dot(p, p) + 0.6);
            emission += aurora_col * 0.05 * aurora_int * solarWindInt * ray * lowerBorder * stamenGain / (1.0 + abs(d) * 10.0);

            haloAcc += 0.02 / (dot(p, p) + 0.5);
            t += 0.02;
        } else {
            haloAcc += d / (dot(p, p) + 0.5);
            t += d;
        }

        if (t > 10.0) { break; }
    }

    // Add pollen
    let pollen_val = snoise(vec3<f32>(uv * 20.0, time));
    if (pollen_val > 0.8) {
        let spark = pow(pollen_val, 10.0) * pollen_dens;
        emission += vec3<f32>(1.0, 0.8, 0.2) * spark;
    }

    // Stamen in-scatter: line integral of the soft inverse-square light along the ray.
    emission += vec3<f32>(0.25, 0.9, 0.5) * haloAcc * 0.015 * aurora_int;

    col += emission;

    var auroraShock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.5) {
            let front = abs(length((uv01 - ripple.xy) * vec2<f32>(res.x / res.y, 1.0)) - age * 0.16);
            auroraShock += (1.0 - smoothstep(0.0, 0.024, front)) * (1.0 - age / 3.5);
        }
    }
    auroraShock = min(auroraShock, 2.0);
    col += vec3<f32>(0.2 + treble * 0.4, 1.0, 0.65 + mids * 0.4) * auroraShock * aurora_int * 0.35;
    col += vec3<f32>(0.7, 0.2, 1.0) * held * exp(-length((uv01 - mouse) * vec2<f32>(res.x / res.y, 1.0)) * 8.0) * 0.35;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // Exact feedback on ACES display RGB (A holds display RGBA).
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    let mapped = acesToneMap(max(col, vec3<f32>(0.0)) * 1.1);
    // Idea 2nd-pass A: metastable persistence — 630 nm red lingers (long O(1D) lifetime),
    // 557.7 nm green and 427.8 nm blue decay faster. Replaces the uniform 0.96.
    let persist = vec3<f32>(0.985, 0.90, 0.93);
    let display = clamp(mix(prev.rgb * persist, mapped, 0.3), vec3<f32>(0.0), vec3<f32>(1.0));
    let alpha = clamp(length(emission) * 0.35 + auroraShock * 0.2 + held * 0.08, 0.04, 0.95);
    let outAlpha = clamp(mix(prev.a * 0.96, alpha, 0.3), 0.0, 0.95);
    let depth = select(0.0, clamp(1.0 - hitT / 10.0, 0.0, 1.0), hitT >= 0.0);
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(display, outAlpha));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(display, outAlpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
