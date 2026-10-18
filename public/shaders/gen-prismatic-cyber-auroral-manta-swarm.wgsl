// ═══════════════════════════════════════════════════════════════════
//  Prismatic Cyber-Auroral Manta-Swarm
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-17
//  Ideas: mobuliform chordwise travelling-wave undulation of the pectoral wing disc; manta countershading with dorsal shoulder chevrons and unique ventral spot constellations; ventral gill-arch bioluminescence; ram-ventilation wake ribbons; school barrel-roll wave (a full roll about the swim axis passes manta to manta through the formation); aurora-lit dorsal dapple (the aurora volume's own density lights the disc in its palette)
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: .x = Scale (swarm cohesion), .y = Intensity (aurora), .z = Speed, .w = Detail

// PRNG
fn hash1(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

// 3D Simplex noise
fn snoise(p: vec3<f32>) -> f32 {
    let K1 = 0.333333333;
    let K2 = 0.166666667;
    let i = floor(p + (p.x + p.y + p.z) * K1);
    let d0 = p - i + (i.x + i.y + i.z) * K2;

    var e = step(vec3<f32>(0.0), d0 - d0.yzx);
    var i1 = e * (1.0 - e.zxy);
    var i2 = 1.0 - e.zxy * (1.0 - e);

    let d1 = d0 - (i1 - 1.0 * K2);
    let d2 = d0 - (i2 - 2.0 * K2);
    let d3 = d0 - (1.0 - 3.0 * K2);

    var h = max(0.6 - vec4<f32>(dot(d0, d0), dot(d1, d1), dot(d2, d2), dot(d3, d3)), vec4<f32>(0.0));
    var n = h * h * h * h * vec4<f32>(
        dot(d0, hash3(i + 0.0) - 0.5),
        dot(d1, hash3(i + i1) - 0.5),
        dot(d2, hash3(i + i2) - 0.5),
        dot(d3, hash3(i + 1.0) - 0.5)
    );
    return dot(n, vec4<f32>(52.0));
}

// Fractal Brownian Motion
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var pp = p;
    for (var i = 0; i < 4; i++) {
        f += amp * snoise(pp * freq);
        freq *= 2.0;
        amp *= 0.5;
        pp = pp * 1.1 + vec3<f32>(0.1, 0.2, 0.3);
    }
    return f;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Octave-controlled FBM for the aurora volume (Detail slider; 4 octaves == fbm above)
fn fbmOct(p: vec3<f32>, oct: i32) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var pp = p;
    for (var i = 0; i < oct; i++) {
        f += amp * snoise(pp * freq);
        freq *= 2.0;
        amp *= 0.5;
        pp = pp * 1.1 + vec3<f32>(0.1, 0.2, 0.3);
    }
    return f;
}

