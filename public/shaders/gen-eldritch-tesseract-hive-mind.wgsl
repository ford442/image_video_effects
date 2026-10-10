// ═══════════════════════════════════════════════════════════════════
//  Eldritch Tesseract-Hive Mind
//  Category: generative
//  Features: 4d-tesseract-raymarch, thin-film-iridescence, voxel-tearing,
//            sentinel-swarm, hdr-feedback-trails, speed-streaks,
//            audio-transient-burst, audio-color-temperature, mouse-driven,
//            audio-reactive, aces-tone-map, semantic-alpha, generated-depth,
//            fast-motion, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: W-cell hive lattice along unused W; sentinel pheromone lanes on radial
//         spokes. 2nd pass: 4D hypercube wire glow (slice edges from the 2-faces,
//         sparks where the 32 edges pierce the slice); W-depth film phase (the
//         rotated W of each hit point shifts the thin-film hue); sentinels orbit
//         the projected centres of the 8 cubic cells + hive cell
//  A packing: raw HDR peak-hold trail RGB (steady state = current frame) +
//             depth (near = 1) in A.a, except A(0,0).a = fract(time) (trail dt);
//             ACES on writeTexture only. No extraBuffer state.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// --- CONSTANTS & HELPERS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;
const HDR_CLAMP: f32 = 6.0; // feedback history energy ceiling (stability at speed)
const HIVE_W: f32 = 2.15;   // W offset of the neighbouring hive cell
const HIVE_HALF: f32 = 0.85;

