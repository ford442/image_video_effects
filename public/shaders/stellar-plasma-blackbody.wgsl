// ═══════════════════════════════════════════════════════════════════
//  Stellar Plasma Blackbody
//  Category: advanced-hybrid
//  Features: generative, blackbody-radiation, procedural, audio-reactive, mouse-driven, HDR, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15, 2026-11-01
//  Ideas: |∇f| magnetic filaments; warp-advected C heat; Stefan-Boltzmann cooling wake (replaces max ratchet); Beer-Lambert dust lanes from warp vector q; hot-core halo from C heat
//  A packing: raw thermal RGB + normalized T
// ═══════════════════════════════════════════════════════════════════
//  Cosmic nebula domain-warped FBM blended with Planck's law
//  blackbody thermal coloring. Energy intensity drives temperature
//  mapping — cool voids glow ember-red, hot plasma cores burn
//  blue-white with physically-correct radiance scaling.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const HASH_CONST1: vec3<f32> = vec3<f32>(0.1031, 0.1031, 0.1031);
const HASH_CONST2: vec3<f32> = vec3<f32>(33.33, 33.33, 33.33);

fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * HASH_CONST1);
    p3 += dot(p3, p3.yzx + HASH_CONST2);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    let u_f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u_f.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u_f.x),
        u_f.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let shift = vec2<f32>(100.0, 100.0);
    let c: f32 = 0.87758256189;
    let s: f32 = 0.4794255386;
    let rot = mat2x2<f32>(vec2<f32>(c, s), vec2<f32>(-s, c));
    var p_mut = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        v += a * noise(p_mut);
        p_mut = rot * p_mut * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
    // Tanner Helland's fit works in T/100 (the previous T/1000 units zeroed g/b below
    // ~5000 K, so the ember-red voids never showed and the hot branch was off-scale).
    let t = clamp(temperatureK / 100.0, 10.0, 300.0);
    var r: f32;
    var g: f32;
    var b: f32;
    if (t <= 66.0) {
        r = 1.0;
        g = clamp(0.39 * log(t) - 0.632, 0.0, 1.0);
        b = select(clamp(0.543 * log(max(t - 10.0, 1.0)) - 1.196, 0.0, 1.0), 0.0, t <= 19.0);
    } else {
        let h = max(t - 60.0, 1.0);
        r = clamp(1.29 * pow(h, -0.1332), 0.0, 1.0);
        g = clamp(1.13 * pow(h, -0.0755), 0.0, 1.0);
        b = 1.0;
    }
    // Visible-band radiance ~ T^2, 1.0 at 10 kK (bolometric T^4 spans 10^4 and ACES
    // clipped every pixel above ~6500 K to white); floor keeps the coolest voids a dim ember.
    let radiance = max(pow(temperatureK / 10000.0, 2.0), 0.03);
    return vec3<f32>(r, g, b) * radiance;
}

