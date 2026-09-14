// ═══════════════════════════════════════════════════════════════════
//  Neon-Plasma Biomechanical Hive
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: brood-cell comb — voronoi hive cells read as chitin-walled brood chambers, some wax-capped domes, others open with heartbeat-pulsing larval plasma; peristaltic hemolymph pumping — boluses travel along the strut tubes, bulging the tube SDF and pushing bright plasma through the neon veins
//  A packing: ACES display RGBA in A (feedback inverts ACES analytically to recover HDR trails)
// ═══════════════════════════════════════════════════════════════════
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config: vec4<f32>,       // x=time (s), y=rippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=time, yz=mouse uv (0-1 canvas, y=0 top), w=mouseDown (>0.5 pressed)
    zoom_params: vec4<f32>,  // x=Hive Breathing Speed, y=Neon Intensity, z=Spore Density, w=Magnetic Pull
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const HDR_CEIL: f32 = 6.0;     // feedback energy ceiling (speed never blows up)
const TRAIL_DECAY: f32 = 0.86; // velocity-advected trail persistence
const MAX_MOUSE_VEL: f32 = 8.0; // cursor pursuit velocity clamp (hive uv/s)

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let p = floor(x);
    var f = fract(x);
    var res = vec2<f32>(8.0, 8.0);
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = vec3<f32>(b) - f + hash3(p + b);
                let d = dot(r, r);
                if (d < res.x) {
                    res.y = res.x;
                    res.x = d;
                } else if (d < res.y) {
                    res.y = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(res.x), sqrt(res.y));
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        let v = voronoi(pos * freq);
        value += amp * v.x;
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return value;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Analytic inverse of acesToneMap (per channel quadratic root) so the ACES
// display RGBA stored in dataTextureA can be lifted back to HDR for trails.
fn acesInverse(y: vec3<f32>) -> vec3<f32> {
    let yc = clamp(y, vec3<f32>(0.0), vec3<f32>(0.98));
    let A = 2.43 * yc - vec3<f32>(2.51);
    let B = 0.59 * yc - vec3<f32>(0.03);
    let C = 0.14 * yc;
    let disc = sqrt(max(B * B - 4.0 * A * C, vec3<f32>(0.0)));
    return max((-B - disc) / (2.0 * A), vec3<f32>(0.0));
}

// Voronoi with nearest-cell identity (f1, f2, cell hash) for brood cells
fn voronoiCell(x: vec3<f32>) -> vec3<f32> {
    let p = floor(x);
    let f = fract(x);
    var f1 = 8.0;
    var f2 = 8.0;
    var id = 0.0;
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let h = hash3(p + b);
                let r = b - f + h;
                let d = dot(r, r);
                if (d < f1) {
                    f2 = f1;
                    f1 = d;
                    id = fract(h.x * 7.13 + h.y * 3.71 + h.z);
                } else if (d < f2) {
                    f2 = d;
                }
            }
        }
    }
    return vec3<f32>(sqrt(f1), sqrt(f2), id);
}