// 4D Rotation matrix helper (any 2-plane)
fn rot4D(theta: f32) -> mat2x2<f32> {
    let c = cos(theta);
    let s = sin(theta);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 3D Value Noise for "boolean carving" (temporally coherent — no strobing)
fn vnoise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    let res = mix(
        mix(mix(hash33(p).x, hash33(p + vec3<f32>(1.0, 0.0, 0.0)).x, f2.x),
            mix(hash33(p + vec3<f32>(0.0, 1.0, 0.0)).x, hash33(p + vec3<f32>(1.0, 1.0, 0.0)).x, f2.x), f2.y),
        mix(mix(hash33(p + vec3<f32>(0.0, 0.0, 1.0)).x, hash33(p + vec3<f32>(1.0, 0.0, 1.0)).x, f2.x),
            mix(hash33(p + vec3<f32>(0.0, 1.0, 1.0)).x, hash33(p + vec3<f32>(1.0, 1.0, 1.0)).x, f2.x), f2.y), f2.z
    );
    return res;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Exact 4D rounded-box SDF (interior distance is real, so carving can use it)
fn sdBox4(q4: vec4<f32>, h: f32, r: f32) -> f32 {
    let q = abs(q4) - vec4<f32>(h);
    return length(max(q, vec4<f32>(0.0))) + min(max(max(q.x, q.y), max(q.z, q.w)), 0.0) - r;
}

fn sdBox3(q3: vec3<f32>, h: vec3<f32>) -> f32 {
    let q = abs(q3) - h;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// World 3D slice point -> tesseract-frame 4D point (dual-plane tumble)
fn tessP4(p: vec3<f32>, time: f32) -> vec4<f32> {
    let w_offset = (u.zoom_config.z - 0.5) * 2.0; // Mouse Y drives 4th dimension
    var p4 = vec4<f32>(p, w_offset);
    let rotation_speed = u.zoom_params.x;
    // Primary x-z plane
    let r1 = rot4D(time * (0.25 + rotation_speed * 1.5));
    let x_new = r1[0][0]*p4.x + r1[0][1]*p4.z;
    let z_new = r1[1][0]*p4.x + r1[1][1]*p4.z;
    p4.x = x_new;
    p4.z = z_new;
    // Secondary y-w plane tumble — the hypercube visibly unfolds through itself
    let r2 = rot4D(time * (0.31 + rotation_speed * 0.9) + 1.3);
    let y_new = r2[0][0]*p4.y + r2[0][1]*p4.w;
    let w_new = r2[1][0]*p4.y + r2[1][1]*p4.w;
    p4.y = y_new;
    p4.w = w_new;
    return p4;
}

// Inverse of tessP4: tesseract-frame point -> world (xyz, w)
fn tessInv(o: vec4<f32>, time: f32) -> vec4<f32> {
    let rotation_speed = u.zoom_params.x;
    let a1 = time * (0.25 + rotation_speed * 1.5);
    let a2 = time * (0.31 + rotation_speed * 0.9) + 1.3;
    let c1 = cos(a1); let s1 = sin(a1);
    let c2 = cos(a2); let s2 = sin(a2);
    let y = c2 * o.y + s2 * o.w;
    let w = -s2 * o.y + c2 * o.w;
    let x = c1 * o.x + s1 * o.z;
    let z = -s1 * o.x + c1 * o.z;
    return vec4<f32>(x, y, z, w);
}

// Vein field: tubes along the 0.5 iso-surface of a drifting value noise
fn veinField(p: vec3<f32>, time: f32) -> f32 {
    return abs(vnoise3(p * vec3<f32>(2.0) + vec3<f32>(time * 0.6)) - 0.5) * 0.35 - 0.022;
}

// Map function evaluating the 4D Tesseract SDF
fn map(p: vec3<f32>, time: f32, bass: f32) -> vec2<f32> {
    let p4 = tessP4(p, time);

    // Core tesseract SDF evaluation
    var d1 = sdBox4(p4, 1.0, 0.1);

    // Idea 1 — W-cell hive lattice: neighboring 4D cube along unused W
    let dHive = sdBox4(p4 - vec4<f32>(0.0, 0.0, 0.0, HIVE_W), HIVE_HALF, 0.08);
    d1 = min(d1, dHive);

    // Boolean carving: noise veins cut as grooves into the outer 0.07 shell
    // (HEAD's max(d1, -carve) with carve >= 0 only touched the hidden interior)
    let groove = max(veinField(p, time), -d1 - 0.07);
    d1 = max(d1, -groove);

    // Voxel tearing: per-cell glitch cubes, bounded to a crust around the surface
    // (HEAD put a sphere at every lattice corner in space -> solid magenta frame)
    let tearing_intensity = u.zoom_params.z;
    let tearAmt = clamp(bass * tearing_intensity * 0.22 + tearing_intensity * 0.06, 0.0, 0.45);
    if (tearAmt > 0.01) {
        let s = 10.0 + (bass * tearing_intensity) * 20.0;
        let cell = floor(p * s);
        let q = p - (cell + vec3<f32>(0.5)) / s;
        let h = 0.5 / s;
        var vox = 1000.0;
        if (hash33(cell + vec3<f32>(7.0)).x < tearAmt) {
            vox = sdBox3(q, vec3<f32>(h * 0.72));
        }
        // Step toward the cell wall (neighbouring voxels are not in this SDF),
        // but never less than a third of a cell: a pure wall cap made grazing
        // rays crawl through the crust, exhaust MAX_STEPS and shade as false
        // hits, washing the whole frame out once bass shrank the cells.
        let aq = abs(q);
        vox = min(vox, max(h - max(aq.x, max(aq.y, aq.z)) + h * 0.06, h * 0.33));
        // thin crust straddling the surface: tiles protrude ~0.04 at most
        let d2 = max(vox, abs(d1 + 0.02) - 0.06);
        if (d2 < d1) {
            return vec2<f32>(d2, 2.0);
        }
    }

    return vec2<f32>(d1, 1.0);
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, bass: f32) -> vec2<f32> {
    var dO: f32 = 0.0;
    var mat_id: f32 = 0.0;
    var converged = false;
    for(var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * vec3<f32>(dO);
        let dS = map(p, time, bass);
        dO += dS.x;
        mat_id = dS.y;
        if (dS.x < SURF_DIST) { converged = true; break; }
        if (dO > MAX_DIST) { break; }
    }
    // A grazing ray that runs out of steps inside the tear crust reports the
    // cell-wall bound as material 2; only a converged hit is a real voxel.
    if (!converged && mat_id == 2.0) { mat_id = 1.0; }
    return vec2<f32>(dO, mat_id);
}

// Normal Calculation
fn get_normal(p: vec3<f32>, time: f32, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, bass).x;
    let n = vec3<f32>(d) - vec3<f32>(
        map(p - e.xyy, time, bass).x,
        map(p - e.yxy, time, bass).x,
        map(p - e.yyx, time, bass).x
    );
    return normalize(n);
}

// Thin film iridescence helper
fn iridescence(view_dir: vec3<f32>, normal: vec3<f32>, shift: f32) -> vec3<f32> {
    let ndotv = max(dot(normal, view_dir), 0.0);
    let t = ndotv + shift;
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(vec3<f32>(6.28318) * (c * vec3<f32>(t) + d));
}

// Sort four values descending (compare-swap network)
fn sort4desc(v: vec4<f32>) -> vec4<f32> {
    var a = v.x; var b = v.y; var c = v.z; var d = v.w;
    var t = 0.0;
    if (a < b) { t = a; a = b; b = t; }
    if (c < d) { t = c; c = d; d = t; }
    if (a < c) { t = a; a = c; c = t; }
    if (b < d) { t = b; b = d; d = t; }
    if (b < c) { t = b; b = c; c = t; }
    return vec4<f32>(a, b, c, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let fragCoord = vec2<f32>(pixel) + vec2<f32>(0.5);
    var uv = (fragCoord - vec2<f32>(0.5) * resolution) / resolution.y;
    let uv01 = fragCoord / resolution;
    let time = u.config.x;

    // Audio (plasmaBuffer only) — bass/mids/treble
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Stateless transient burst: bass punching above the mids bed ──
    // (HEAD kept prevBass/envelope in extraBuffer[133/134], which the engine
    //  re-uploads every frame, so the "rising edge" never existed.)
    let burst = clamp((bass - mids * 0.7) * 3.0, 0.0, 2.0) * smoothstep(0.12, 0.45, bass);

    // Parameters (all four sliders LIVE)
    let rotation_speed = u.zoom_params.x;    // p1 — governs 4D spin AND motion energy
    let swarm_density = u.zoom_params.y;     // p2 — sentinel swarm density
    let iridescence_shift = u.zoom_params.w; // p4 — thin-film phase shift

    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.8) {
            let front = abs(length((uv01 - ripple.xy) * vec2<f32>(resolution.x / resolution.y, 1.0)) - age * 0.26);
            shock += (1.0 - smoothstep(0.0, 0.028, front)) * (1.0 - age / 2.8);
        }
    }
    shock = min(shock, 2.0);

    // Time-warp easing: fast surges, smooth settle — no strobing
    let warpT = time + 0.4 * sin(time * 0.31) * (0.5 + rotation_speed * 0.5);

    // Mouse Interaction (Gravity Well) — mouse_uv is 0–1, y=0 top
    let mouse01 = u.zoom_config.yz;
    let mouse_uv = (mouse01 - vec2<f32>(0.5)) * resolution / resolution.y;
    let mouse_dist = length(uv - mouse_uv);
    if (u.zoom_config.w > 0.5) { // If clicking, distort space
        let pull = 0.5 / (mouse_dist + 0.1);
        uv = uv - (uv - mouse_uv) * pull * 0.05;
    }

    // Camera setup — slow orbit scaled by the speed slider for kinetic framing
    let camA = time * (0.10 + rotation_speed * 0.15);
    let camR = rot4D(camA);
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    let roxz = camR * ro.xz;
    ro = vec3<f32>(roxz.x, 0.0, roxz.y);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));
    let rdxz = camR * rd.xz;
    rd = normalize(vec3<f32>(rdxz.x, rd.y, rdxz.y));

    // Raymarch
    let rm = raymarch(ro, rd, warpT, bass);
    let d = rm.x;
    let mat_id = rm.y;

    // Audio-reactive color temperature: mids swing the hive cool→warm
    let tempMix = clamp(mids * 0.45, 0.0, 1.0);
    let coolTint = vec3<f32>(0.25, 0.75, 1.0);
    let warmTint = vec3<f32>(1.0, 0.55, 0.25);
    let tempTint = mix(coolTint, warmTint, tempMix);

    var col = vec3<f32>(0.0);

    if (d < MAX_DIST) {
        let p = ro + rd * vec3<f32>(d);
        let n = get_normal(p, warpT, bass);

        if (mat_id == 1.0) {
            // Which 4D cell did we hit — the core tesseract or the W hive cell?
            let p4 = tessP4(p, warpT);
            let p4h = p4 - vec4<f32>(0.0, 0.0, 0.0, HIVE_W);
            let inHive = sdBox4(p4h, HIVE_HALF, 0.08) < sdBox4(p4, 1.0, 0.1);
            let q4 = select(p4, p4h, inHive);
            let cellHalf = select(1.0, HIVE_HALF, inHive);

            // Idea: W-depth film phase — the hit point's rotated W coordinate
            // feeds the film, so cells sliding through W sweep the hue.
            let wPhase = q4.w * 0.45;
            col = iridescence(-rd, n, iridescence_shift + warpT * 0.05 + wPhase);
            // Diffuse lighting
            let light_dir = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let diff = max(dot(n, light_dir), 0.0);
            col = col * diff;

            // Neon glow in the veins — HDR (>1.0), temperature-shifted, burst-flashed
            let glow_factor = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            let huePhase = sin(warpT * 1.7 + p.y) * 0.5 + 0.5; // fast smooth hue cycle
            let glow_color = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), huePhase) * tempTint;
            col += glow_color * vec3<f32>(glow_factor * (1.2 + 0.7 * bass + 0.45 * burst));

            // Carved vein grooves now exist on the surface: light their floors
            let veinLit = 1.0 - smoothstep(0.0, 0.03, veinField(p, warpT));
            col += glow_color * veinLit * (0.5 + bass * 0.35 + burst * 0.2);

            // Idea: 4D hypercube wire glow. On the 3D slice, the edges are where
            // two |q4| components sit at the half-size (the 24 square 2-faces);
            // the 32 4D edges (three components at the half-size) pierce the
            // slice as vertex sparks.
            let sq = sort4desc(abs(q4));
            let e2 = max(cellHalf - sq.y, 0.0);
            let e3 = max(cellHalf - sq.z, 0.0);
            let wire = exp(-e2 * 28.0);
            let node = exp(-(e2 + e3) * 22.0);
            let wireCol = mix(vec3<f32>(0.2, 1.0, 1.0), vec3<f32>(1.0, 0.25, 1.0), fract(wPhase + huePhase * 0.5));
            col += wireCol * (wire * 1.4 + node * 3.0) * (0.8 + bass * 0.6 + burst * 0.5);

        } else if (mat_id == 2.0) {
            // Voxel Tearing — hot HDR glitch, flashes harder on transients
            col = vec3<f32>(1.0, 0.2, 0.5) * vec3<f32>(0.85 + 0.35 * bass + 0.3 * burst);
        }
    }

    // ── Sentinel Swarms: velocity-stretched SPEED STREAKS ─────────────
    // Idea: sentinels orbit the projected centres of the 8 cubic cells (±axis
    // in the tesseract frame) and the hive cell — inverse 4D tumble, 4D→3D
    // perspective by W distance from the slice, then the camera projection.
    // (HEAD streamed them around the screen centre with dot(uv, tangential),
    //  which is identically 0, so they were flickering concentric rings.)
    let swarmSpeed = 4.0 + rotation_speed * 4.0 + bass * 5.0;
    let thresh = 0.94 - swarm_density * 0.055;
    let w_off = (u.zoom_config.z - 0.5) * 2.0;
    var swarm_val = 0.0;
    var bestR = 1e3;
    var bestLoc = vec2<f32>(0.0);
    var bestRk = 1.0;
    for (var k = 0; k < 9; k++) {
        var o = vec4<f32>(0.0, 0.0, 0.0, HIVE_W);
        if (k < 8) {
            let axis = k / 2;
            let sgn = select(-1.0, 1.0, (k % 2) == 0);
            o = vec4<f32>(0.0);
            o[axis] = sgn;
        }
        let wc = tessInv(o, warpT);
        let persp = 1.0 / (1.0 + 0.3 * abs(wc.w - w_off));
        let rel = wc.xyz * persp - ro;
        // world -> camera (transpose of camR on xz)
        let lz = -camR[0][1] * rel.x + camR[1][1] * rel.z;
        let lx = camR[0][0] * rel.x - camR[1][0] * rel.z;
        if (lz < 0.2) { continue; }
        let suv = vec2<f32>(lx, rel.y) / lz;
        let rk = 0.75 * persp / lz; // projected cell radius
        let loc = uv - suv;
        let r = length(loc);
        let rn = r / rk;
        if (rn < bestR) { bestR = rn; bestLoc = loc; bestRk = rk; }
        let fk = f32(k);
        // Kepler-ish angular speed: inner orbits are faster
        let a = atan2(loc.y, loc.x) - warpT * swarmSpeed * 0.07 / (rn + 0.35);
        let n1 = vnoise3(vec3<f32>(cos(a) * 2.2 + fk * 5.1, sin(a) * 2.2, rn * 9.0 + warpT * 0.7));
        let n2 = vnoise3(vec3<f32>(cos(a) * 5.5 + 31.7 + fk * 3.3, sin(a) * 5.5 + 11.3, rn * 18.0 + warpT * 1.3));
        let swarmNoise = n1 * 0.65 + n2 * 0.35;
        let orbitBand = exp(-rn * rn * 0.9);
        swarm_val = max(swarm_val, smoothstep(thresh, thresh + 0.06, swarmNoise) * orbitBand);
    }

    // Mask swarms to only appear near the structure using depth
    let depth_mask = 1.0 - smoothstep(0.0, 12.0, d);
    let swarm_color = vec3<f32>(0.1, 1.0, 0.55) * tempTint * vec3<f32>(swarm_val * depth_mask * (2.2 + burst * 0.8));
    col += swarm_color;

    // Idea 2 — sentinel pheromone lanes: radial spokes streaming outward from
    // the nearest projected cell centre, beside the orbiting streaks
    let a0 = atan2(bestLoc.y, bestLoc.x);
    let alongRad = bestR * 3.5 - warpT * swarmSpeed * 0.12;
    let nPhero = vnoise3(vec3<f32>(cos(a0) * 6.0, sin(a0) * 6.0, alongRad));
    let phero = smoothstep(0.90, 0.97, nPhero) * depth_mask * exp(-bestR * 0.5)
              * clamp(swarm_density * 0.15, 0.0, 0.8);
    col += vec3<f32>(0.08, 0.55, 0.28) * tempTint * vec3<f32>(phero * (1.2 + burst));
    col += iridescence(vec3<f32>(0.0, 0.0, 1.0), normalize(vec3<f32>(uv, 1.0)), iridescence_shift + time * 0.1)
         * shock * (0.8 + treble * 1.2);

    // Atmospheric Fog — depth atmosphere, temperature-tinted shadows
    let fogCol = mix(vec3<f32>(0.02, 0.0, 0.05), vec3<f32>(0.05, 0.025, 0.0), tempMix * 0.5);
    col = mix(col, fogCol, 1.0 - exp(-0.02 * d * d));
    col = max(col, vec3<f32>(0.0));

    // ── HDR velocity feedback trails (dataTextureC → dataTextureA) ────
    // Peak-hold: steady state equals the current frame (HEAD's col + 0.86·prev
    // settled at ~7× and washed out); moving light leaves decaying trails.
    // The decay is per 1/60 s, not per frame: texel (0,0).a carries fract(time)
    // of the previous frame, so a slow frame (SwiftShader ~2 fps, a hitch, a
    // re-seeked clock) does not peak-hold several distant poses of the spinning
    // slice into one washed-out white union.
    let prev = textureLoad(dataTextureC, pixel, 0);
    let prevT = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).a;
    let dt = fract(fract(time) - prevT + 1.0); // wraps; a > 1 s gap reads short but still decays hard
    let trailDecay = 0.78 + clamp(rotation_speed, 0.0, 2.0) * 0.04; // faster spin → longer streaks
    let decay = pow(trailDecay, clamp(dt * 60.0, 1.0, 60.0));
    let history = min(max(prev.rgb, vec3<f32>(0.0)) * decay, vec3<f32>(HDR_CLAMP));
    var hdr = max(col, history);
    hdr = min(hdr, vec3<f32>(HDR_CLAMP));

    // Real generated depth (near = 1, background = 0)
    let depthOut = 1.0 - clamp(d / 12.0, 0.0, 1.0);
    // A.a = depth, except texel (0,0) which stamps the frame clock for the trail dt
    let aOut = select(depthOut, fract(time), pixel.x == 0 && pixel.y == 0);
    textureStore(dataTextureA, pixel, vec4<f32>(hdr, aOut));

    // ── ACES tone map (linear HDR workflow, exposure rides audio) ─────
    // Audio gains stay modest: the quiet frame already fills most of the screen,
    // so HEAD's 3-7x bass multipliers saturated the whole frame to white.
    let exposure = 1.15 + mids * 0.1 + burst * 0.12 + treble * 0.05;
    let outCol = acesToneMap(max(hdr * exposure, vec3<f32>(0.0)));

    // Semantic alpha: luminous intensity + structural hit, never flat 1.0
    let hitMask = 1.0 - f32(d > MAX_DIST);
    let alpha = clamp(0.12 + luma(outCol) * 1.2 + swarm_val * depth_mask * 0.3 + hitMask * 0.15 + shock * 0.2, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(outCol, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