fn loadC(coord: vec2<i32>, max_coord: vec2<i32>) -> vec4<f32> {
    let c = clamp(coord, vec2<i32>(0), max_coord);
    return textureLoad(dataTextureC, c, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let max_coord = vec2<i32>(res) - vec2<i32>(1);
    var uv = vec2<f32>(global_id.xy) / res;
    var p = uv * 2.0 - 1.0;
    p.x *= res.x / max(res.y, 1.0);

    let dist = length(p);
    let lodFactor = smoothstep(1.5, 2.5, dist);

    if (dist > 3.0) {
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 0.0));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        textureStore(dataTextureA, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        return;
    }

    let tempShift = u.zoom_params.x;
    let speed = mix(0.5, 2.0, u.zoom_params.y);
    let scale = mix(1.0, 4.0, u.zoom_params.z);
    let thermalIntensity = mix(0.5, 3.0, u.zoom_params.w);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioReactivity = 1.0 + mids * 0.3;
    let time = u.config.x * speed * audioReactivity;

    var mouse_pos = u.zoom_config.yz * 2.0 - 1.0;
    mouse_pos.x *= res.x / max(res.y, 1.0);
    let dist_to_mouse = length(p - mouse_pos);
    let mouse_influence = exp(-dist_to_mouse * 3.0) * select(0.0, 1.0, u.zoom_config.w > 0.5);

    var q_pos = p * scale + mouse_influence;
    let octaves = i32(mix(6.0, 3.0, lodFactor));

    var q = vec2<f32>(
        fbm(q_pos + vec2<f32>(0.0, time * 0.2), octaves),
        fbm(q_pos + vec2<f32>(1.0, 2.0) + time * 0.2, octaves)
    );
    var r = vec2<f32>(
        fbm(q_pos + 4.0 * q + vec2<f32>(1.7, 9.2) + time * 0.15, octaves),
        fbm(q_pos + 4.0 * q + vec2<f32>(8.3, 2.8) + time * 0.126, octaves)
    );
    var f = fbm(q_pos + 4.0 * r, octaves);

    // Idea 1 — filaments along |∇f|
    let f2 = fbm(q_pos + vec2<f32>(0.04, 0.03) + 4.0 * r, octaves);
    let gradMag = abs(f2 - f) / 0.05;
    let filament = smoothstep(0.12, 0.55, gradMag);

    let energy = clamp(f * f * f + 0.4 * f * f + 0.3 * length(q) + 0.2 * length(r.x), 0.0, 1.0);
    let audioHeatBoost = (bass - treble) * 0.15;
    // energy sits in ~0.3..1.0 (mean 0.6), so mapping it straight onto 1.2..12 kK put the
    // whole nebula above 8 kK (white); re-centre so the voids reach ember temperatures.
    var temperature = mix(1200.0, 12000.0, (energy - 0.42) * 1.7 + tempShift * 0.3 + audioHeatBoost);
    temperature = clamp(temperature, 800.0, 15000.0);

    // Idea 2 — warp-advected C heat along existing r
    let advectUV = clamp(uv - r * 0.035, vec2<f32>(0.0), vec2<f32>(1.0));
    let prevCoord = vec2<i32>(advectUV * res);
    let prev = loadC(prevCoord, max_coord);
    // ── Idea 3: Stefan-Boltzmann cooling wake ───────────────────────
    // dT/dt ∝ -T^4 → T' = T / (1 + 3 k T^3 dt)^(1/3). Hot plasma advected from C now
    // cools fast and cool plasma barely changes (HEAD's max() ratchet only ever heated).
    let tn = clamp(prev.a, 0.0, 1.0);
    let cooledT = tn / pow(1.0 + 0.35 * tn * tn * tn, 0.3333333) * 15000.0;
    temperature = mix(temperature, max(temperature, cooledT), 0.32);

    var thermalColor = blackbodyColor(temperature) * thermalIntensity;
    thermalColor = mix(thermalColor, prev.rgb, 0.18);
    thermalColor += blackbodyColor(clamp(temperature * 1.12, 800.0, 15000.0)) * filament * 0.55;

    // ── Idea 4: Beer-Lambert dust lanes ─────────────────────────────
    // Cool foreground dust (long warp vector q, low energy) absorbs the hotter
    // plasma behind it: transmittance exp(-tau * dust).
    let dust = smoothstep(0.55, 0.95, length(q)) * (1.0 - energy);
    thermalColor *= exp(-2.4 * dust);

    // ── Idea 5: hot-core halo from C heat ───────────────────────────
    // Energy-conserving: heat above 9000 K in four exact C taps is spread as a blue-white
    // halo, and the core it came from is bled by a matching fraction.
    var haloT = 0.0;
    for (var k = 0; k < 4; k = k + 1) {
        let o = vec2<i32>(select(-7, 7, (k & 1) == 1), select(-7, 7, (k & 2) == 2));
        haloT += max(loadC(coord + o, max_coord).a - 0.6, 0.0);
    }
    haloT *= 0.25;
    let coreExcess = clamp((temperature / 15000.0 - 0.6) * 4.0, 0.0, 1.0);
    thermalColor = thermalColor * (1.0 - 0.18 * coreExcess) + blackbodyColor(11000.0) * haloT * 1.6;

    if (u.zoom_config.w > 0.5) {
        let mouseDistUV = length(uv - u.zoom_config.yz);
        let mouseHeat = exp(-mouseDistUV * mouseDistUV * 400.0);
        thermalColor += blackbodyColor(15000.0) * mouseHeat * thermalIntensity;
    }

    let displayColor = toneMapACES(thermalColor);
    let alpha = clamp(0.28 + energy * 0.5 + filament * 0.22 + mids * 0.04, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(displayColor, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(clamp(energy, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(thermalColor, temperature / 15000.0));
}