// Rotation matrices
fn rotX(a: f32) -> mat3x3<f32> {
    let c = cos(a); let s = sin(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotY(a: f32) -> mat3x3<f32> {
    let c = cos(a); let s = sin(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}
fn rotZ(a: f32) -> mat3x3<f32> {
    let c = cos(a); let s = sin(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// Idea 5: school barrel-roll wave. Every ~12 s a full roll about the swim
// axis passes through the formation one manta after another; returns the
// roll as (cos, sin) for manta fi.
fn schoolRoll(time: f32, fi: f32) -> vec2<f32> {
    let wave = fract(time * 0.085) * 8.0 - fi;
    let a = smoothstep(0.0, 1.0, clamp(wave, 0.0, 1.0)) * 6.2831853;
    return vec2<f32>(cos(a), sin(a));
}

// Smooth min/max
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Manta ray SDF
fn sdf_manta(p_in: vec3<f32>, time: f32, audio_react: f32, id: f32) -> f32 {
    var p = p_in;

    // Wing flapping animation based on time, position, and audio
    // Base rate times time, audio as a bounded phase kick (scaling absolute
    // time by audio made the flap jump on every beat).
    let flap_speed = 2.0 + hash1(id) * 1.5;
    let flap_kick = audio_react * 1.5;
    let flap_amp = 0.3 + audio_react * 0.2;

    // Flapping (spanwise wave out to the wingtips)
    let flap = sin(time * flap_speed + flap_kick - abs(p.x) * 2.0) * flap_amp * p.x * p.x;
    p.y -= flap;

    // Idea 1: mobuliform chordwise travelling wave - the pectoral disc ripples from
    // leading edge to trailing edge with a phase lag, amplitude growing toward the tips.
    let chord_phase = (time * flap_speed + flap_kick) * 1.3 - p.z * 3.2 - abs(p.x) * 1.1;
    let tip_w = smoothstep(0.4, 2.3, abs(p.x));
    p.y -= sin(chord_phase) * (0.06 + audio_react * 0.05) * tip_w;

    // Body (flattened ellipsoid)
    let body_r = vec3<f32>(0.8, 0.15, 1.2);
    let body_d = length(p / body_r) - 1.0;
    var d = body_d * min(min(body_r.x, body_r.y), body_r.z);

    // Wings
    let wing_w = 2.5;
    let wing_l = 1.0;
    let wing_t = 0.05 * (1.0 - min(abs(p.x) / wing_w, 1.0)); // Taper towards tips

    // Swept back wing shape
    var wp = p;
    wp.z -= abs(wp.x) * 0.5; // Sweep back (local +z is aft)

    // Wing bounding box/shape
    let d_x = abs(wp.x) - wing_w;
    let d_y = abs(wp.y) - wing_t;
    let d_z = abs(wp.z) - wing_l * (1.0 - min(abs(wp.x) / wing_w, 1.0));

    let wing_dist = length(max(vec3<f32>(d_x, d_y, d_z), vec3<f32>(0.0))) + min(max(d_x, max(d_y, d_z)), 0.0);

    // Tail
    let tail_l = 2.0;
    let tail_t = 0.02;
    var tp = p;
    tp.z -= 1.0; // Start at back of body
    // Tail whipping
    tp.x += sin((time * flap_speed + flap_kick) * 1.5 + tp.z * 2.0) * 0.1 * tp.z;

    // Tail cylinder
    let d_tx = abs(tp.x) - tail_t;
    let d_tz = max(0.0, tp.z) - tail_l; // only go backwards
    var tail_dist = length(vec2<f32>(tp.x, tp.y)) - tail_t;
    tail_dist = max(tail_dist, -tp.z); // Start at z=0
    tail_dist = max(tail_dist, tp.z - tail_l); // End at tail_l

    // Smooth union of parts
    d = smin(d, wing_dist, 0.2);
    d = smin(d, tail_dist, 0.1);

    return d;
}

// Swarm SDF
fn map(p_in: vec3<f32>, time: f32, audio_react: f32, mouse_pos: vec3<f32>, swarm_cohesion: f32) -> f32 {
    var min_d = 1000.0;

    // Render a few manta rays
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);

        // Base orbit
        let orbit_r = 4.0 + hash1(fi) * 2.0;
        let orbit_s = 0.2 + hash1(fi + 10.0) * 0.2;

        var base_pos = vec3<f32>(
            cos(time * orbit_s + fi * 2.0) * orbit_r,
            sin(time * orbit_s * 1.3 + fi * 3.0) * orbit_r * 0.5,
            sin(time * orbit_s + fi * 2.0) * orbit_r
        );

        // Mouse gravity influence
        let m_dist = length(mouse_pos - base_pos);
        let held_gain = 1.0 + select(0.0, 1.5, u.zoom_config.w > 0.5);
        let m_pull = 1.0 / (m_dist * m_dist + 1.0) * 10.0 * held_gain;
        let pull_dir = normalize(mouse_pos - base_pos);

        // Cohesion pull (towards center of swarm)
        let center_pull = -base_pos * swarm_cohesion * 0.1;

        // Final position
        var pos = base_pos + pull_dir * m_pull * 0.5 + center_pull;

        // Calculate orientation (facing direction of movement)
        // Approximate velocity by looking at next frame position
        let t_next = time + 0.1;
        var next_pos = vec3<f32>(
            cos(t_next * orbit_s + fi * 2.0) * orbit_r,
            sin(t_next * orbit_s * 1.3 + fi * 3.0) * orbit_r * 0.5,
            sin(t_next * orbit_s + fi * 2.0) * orbit_r
        );
        let m_dist_next = length(mouse_pos - next_pos);
        let m_pull_next = 1.0 / (m_dist_next * m_dist_next + 1.0) * 10.0 * held_gain;
        let pull_dir_next = normalize(mouse_pos - next_pos);
        next_pos = next_pos + pull_dir_next * m_pull_next * 0.5 - next_pos * swarm_cohesion * 0.1;

        // Local +z is aft (tail, wake), so the frame's z axis points against travel
        let vel = normalize(pos - next_pos);

        // Create rotation matrix to align with velocity
        let up = vec3<f32>(0.0, 1.0, 0.0);
        let right0 = normalize(cross(up, vel));
        let up0 = cross(vel, right0);
        let roll = schoolRoll(time, fi);
        let right = right0 * roll.x + up0 * roll.y;
        let new_up = up0 * roll.x - right0 * roll.y;
        let rot = mat3x3<f32>(right, new_up, vel);

        // Transform point to manta local space
        var lp = (p_in - pos);
        // Multiply by inverse rotation (transpose for orthogonal matrix)
        let inv_rot = mat3x3<f32>(
            rot[0][0], rot[1][0], rot[2][0],
            rot[0][1], rot[1][1], rot[2][1],
            rot[0][2], rot[1][2], rot[2][2]
        );
        lp = inv_rot * lp;

        // Get distance
        let d = sdf_manta(lp, time, audio_react, fi);
        min_d = smin(min_d, d, 0.5); // Merge them softly if they get close
    }

    return min_d;
}

// Local frame of the nearest manta at p (mirrors map's pose); returns (local p.xyz, manta id)
fn nearestMantaLocal(p_in: vec3<f32>, time: f32, audio_react: f32, mouse_pos: vec3<f32>, swarm_cohesion: f32) -> vec4<f32> {
    var best_d = 1000.0;
    var best = vec4<f32>(0.0);
    let held_gain = 1.0 + select(0.0, 1.5, u.zoom_config.w > 0.5);
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let orbit_r = 4.0 + hash1(fi) * 2.0;
        let orbit_s = 0.2 + hash1(fi + 10.0) * 0.2;
        let base_pos = vec3<f32>(
            cos(time * orbit_s + fi * 2.0) * orbit_r,
            sin(time * orbit_s * 1.3 + fi * 3.0) * orbit_r * 0.5,
            sin(time * orbit_s + fi * 2.0) * orbit_r
        );
        let m_dist = length(mouse_pos - base_pos);
        let m_pull = 1.0 / (m_dist * m_dist + 1.0) * 10.0 * held_gain;
        let pos = base_pos + normalize(mouse_pos - base_pos) * m_pull * 0.5 - base_pos * swarm_cohesion * 0.1;
        let t_next = time + 0.1;
        var next_pos = vec3<f32>(
            cos(t_next * orbit_s + fi * 2.0) * orbit_r,
            sin(t_next * orbit_s * 1.3 + fi * 3.0) * orbit_r * 0.5,
            sin(t_next * orbit_s + fi * 2.0) * orbit_r
        );
        let m_dist_next = length(mouse_pos - next_pos);
        let m_pull_next = 1.0 / (m_dist_next * m_dist_next + 1.0) * 10.0 * held_gain;
        next_pos = next_pos + normalize(mouse_pos - next_pos) * m_pull_next * 0.5 - next_pos * swarm_cohesion * 0.1;
        let vel = normalize(pos - next_pos);
        let right0 = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), vel));
        let up0 = cross(vel, right0);
        let roll = schoolRoll(time, fi);
        let right = right0 * roll.x + up0 * roll.y;
        let new_up = up0 * roll.x - right0 * roll.y;
        let d_vec = p_in - pos;
        let lp = vec3<f32>(dot(right, d_vec), dot(new_up, d_vec), dot(vel, d_vec));
        let d = sdf_manta(lp, time, audio_react, fi);
        if (d < best_d) {
            best_d = d;
            best = vec4<f32>(lp, fi);
        }
    }
    return best;
}