// ── IDEA 2 helper: peristaltic bolus profile along a strut axis ──
// A contraction wave squeezes hemolymph into a travelling bolus: sharp
// crest, long relaxed trough (raised-cosine to the 4th power).
fn peristalsis(axial: f32, time: f32, pump: f32) -> f32 {
    let w = 0.5 + 0.5 * sin(axial * TAU * 0.75 - time * pump);
    let w2 = w * w;
    return w2 * w2;
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn map(pos: vec3<f32>, mouse_pos: vec3<f32>, mouse_pull: f32, time: f32, pump: f32) -> vec2<f32> {
    var p = pos;

    // Cursor gravity well — force clamped so speed stays stable
    let pull_dist = length(p - mouse_pos);
    if (pull_dist > 0.1) {
        let pull_force = mouse_pull / (pull_dist * pull_dist);
        p -= normalize(mouse_pos - p) * clamp(pull_force, 0.0, 2.0);
    }

    let v = voronoi(p * 2.0);
    let displacement = (v.y - v.x) * 0.3;

    let q = fract(p * 0.5) - 0.5;
    let sphere = length(q) - 0.25 + displacement;

    // IDEA 2: struts are muscular tubes; the bolus bulges the tube wall as it
    // travels along each strut axis (axial coordinate = unwrapped world axis).
    let bx = peristalsis(p.x, time, pump);
    let by = peristalsis(p.y + 0.37, time, pump);
    let bz = peristalsis(p.z + 0.71, time, pump);
    let cyl_x = length(q.yz) - (0.1 + 0.03 * bx);
    let cyl_y = length(q.xz) - (0.1 + 0.03 * by);
    let cyl_z = length(q.xy) - (0.1 + 0.03 * bz);
    let cyl = min(min(cyl_x, cyl_y), cyl_z);
    // Bolus of the nearest strut (for vein shading at the hit point)
    var bolus = bx;
    if (cyl_y < cyl_x && cyl_y <= cyl_z) { bolus = by; }
    else if (cyl_z < cyl_x && cyl_z < cyl_y) { bolus = bz; }

    let d = smin(sphere, cyl, 0.2);
    // Tube proximity: bolus only shows where the surface is a strut
    let onTube = clamp(1.0 - (cyl - d) * 6.0, 0.0, 1.0);

    return vec2<f32>(d, bolus * onTube);
}

// Plasma-spore swarm: fast closed-form orbital flight (smooth sin,
// temporal-coherent — no hash strobing) + spring-damped pursuit of the
// cursor attractor with a clamped max offset (velocity clamp analog).
fn map_spores(p: vec3<f32>, time: f32, attract: vec3<f32>, chase_amt: f32) -> f32 {
    let cell = floor(p);
    let h = hash3(cell);
    let spd = 2.0 + h.z * 2.5; // per-agent flight speed 2.0–4.5 rad/s
    let offset = vec3<f32>(
        sin(time * spd + h.x * TAU),
        cos(time * (spd * 0.8) + h.y * TAU),
        sin(time * (spd * 0.6) + h.z * TAU)
    ) * 0.3;
    let chase = clamp(attract - p, vec3<f32>(-0.45), vec3<f32>(0.45)) * chase_amt;
    let q = fract(p) - 0.5 - offset - chase;
    return length(q) - 0.05;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let pixel = vec2<i32>(global_id.xy);
    let aspect = res / min(res.x, res.y);
    let uv = (vec2<f32>(global_id.xy) * 2.0 - res) / min(res.x, res.y);
    let time = u.config.x;

    // ── Live sliders (updatedParams contract, byte-exact) ─────────
    let breathing_speed = u.zoom_params.x;  // p1 0.1–5  — breathing rate AND hive flythrough speed
    let neon_intensity  = u.zoom_params.y;  // p2 0–10  — neon vein emission
    let spore_density   = u.zoom_params.z;  // p3 0–1   — spore swarm glow density
    let magnetic_pull   = u.zoom_params.w;  // p4 0–5   — cursor gravity-well strength

    // ── Audio: ONLY plasmaBuffer[0].xyz ───────────────────────────
    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    // Hemolymph pump rate: breathing speed, quickened by bass
    let pump = 1.5 + breathing_speed * 1.2 + bass * 0.5;

    // Mouse in hive uv space (zoom_config.yz already 0–1, y=0 top)
    let mouseS = (u.zoom_config.yz * 2.0 - vec2<f32>(1.0)) * aspect;
    let mouseDown = u.zoom_config.w > 0.5;

    // ── Persistent state (extraBuffer[133..137], single writer) ───
    // [133] bass envelope   [134] last kick time
    // [135..136] spring-smoothed cursor   [137] prev time (dt)
    var bassEnv = bass;
    var lastKick = time - 10.0;
    var smoothMouse = mouseS;
    var dt = 0.016;
    if (arrayLength(&extraBuffer) > 138u) {
        bassEnv = extraBuffer[133];
        lastKick = extraBuffer[134];
        smoothMouse = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        dt = clamp(time - extraBuffer[137], 0.001, 0.1);
        if (global_id.x == 0u && global_id.y == 0u) {
            // Fast attack / slow release bass envelope
            var be = bassEnv;
            be = mix(be, bass, select(0.06, 0.4, bass > be));
            // Kick = bass pokes above its own envelope (0.3 s retrigger gap)
            var lk = lastKick;
            if (bass > be * 1.25 + 0.12 && time - lk > 0.3) { lk = time; }
            // Frame-rate-independent spring chase of the cursor
            let sm = mix(smoothMouse, mouseS, vec2<f32>(1.0 - exp(-dt * 12.0)));
            extraBuffer[133] = be;
            extraBuffer[134] = lk;
            extraBuffer[135] = sm.x;
            extraBuffer[136] = sm.y;
            extraBuffer[137] = time;
        }
    }

    // ── Bass-kick shockwave (bounded exp decay) ───────────────────
    let kickAge = time - lastKick;
    let kickEnv = exp(-kickAge * 2.5);
    let kickRadius = kickAge * 3.5; // fast propagation front

    // ── Cursor pursuit: velocity + lead (whip-fast anticipation) ──
    // Spring-smoothed cursor lags the real cursor ⇒ delta/dt ≈ velocity.
    var mVel = (mouseS - smoothMouse) / dt;
    mVel *= min(1.0, MAX_MOUSE_VEL / max(length(mVel), 0.001)); // velocity clamp
    let lead = clamp(mVel * 0.12, vec2<f32>(-0.6), vec2<f32>(0.6));
    let chaseS = mix(mouseS, smoothMouse, 0.35) + lead;

    // ── Click shockwaves (guarded ripple loop) ────────────────────
    var shockVec = vec2<f32>(0.0);
    var shockFlash = 0.0;
    let nRip = min(u32(u.config.y), 50u);
    for (var i = 0u; i < nRip; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age > 0.0 && age < 3.0) {
            let rc = (rp.xy * 2.0 - vec2<f32>(1.0)) * aspect;
            let dvec = uv - rc;
            let dist = length(dvec);
            let ring = exp(-pow((dist - age * 2.8) * 7.0, 2.0)) * exp(-age * 2.0);
            shockVec += (dvec / max(dist, 0.05)) * ring;
            shockFlash += ring;
        }
    }
    // Bass-kick shockwave ring from screen center
    let kDist = length(uv);
    let kRing = exp(-pow((kDist - kickRadius) * 6.0, 2.0)) * kickEnv;
    shockVec += (uv / max(kDist, 0.05)) * kRing;
    shockFlash += kRing;
    shockFlash = min(shockFlash, 2.0); // bounded flash energy

    // ── Camera: fast flythrough (speed scales with p1) + shock whip ─
    var ro = vec3<f32>(
        time * (0.6 + breathing_speed * 0.5),
        sin(time * 0.7) * 0.4,
        time * (0.25 + breathing_speed * 0.2)
    );
    ro += vec3<f32>(shockVec * 0.5, 0.0); // shockwave whips the view
    let rd = normalize(vec3<f32>(uv + shockVec * 0.25, 1.0));

    // Cursor gravity well sits in front of the camera at the pursuit point
    let mouse_pos = ro + normalize(vec3<f32>(chaseS, 1.2)) * (3.5 + magnetic_pull * 0.5);
    let pull = magnetic_pull * 0.8 * select(1.0, 1.6, mouseDown);

    // ── Chromatic aberration raymarch (3 passes, bass/kick widens) ──
    var col = vec3<f32>(0.0);
    var hitT = 20.0;
    let caScale = 1.0 + bass * 0.6 + kickEnv * 1.5;
    let ca_offsets = array<vec3<f32>, 3>(
        vec3<f32>(0.005, 0.0, 0.0) * caScale,
        vec3<f32>(0.0, 0.005, 0.0) * caScale,
        vec3<f32>(0.0, 0.0, 0.005) * caScale
    );

    for (var c = 0; c < 3; c++) {
        var t = 0.0;
        var p = ro;
        var glow = 0.0;
        let rd_offset = normalize(rd + ca_offsets[c]);

        for (var i = 0; i < 64; i++) {
            p = ro + rd_offset * t;
            let p_breathe = p * (1.0 + sin(time * breathing_speed) * 0.05);
            let d = map(p_breathe, mouse_pos, pull, time, pump).x;

            let spore_d = map_spores(p, time, mouse_pos, 0.35 + select(0.0, 0.45, mouseDown));
            glow += 0.05 / (0.01 + abs(spore_d)) * spore_density * (1.0 + bass * 0.5 + kickEnv);

            if (d < 0.001) {
                break;
            }
            if (t > 20.0) {
                break;
            }
            t += min(d, spore_d) * 0.7;
        }

        if (t < 20.0) {
            if (c == 1) { hitT = t; }
            let vein_noise = fbm(p * 5.0 - time * (1.0 + breathing_speed));
            // IDEA 2: bolus pushes plasma through the veins of its tube
            let bolus = map(p, mouse_pos, pull, time, pump).y;
            let vein_glow = pow(vein_noise, 3.0) * neon_intensity * (1.0 + bass * 0.5 + mids * 0.3) * (0.6 + bolus * 1.6);

            let eps = vec2<f32>(0.001, 0.0);
            let n = normalize(vec3<f32>(
                map(p + eps.xyy, mouse_pos, pull, time, pump).x - map(p - eps.xyy, mouse_pos, pull, time, pump).x,
                map(p + eps.yxy, mouse_pos, pull, time, pump).x - map(p - eps.yxy, mouse_pos, pull, time, pump).x,
                map(p + eps.yyx, mouse_pos, pull, time, pump).x - map(p - eps.yyx, mouse_pos, pull, time, pump).x
            ));

            let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
            let diff = max(dot(n, light_dir), 0.0);
            let base_color = vec3<f32>(0.1, 0.15, 0.2); // Gunmetal

            // Audio reactive neon colors
            let audio_color = vec3<f32>(bass, mids, treble);
            var neon_color = vec3<f32>(0.0, 1.0, 1.0); // Cyan
            neon_color = mix(neon_color, vec3<f32>(1.0, 0.0, 1.0), clamp(bass * 0.8, 0.0, 1.0)); // Shift to magenta on bass
            if (length(audio_color) > 0.1) {
                 neon_color = mix(neon_color, audio_color, 0.5);
            }
            // Shockwave fronts flash the veins white-hot
            neon_color = mix(neon_color, vec3<f32>(1.0), clamp(shockFlash * 0.5, 0.0, 0.7));

            // ── IDEA 1: brood-cell comb ──
            // Hive voronoi cells are brood chambers: thin chitin walls where
            // f2 − f1 → 0; ~55% wax-capped (domed, amber-metal sheen), the rest
            // open with a larva whose plasma glow pulses on its own heartbeat.
            let bc = voronoiCell(p * 2.0);
            let wall = 1.0 - smoothstep(0.0, 0.07, bc.y - bc.x);
            // Cursor gravity well (held) uncaps nearby brood → more larvae visible
            let wellNear = exp(-length(p - mouse_pos) * 0.9) * select(0.0, 0.35, mouseDown);
            let capped = step(0.45 + wellNear, bc.z);
            let dome = (1.0 - clamp(bc.x * 1.6, 0.0, 1.0));
            let capShade = capped * dome * dome * (0.35 + diff * 0.9);
            let heartbeat = pow(0.5 + 0.5 * sin(time * (2.2 + breathing_speed * 0.8) + bc.z * TAU), 6.0);
            let larva = (1.0 - capped) * exp(-bc.x * bc.x * 9.0) * (0.25 + heartbeat * (0.9 + bass * 0.5));
            let broodCol = vec3<f32>(0.55, 0.36, 0.10) * capShade
                         + vec3<f32>(0.9, 0.35, 1.0) * larva * (0.15 + neon_intensity * 0.12)
                         + neon_color * wall * 0.12 * (1.0 + treble * 0.5);

            let c_val = base_color * diff + neon_color * vein_glow + broodCol;
            if (c == 0) { col.r = c_val.r; }
            else if (c == 1) { col.g = c_val.g; }
            else { col.b = c_val.b; }
        }
        if (c == 0) { col.r += glow; }
        else if (c == 1) { col.g += glow; }
        else { col.b += glow; }
    }

    col = max(col, vec3<f32>(0.0));

    // ── Velocity-advected HDR feedback trails ─────────────────────
    // Fetch upstream along the shockwave/velocity direction (clamped
    // fetch, textureLoad only); decaying history streaks fast motion.
    let advVec = shockVec * 0.10 + vec2<f32>(0.003 + breathing_speed * 0.002, 0.0);
    let advPx = clamp(
        vec2<i32>(vec2<f32>(pixel) - advVec * res),
        vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)
    );
    // A holds ACES display RGBA: undo exposure + ACES to recover HDR history
    let prev = min(acesInverse(textureLoad(dataTextureC, advPx, 0).rgb) / (0.9 + mids * 0.2), vec3<f32>(HDR_CEIL));
    var hdr = min(col, vec3<f32>(8.0)) * 0.85 + prev * TRAIL_DECAY * 0.55;
    hdr = min(hdr, vec3<f32>(HDR_CEIL)); // bounded feedback energy

    // ── Semantic alpha: hive emission intensity ───────────────────
    let alpha = clamp(luma(hdr) * 0.6 + shockFlash * 0.25, 0.04, 0.95);

    // ── Real generated depth: raymarched hive hit distance ────────
    let depthVal = clamp(hitT / 20.0, 0.0, 1.0);

    // ACES display RGBA → screen and A (feedback reads it back via acesInverse)
    let ldr = acesToneMap(hdr * (0.9 + mids * 0.2));
    let finalColor = vec4<f32>(ldr, alpha);
    textureStore(writeTexture, pixel, finalColor);
    textureStore(dataTextureA, pixel, finalColor);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
