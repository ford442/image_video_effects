// ═══════════════════════════════════════════════════════════════════
//  Ethereal Chrono-Flora Loom
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: warp-thread helices along the loom axis; weft shuttle bead at flow speed; chrono-petal clock face; temporal gear-tooth rims
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: .x = Density, .y = Flow Speed, .z = Glow Intensity, .w = Color Shift

// --- CONSTANTS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

// --- UTILS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn shuttlePos(flowTime: f32) -> vec3<f32> {
    let ang = flowTime * 1.4;
    return vec3<f32>(cos(ang) * 0.9, sin(ang) * 0.9, sin(flowTime * 0.35) * 2.2);
}

// --- SDF ---
// Returns (distance, material). 1 stem/orb, 2 warp thread, 3 weft shuttle.
fn map(p: vec3<f32>) -> vec2<f32> {
    var p_mod = p;

    let audioBass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let flow = max(u.zoom_params.y, 0.0);
    let t = u.config.x * flow * (1.0 + audioBass * 0.5);
    let density = clamp(u.zoom_params.x, 0.1, 5.0);

    // Twist based on height and time
    let pxy = p_mod.xy * rot2D(p_mod.z * 0.2 + t * 0.5);
    p_mod = vec3<f32>(pxy, p_mod.z);

    // Domain repetition for flora petals
    let angle = atan2(p_mod.y, p_mod.x);
    let radius = length(p_mod.xy);
    let petals = 6.0;
    let sector = 6.28318 / petals;
    let petalId = floor(angle / sector);
    let local_angle = (fract(angle / sector) - 0.5) * sector;

    let p_folded = vec3<f32>(cos(local_angle)*radius, sin(local_angle)*radius, p_mod.z);

    let fft_mod = mids * (0.5 + 0.5 * sin(petalId * 1.7));

    // Idea 2: Temporal gear-tooth rims
    let gearTeeth = abs(sin(p_mod.z * 10.0 - t * 2.0)) * 0.03 * density;
    
    // Flora structure (capsule/cylinder)
    let d_stem = length(p_folded.xy - vec2<f32>(0.5, 0.0)) - (0.1 * density * (1.0 + fft_mod) + gearTeeth);

    // Central glowing orb
    let d_orb = length(p) - 1.0;

    // Idea 1 — warp threads: two helices running the length of the loom.
    let threadR = 0.03 * density;
    let helixA = vec2<f32>(cos(p_mod.z * 2.4 + t), sin(p_mod.z * 2.4 + t)) * 1.15;
    let helixB = vec2<f32>(cos(p_mod.z * 2.4 + t + 3.14159), sin(p_mod.z * 2.4 + t + 3.14159)) * 1.15;
    let d_warp = min(length(p_mod.xy - helixA), length(p_mod.xy - helixB)) - threadR;

    // Idea 1: Chrono-petal clock face
    let clockRadius = length(p_mod.xy);
    let clockAngle = atan2(p_mod.y, p_mod.x);
    let clockTicks = abs(sin(clockAngle * 6.0)) * 0.1;
    let d_clock = max(abs(clockRadius - 2.0) - 0.05, -clockTicks);

    var d = smin(d_stem, d_orb, 0.5);
    d = smin(d, d_warp, 0.22);
    d = smin(d, d_clock, 0.15);

    // Idea 2 — weft shuttle riding the twist at Flow Speed.
    let d_shuttle = length(p - shuttlePos(t)) - 0.07;

    var mat = 1.0;
    if (d_shuttle < d) {
        d = d_shuttle;
        mat = 3.0;
    } else if (d_clock < d_stem && d_clock < d_orb && d_clock < d_warp && d_clock < d_shuttle) {
        mat = 4.0;
    } else if (d_warp < d_stem && d_warp < d_orb) {
        mat = 2.0;
    }

    return vec2<f32>(d, mat);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p).x;
    let n = vec3<f32>(
        d - map(p - e.xyy).x,
        d - map(p - e.yxy).x,
        d - map(p - e.yyx).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse orbit. zoom_config.yz is 0–1, not pixels.
    if (u.zoom_config.w > 0.5) {
        let ang = (u.zoom_config.y - 0.5) * 3.14159;
        let spin = rot2D(ang);
        let pxy = spin * ro.xy;
        ro = vec3<f32>(pxy, ro.z);
        let rdxy = spin * rd.xy;
        rd = vec3<f32>(rdxy, rd.z);
    }

    let audioBass = plasmaBuffer[0].x;
    let flow = max(u.zoom_params.y, 0.0);
    let flowTime = u.config.x * flow * (1.0 + audioBass * 0.5);
    let shuttle = shuttlePos(flowTime);
    let glowAmt = u.zoom_params.z;

    var t = 0.0;
    var glow = 0.0;
    var weftGlow = 0.0;
    var hit = false;
    var steps_taken: i32 = 0;
    var mat = 1.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        let d = map(p);
        mat = d.y;

        glow += 0.01 / (0.01 + abs(d.x)) * glowAmt * (1.0 + audioBass * 0.5);

        let ang = atan2(p.y, p.x);
        let shuttleAng = atan2(shuttle.y, shuttle.x);
        var dang = ang - shuttleAng;
        dang = dang - 6.28318 * round(dang / 6.28318);
        let weftArc = exp(-abs(dang) * 7.0) * exp(-abs(length(p.xy) - 0.9) * 10.0) * exp(-abs(p.z - shuttle.z) * 1.4);
        weftGlow += weftArc * glowAmt * 0.015;

        if (abs(d.x) < SURF_DIST) {
            hit = true;
            steps_taken = i;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += d.x * 0.8;
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));

        let dif = clamp(dot(n, l), 0.0, 1.0);
        let amb = 0.1 + 0.9 * clamp(0.5 + 0.5 * n.y, 0.0, 1.0);

        let baseCol = palette(length(p) * 0.1 + u.zoom_params.w);
        col = baseCol * dif * amb;

        if (mat > 3.5) {
            col += vec3<f32>(0.5, 0.8, 1.0) * (0.8 + audioBass);
        } else if (mat > 2.5) {
            col += vec3<f32>(1.0, 0.92, 0.75) * (1.2 + audioBass);
        } else if (mat > 1.5) {
            col += palette(u.zoom_params.w + 0.35) * 0.45;
        }

        // Fake AO from step count
        col *= 1.0 - f32(steps_taken) / f32(MAX_STEPS);
    }

    // Add glow and the weft arc the shuttle is laying down
    col += palette(u.config.x * 0.1) * glow * 0.05;
    col += vec3<f32>(1.0, 0.86, 0.55) * weftGlow;

    let mapped = acesToneMap(col * 1.15);
    let alpha = clamp(select(0.04, 0.72, hit) + glow * 0.08 + weftGlow * 0.35, 0.0, 1.0);
    let depth = clamp(1.0 - t / MAX_DIST, 0.0, 1.0);
    textureStore(writeTexture, id.xy, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(mapped, alpha));
}