// Idea 2: manta countershading - near-black dorsal disc with pale shoulder chevrons,
// pale ventral surface carrying a per-individual constellation of dark spots.
fn mantaSkin(lp: vec3<f32>, n_local: vec3<f32>, id: f32, detail: f32) -> vec4<f32> {
    let dorsal = smoothstep(-0.25, 0.25, n_local.y);
    // Dorsal shoulder chevrons: two pale bands sweeping back from the head toward the wing roots
    let ax = abs(lp.x);
    let chevron_line = abs((0.1 - lp.z) - (0.9 - ax * 0.75));
    let chevron = smoothstep(0.28, 0.08, chevron_line) * smoothstep(0.2, 0.5, ax) * smoothstep(1.6, 1.0, ax);
    // Ventral spot constellation seeded by manta id (between the gill slits, on the belly)
    let spot_scale = 2.5 + detail * 3.0;
    let sp = vec3<f32>(lp.x, 0.0, lp.z) * spot_scale + vec3<f32>(id * 17.3, 0.0, id * 5.1);
    let cell = floor(sp);
    let fr = fract(sp) - 0.5;
    let rnd = hash3(cell + vec3<f32>(id));
    let spot_on = step(0.62, rnd.z);
    let spot = spot_on * smoothstep(0.22, 0.1, length(fr.xz - (rnd.xy - 0.5) * 0.5));
    let belly = smoothstep(1.4, 0.3, length(lp.xz * vec2<f32>(0.9, 0.7)));
    let dorsal_col = mix(vec3<f32>(0.05, 0.1, 0.2), vec3<f32>(0.55, 0.75, 0.85), chevron * 0.6);
    let ventral_col = mix(vec3<f32>(0.35, 0.42, 0.5), vec3<f32>(0.03, 0.04, 0.08), spot * belly);
    let col = mix(ventral_col, dorsal_col, dorsal);
    return vec4<f32>(col, chevron * dorsal);
}

