// ----------------------------------------------------------------
// Cymatic Void-Glass Geode
// Category: generative
// Features: audio-reactive, mouse-driven, raymarched, depth-aware
// Upgraded: 2026-11-10
// Ideas: Chladni nodal sand-lines on the cymatic surface (§12.2E promote the wave); step-count ambient occlusion (§12.2E)
// A packing: display RGB in writeTexture (no A write, as HEAD)
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 10.0;

// Palette function for iridescence
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// 2D Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// The cymatic standing wave (unscaled). `map()` multiplies it by the amplitude;
// the shading reads its zero set (the nodal lines) from the same function.
fn cymaticWave(p: vec3<f32>, t: f32) -> f32 {
    let freq = u.zoom_params.y * 10.0; // Frequency param
    return sin(length(p) * freq - t) * cos(atan2(p.y, p.x) * 4.0);
}

// SDF with Apollonian fractal and Cymatic displacement
fn map(p: vec3<f32>) -> vec2<f32> { // returns vec2(distance, orbit_trap)
    var q = p;
    let time = u.config.x * u.zoom_params.x; // Speed param

    // Mouse gravity well distortion
    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    let mouse_pos = vec3<f32>(mouse_uv.x, -mouse_uv.y, 0.0);
    if (u.zoom_config.w > 0.5) {
        let dir = mouse_pos - q;
        let dist = length(dir);
        q += normalize(dir) * (0.5 * u.zoom_params.w) / (dist + 0.1); // Gravity param
    }

    var scale = 1.0;
    var orb = 1000.0;

    // Apollonian folding
    for (var i = 0; i < 4; i++) {
        q = -1.0 + 2.0 * fract(0.5 * q + 0.5);
        let r2 = dot(q, q);
        orb = min(orb, r2);
        let k = 1.2 / r2;
        q *= k;
        scale *= k;

        let a = f32(i) * 0.5 + time * 0.1;
        let new_xy = rot(a) * q.xy;
        q.x = new_xy.x;
        q.y = new_xy.y;
    }

    let base_sdf = (length(q) - 0.25) / scale;

    // Audio reactivity. RESCUE: HEAD read dataTextureC(0,0), which nothing in this
    // file ever writes, so the audio claim was dead. Bass is plasmaBuffer[0].x.
    // The factor is kept moderate so a loud bass cannot overstep the march.
    let audio_sample = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let audio_mod = 1.0 + audio_sample * 0.8;

    // Cymatic displacement
    let amp = u.zoom_params.z * 0.1 * audio_mod;   // Amplitude param mod with audio
    let disp = cymaticWave(p, time) * amp;

    return vec2<f32>(base_sdf + disp, orb);
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> { // returns vec3(distance, steps, orbit_trap)
    var dO = 0.0;
    var min_orb = 1000.0;
    var i = 0;
    for (; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let res = map(p);
        let dS = res.x;
        min_orb = min(min_orb, res.y);
        dO += dS;
        if (dO > MAX_DIST || abs(dS) < SURF_DIST) { break; }
    }
    return vec3<f32>(dO, f32(i), min_orb);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// ── Idea 2: step-count ambient occlusion (§12.2E) ─────────────────────
// Five taps of the file's own map() along the normal; a crevice between folds
// reports a distance smaller than the step, and the deficit accumulates.
fn aoFive(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 1; i <= 5; i = i + 1) {
        let h = 0.01 + 0.12 * f32(i) / 5.0;
        occ += (h - map(p + n * h).x) * sca;
        sca *= 0.5;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    var uv = (fragCoord - 0.5 * res) / res.y;
    let time = u.config.x;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -2.0 + sin(time*0.2)*0.5); // Slight dolly
    let lookat = vec3<f32>(0.0, 0.0, 0.0);
    let zoom = 1.0;

    let f = normalize(lookat - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let u_cam = cross(f, r);
    var rd = normalize(uv.x * r + uv.y * u_cam + f * zoom);

    // Raymarch
    let rm = raymarch(ro, rd);
    let d = rm.x;
    let steps = rm.y;
    let orb = rm.z;

    var col = vec3<f32>(0.0);

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(ro - p);

        // Iridescence (Void-Glass effect)
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 5.0);
        let iri_color = palette(fresnel + orb * 0.1,
                                vec3<f32>(0.5, 0.5, 0.5),
                                vec3<f32>(0.5, 0.5, 0.5),
                                vec3<f32>(1.0, 1.0, 1.0),
                                vec3<f32>(0.0, 0.33, 0.67));

        // Inner Glow (Veins)
        let glow = exp(-orb * 5.0) * vec3<f32>(0.2, 0.8, 1.0);

        let ao = aoFive(p, n);
        col = (diff * 0.2 + iri_color * 0.8) * (1.0 - fresnel * 0.5) * mix(0.35, 1.0, ao)
            + glow * mix(0.6, 1.0, ao);

        // ── Idea 1: Chladni nodal lines ─────────────────────────────────
        // Cymatics is defined by its nodal lines: where the plate does not move,
        // sand collects. That zero set is exactly cymaticWave() == 0 on the surface.
        // Width follows the wave's slope (closed form) so lines stay crisp; they
        // exist only while the plate vibrates (Cymatic Amp / Freq above zero).
        let waveT = time * u.zoom_params.x;
        let wave = cymaticWave(p, waveT);
        let waveFreq = u.zoom_params.y * 10.0;
        let waveR = max(length(p), 0.05);
        let wavePhase = waveR * waveFreq - waveT;
        let waveTheta = atan2(p.y, p.x) * 4.0;
        let waveSlope = max(abs(waveFreq * cos(wavePhase) * cos(waveTheta))
                          + abs(4.0 / waveR * sin(wavePhase) * sin(waveTheta)), 0.3);
        let nodal = exp(-pow(wave / (waveSlope * 0.035), 2.0))
                  * smoothstep(0.0, 0.3, u.zoom_params.z) * smoothstep(0.05, 0.4, u.zoom_params.y);
        col += vec3<f32>(0.55, 0.95, 1.0) * nodal * (0.45 + clamp(plasmaBuffer[0].x, 0.0, 1.0) * 0.5);

        // Subsurface scattering approximation based on step count
        col += vec3<f32>(0.1, 0.05, 0.2) * (steps / f32(MAX_STEPS));
    } else {
        // Deep space background
        col = vec3<f32>(0.0, 0.0, 0.02) * (1.0 - length(uv));
    }

    // Gamma correction
    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
    // Truthful relief depth: the nearer the geode surface, the higher the value.
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(select(0.0, 1.0 - clamp(d / MAX_DIST, 0.0, 1.0), d < MAX_DIST), 0.0, 0.0, 0.0));
}