// Idea 3: ventral gill arches glowing along the feeding channels.
fn mantaGillArches(lp: vec3<f32>, n_local: vec3<f32>, detail: f32) -> f32 {
    let ventral = smoothstep(0.0, 0.55, -n_local.y);
    let channel = (1.0 - smoothstep(0.12, 0.85, abs(lp.x))) * (1.0 - smoothstep(0.15, 0.9, abs(lp.z + 0.15)));
    let arch = pow(max(0.5 + 0.5 * sin((lp.x * 8.0 + lp.z * 3.0) * (1.0 + detail * 0.6)), 0.0), 3.0);
    return ventral * channel * arch;
}

// Idea 4: luminous wake sheets shed from the trailing manta disc.
fn mantaWakeRibbon(lp: vec3<f32>, time: f32, audio_react: f32, detail: f32) -> f32 {
    let trail = smoothstep(0.35, 2.6, lp.z);
    let sheet = exp(-abs(lp.x) * (2.0 + detail * 2.0)) * exp(-abs(lp.y) * 8.0);
    let roll = pow(max(0.5 + 0.5 * sin(lp.z * 6.0 - (time * 3.5 + audio_react * 1.5) + lp.x * 2.0), 0.0), 2.0);
    return trail * sheet * roll;
}

// Calculate normal
fn calcNormal(p: vec3<f32>, time: f32, audio_react: f32, mouse_pos: vec3<f32>, swarm_cohesion: f32) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audio_react, mouse_pos, swarm_cohesion) - map(p - e.xyy, time, audio_react, mouse_pos, swarm_cohesion),
        map(p + e.yxy, time, audio_react, mouse_pos, swarm_cohesion) - map(p - e.yxy, time, audio_react, mouse_pos, swarm_cohesion),
        map(p + e.yyx, time, audio_react, mouse_pos, swarm_cohesion) - map(p - e.yyx, time, audio_react, mouse_pos, swarm_cohesion)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) { return; }

    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * res) / res.y;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Parameters mapped from UI sliders
    let swarm_cohesion = u.zoom_params.x;          // Scale
    let aurora_intensity = u.zoom_params.y;        // Intensity
    let speed = u.zoom_params.z;                   // Speed (default 0.3 -> original 0.5 time scale)
    let detail = u.zoom_params.w;                  // Detail (default 0.5 -> original 4 aurora octaves)
    let time = u.config.x * (0.2 + speed);
    let audio_react = clamp(bass * 0.8 + mids * 0.3, 0.0, 1.0) * (0.4 + speed);
    let aurora_oct = clamp(2 + i32(detail * 4.0 + 0.001), 2, 6);

    // Mouse coords
    let mouse_ndc = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let uv01 = vec2<f32>(f32(id.x), f32(id.y)) / res;

    // Click ripples: bioluminescent breach rings in the aurora plasma
    var breach = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let rp = u.ripples[ri];
        let age = u.config.x - rp.z;
        if (age < 0.0 || age > 3.0) { continue; }
        let rdist = length((uv01 - rp.xy) * vec2<f32>(res.x / res.y, 1.0));
        let rr = (rdist - age * 0.35) * 18.0;
        breach += exp(-rr * rr) * (1.0 - age / 3.0);
    }
    breach = clamp(breach, 0.0, 1.5);

    // Camera
    let ro = vec3<f32>(0.0, 0.0, -10.0);
    // Pixel rows grow downward; flip so world +y is screen-up
    var rd = normalize(vec3<f32>(uv.x, -uv.y, 1.0));

    // Slight camera drift
    let cam_rot = rotY(sin(time * 0.1) * 0.2) * rotX(cos(time * 0.15) * 0.1);
    rd = cam_rot * rd;

    // 3D Mouse position (projected into scene)
    let mouse_pos = vec3<f32>(mouse_ndc.x * 8.0, -mouse_ndc.y * 8.0, 0.0);

    // Background / Aurora Volumetrics
    var col = vec3<f32>(0.0);
    var transmittance = 1.0;
    var t_vol = 0.0;

    // Raymarch Volumetric Aurora
    for (var i = 0; i < 40; i++) {
        let p = ro + rd * t_vol;

        // Aurora density based on noise and height
        var density = fbmOct(p * 0.2 + vec3<f32>(time * 0.1, 0.0, time * 0.2), aurora_oct) * 2.0 - 1.0;

        // Modulate with audio
        density += fbm(p * 0.5 - vec3<f32>(0.0, time * 0.1 + audio_react * 0.8, 0.0)) * audio_react * 0.5;
        density += breach * 0.35;

        // Confine to a band
        density *= smoothstep(6.0, 2.0, abs(p.y));
        density = max(0.0, density);

        if (density > 0.0) {
            // Color mapping based on height and density
            let aurora_col = mix(
                vec3<f32>(0.1, 0.0, 0.8), // Deep neon indigo
                vec3<f32>(0.0, 0.8, 0.6), // Brilliant cyan
                smoothstep(-2.0, 2.0, p.y + density)
            );

            // Add magenta spikes on treble
            let spike = pow(max(0.0, sin(p.x * 2.0 + time) * cos(p.z * 2.0 - time)), 4.0) * treble * (0.5 + speed);
            let final_aurora = mix(aurora_col, vec3<f32>(1.0, 0.0, 0.5), clamp(spike, 0.0, 1.0));

            let absorption = density * 0.1 * aurora_intensity;
            let emission = final_aurora * density * 0.5 * aurora_intensity;

            col += emission * transmittance;
            transmittance *= exp(-absorption);
        }

        if (transmittance < 0.01) { break; }

        t_vol += 0.5; // Step size
    }

    // Raymarch Manta Rays (Solid geometry)
    var t = 0.0;
    var d = 0.0;
    var hit = false;
    var p = ro;

    for (var i = 0; i < 64; i++) {
        p = ro + rd * t;
        d = map(p, time, audio_react, mouse_pos, swarm_cohesion);
        if (d < 0.01) {
            hit = true;
            break;
        }
        t += d;
        if (t > 20.0) { break; }
    }

    var coverage = 0.0;
    var depth = 0.0;
    if (hit && transmittance > 0.1) { // Only render if not fully obscured by thick aurora
        let n = calcNormal(p, time, audio_react, mouse_pos, swarm_cohesion);

        // Lighting
        let l_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(0.0, dot(n, l_dir));
        let fresnel = pow(1.0 - max(0.0, dot(n, -rd)), 3.0);

        // Subsurface scattering / glowing edge effect
        let thickness = map(p - n * 0.1, time, audio_react, mouse_pos, swarm_cohesion);
        let sss = smoothstep(0.0, 0.1, thickness);

        // Countershaded skin in the nearest manta's local frame
        let local = nearestMantaLocal(p, time, audio_react, mouse_pos, swarm_cohesion);
        let e = vec2<f32>(0.01, 0.0);
        let n_local = normalize(vec3<f32>(
            sdf_manta(local.xyz + e.xyy, time, audio_react, local.w) - sdf_manta(local.xyz - e.xyy, time, audio_react, local.w),
            sdf_manta(local.xyz + e.yxy, time, audio_react, local.w) - sdf_manta(local.xyz - e.yxy, time, audio_react, local.w),
            sdf_manta(local.xyz + e.yyx, time, audio_react, local.w) - sdf_manta(local.xyz - e.yyx, time, audio_react, local.w)
        ));
        let skin = mantaSkin(local.xyz, n_local, local.w, detail);
        let gills = mantaGillArches(local.xyz, n_local, detail);
        let wake = mantaWakeRibbon(local.xyz, time, audio_react, detail);

        // Manta Color (glass-like, refractive, glowing edges)
        var manta_col = skin.rgb * (0.35 + diff * 0.65); // Countershaded dark glass

        // Add neon glow to edges (fresnel + sss)
        let edge_glow = vec3<f32>(0.0, 0.8, 1.0) * fresnel * 2.0;

        // Add audio reactive chromatic bloom
        let bloom = vec3<f32>(1.0, 0.2, 0.8) * sss * audio_react;

        // Chevrons glow faintly with mids
        let chevron_glow = vec3<f32>(0.4, 0.9, 1.0) * skin.a * (0.15 + mids * 0.5);
        let gill_glow = vec3<f32>(0.25, 1.0, 0.75) * gills * (0.25 + mids * 0.55);
        let wake_glow = vec3<f32>(0.3, 0.8, 1.0) * wake * (0.25 + bass * 0.45);

        // Idea 6: aurora-lit dorsal dapple - the same drifting aurora density
        // field, sampled at the hit, lights the upper disc in the aurora's own
        // indigo->cyan palette, so each manta carries the sky it swims through.
        let sky_d = max(0.0, fbm(p * 0.2 + vec3<f32>(time * 0.1, 0.0, time * 0.2)) * 2.0 - 0.6);
        let sky_col = mix(vec3<f32>(0.1, 0.0, 0.8), vec3<f32>(0.0, 0.8, 0.6), smoothstep(-2.0, 2.0, p.y + sky_d));
        let dapple = sky_col * sky_d * smoothstep(-0.1, 0.6, n_local.y) * (0.2 + diff * 0.5) * aurora_intensity * 2.0;

        manta_col += edge_glow + bloom + chevron_glow + gill_glow + wake_glow + dapple;

        // Blend solid object with volumetric background based on transmittance
        // The solid object occludes what's behind it, but is dimmed by what's in front
        col = mix(col, manta_col * transmittance, transmittance);
        coverage = transmittance;
        depth = clamp(1.0 - t / 20.0, 0.0, 1.0);
    }

    col += vec3<f32>(0.3, 0.9, 1.0) * breach * 0.25;

    // ACES tone mapping and gamma
    col = acesToneMap(col * (1.1 + bass * 0.15));
    col = pow(col, vec3<f32>(1.0 / 2.2));

    // Alpha: manta coverage over aurora optical depth, plus breach ring glow
    let alpha = clamp(max(coverage, 1.0 - transmittance) + breach * 0.2, 0.0, 1.0);
    let finalColor = vec4<f32>(col, alpha);

    textureStore(writeTexture, id.xy, finalColor);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, finalColor);
}
