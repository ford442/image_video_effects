// ═══════════════════════════════════════════════════════════════════
//  Fractured Monolith — levitating cell-fractured slab over liquid floor
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-11, 2026-11-08
//  Ideas: per-shard identity tint; fracture-plane glints; seam light pool on the liquid; rising seam pulse; spall chips; crack dust; per-shard levitation phase; downdraft ring train on the liquid (deep-water dispersion, §12.2D; floor-hit normal + pool light); chipped-edge wear (4-tap SDF curvature, §12.2E)
//  Rescue 2026-11-08: trail history re-brightened to a saturated blue sky dome (tone-mapped C decayed without decode); spall chips tiled all of space (cell fold has no bound); camera was upside-down (floor at the top); shard tumble was unbounded in time and about the slab axis (slab eroded away); audio multiplied absolute time inside phases (phase jumped by time*dAudio)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Fracture Spread, y=Levitation Speed, z=Glow Intensity, w=Rotation Speed

// --- Helper Functions ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Inverse of the Narkowicz ACES fit above (display -> scene-linear). The trail
// history in A/C is stored tone-mapped, so it must be decoded before decaying.
fn acesInverse(y_in: vec3<f32>) -> vec3<f32> {
    let y = clamp(y_in, vec3<f32>(0.0), vec3<f32>(0.98));
    let a = 2.43 * y - vec3<f32>(2.51);
    let b = 0.59 * y - vec3<f32>(0.03);
    let c = 0.14 * y;
    let disc = max(b * b - 4.0 * a * c, vec3<f32>(0.0));
    return max((-b - sqrt(disc)) / (2.0 * a), vec3<f32>(0.0));
}

// Basic 3D Noise for fracture displacement
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let res = mix(
        mix(mix(hash31(i + vec3<f32>(0.0, 0.0, 0.0)), hash31(i + vec3<f32>(1.0, 0.0, 0.0)), w.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 0.0)), hash31(i + vec3<f32>(1.0, 1.0, 0.0)), w.x), w.y),
        mix(mix(hash31(i + vec3<f32>(0.0, 0.0, 1.0)), hash31(i + vec3<f32>(1.0, 0.0, 1.0)), w.x),
            mix(hash31(i + vec3<f32>(0.0, 1.0, 1.0)), hash31(i + vec3<f32>(1.0, 1.0, 1.0)), w.x), w.y), w.z
    );
    return res;
}

// --- SDFs ---

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdPlane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
    return dot(p, n) + h;
}

// Levitation bob and slab yaw, shared by map() and the seam-pool light so both
// agree. Rescue: audio used to multiply ABSOLUTE time inside these phases
// (time*0.35*level), so every level change jumped the phase by time*dLevel
// (several rad per frame after a few minutes). Audio now changes amplitude or a
// bounded wobble only.
fn slabBob(time: f32, lev: f32, mid: f32) -> f32 {
    return sin(time * lev) * (0.5 + mid * 0.12);
}
fn slabYaw(time: f32, rotSpeed: f32, overall: f32) -> f32 {
    return time * 0.2 * rotSpeed + overall * 0.2 * sin(time * 0.9);
}

// One dispersive ring of the downdraft train: phase k r - w t, amplitude = the
// bob speed the slab had when the ring left it (retarded time r / group speed).
fn ringWave(r: f32, time: f32, kw: f32, omega: f32, cg: f32, lev: f32, mid: f32, decay: f32) -> f32 {
    let tRet = time - r / cg;
    let emit = abs(lev * cos(tRet * lev)) * (0.5 + mid * 0.12);
    return sin(kw * r - omega * time * 0.35) * emit * exp(-r * decay);
}

// ── Idea 6: downdraft ring train height at radius r from the slab axis (§12.2D
// deep-water dispersion). The levitating slab pushes the liquid: rings leave the
// axis with w = sqrt(g k) (k = 2pi/lambda, lambda 1.2 / 2.3 / 3.4), so long waves
// outrun short ones and the rings spread into a train; group speed = 0.5 (w/k)*0.35;
// each ring carries the bob speed the slab had when it left (retarded time), so a
// still slab (Levitation Speed 0) raises no rings. Evaluated ONLY at the floor hit
// (height + one forward difference for the slope), never per march step.
fn ringHeight(r: f32, time: f32, lev: f32, mid: f32) -> f32 {
    let train = ringWave(r, time, 5.23598, 7.16694, 0.23954, lev, mid, 0.18)
              + ringWave(r, time, 2.73182, 5.17679, 0.33162, lev, mid, 0.23)
              + ringWave(r, time, 1.84799, 4.25780, 0.40320, lev, mid, 0.28);
    return train * 0.18 / (1.0 + r * 0.6);
}

// --- Map Function ---
// Returns vec3: x = distance, y = material ID, z = glow accumulation
fn map(p: vec3<f32>) -> vec3<f32> {
    var d = 1000.0;
    var mat = 0.0;
    var glow = 0.0;

    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioBass = plasmaBuffer[0].x;
    let audioMid = plasmaBuffer[0].y;
    let audioHigh = plasmaBuffer[0].z;
    let audioOverall = (audioBass + audioMid + audioHigh) / 3.0;
    let spread = u.zoom_params.x * 2.0;
    let levSpeed = u.zoom_params.y;
    let rotSpeed = u.zoom_params.w;

    // --- Liquid Terrain ---
    // Smooth wavy floor
    let audioWobble = audioOverall * 0.6 * sin(time * 0.41);
    let wave = sin(p.x * 0.5 + time * 0.5 + audioWobble) * cos(p.z * 0.5 + time * 0.3 + audioWobble) * 0.2 * (1.0 + audioBass * 0.35);

    let floorDist = sdPlane(p, vec3<f32>(0.0, 1.0, 0.0), 2.0) + wave;
    if (floorDist < d) {
        d = floorDist;
        mat = 1.0; // Floor material
    }

    // --- Monolith ---
    var bp = p;
    // Levitation bobbing
    bp.y -= slabBob(time, levSpeed, audioMid) + 2.0;
    // Slow global rotation
    let temp_bp_xz = rot(slabYaw(time, rotSpeed, audioOverall)) * bp.xz;
    bp.x = temp_bp_xz.x;
    bp.z = temp_bp_xz.y;


    // Base shape: Tall box
    let baseBox = sdBox(bp, vec3<f32>(1.5, 4.0, 1.5));

    // Fracturing using noise-displaced planes
    // We simulate fracturing by expanding space based on a cellular-like grid
    let cellSize = 1.5;
    let cellId = floor(bp / cellSize);
    let cellCenter = (cellId + 0.5) * cellSize;

    // Drift fragments away from center based on cell ID
    let cellHash = hash31(cellId);
    let drift = (cellHash - 0.5) * spread;
    var fp = bp;
    var dir = normalize(cellCenter + vec3<f32>(0.001));
    fp -= dir * drift * (1.0 + sin(time * 0.5 + cellHash * 10.0) * 0.2);

    // ── Idea 5: per-shard levitation phase — each shard bobs on its own phase
    // (hash of its cell) at the Levitation Speed rhythm, amplitude opened by
    // Fracture Spread, so the seams breathe instead of the slab moving as one
    // block. Zero at t=0, at spread=0 and at Levitation Speed 0.
    let shardPhase = cellHash * 6.28318;
    fp.y -= (sin(time * levSpeed * 0.7 + shardPhase) - sin(shardPhase)) * 0.2 * spread;

    // Individual piece tumble. Rescue: this used to be `(h-0.5)*time*rotSpeed`
    // about the SLAB axis — unbounded, so every shard orbited out of its own
    // cell and the slab eroded to a few fragments within ~15 s. Now a bounded
    // wobble about the shard's OWN centre (tanh soft-limits Rotation Speed > 1).
    let hRot = hash31(cellId + vec3<f32>(1.0)) - 0.5;
    let rotPh = hRot * 12.566;
    let tumble = 1.2 * tanh(hRot * rotSpeed * (sin(time * 0.5 + rotPh) - sin(rotPh)) / 1.2);
    var lp = fp - cellCenter;
    let temp_lp_xz = rot(tumble) * lp.xz;
    lp.x = temp_lp_xz.x;
    lp.z = temp_lp_xz.y;
    let temp_lp_xy = rot(tumble * 0.5) * lp.xy;
    lp.x = temp_lp_xy.x;
    lp.y = temp_lp_xy.y;

    // Carve out cracks
    let crackNoise = noise(bp * 3.0);
    let shardDist = max(baseBox, sdBox(lp, vec3<f32>(cellSize * 0.45)) - crackNoise * 0.1);

    // The monolith surface
    if (shardDist < d) {
        d = shardDist;
        mat = 2.0; // Monolith material
    }

    // Spall chips — small stones knocked off the shard corner, same drift as the cell.
    let chipHash = hash31(cellId + vec3<f32>(4.2, 1.7, 0.3));
    let chipOff = dir * (0.22 + chipHash * 0.18) + vec3<f32>(0.0, 0.18 + chipHash * 0.12, 0.0);
    let chip = sdBox(lp - chipOff, vec3<f32>(0.11, 0.08, 0.1));
    // Rescue: the cell fold repeats through ALL of space, so these chips used to
    // tile the whole scene as a field of debris (sky "snow", stones on the sea).
    // Intersect with a shell around the slab so they only exist near their shard.
    let chipBounded = max(chip, baseBox - 1.4);
    if (chipBounded < d && chipHash > 0.62) {
        d = chipBounded;
        mat = 3.0;
    }

    // Inner Glow accumulation in cracks
    // When inside the bounding box but outside shards
    if (baseBox < 0.5 && shardDist > 0.05) {
        // Idea 4: rising seam pulse — a bass-lifted band climbs the slab's local Y
        // (-4..4) and boosts crack glow only where it passes; paced by Levitation Speed.
        let pulsePos = fract(time * (0.15 + levSpeed * 0.2)) * 10.0 - 5.0;
        let pulseBand = exp(-abs(bp.y - pulsePos) * 2.5);
        let seamPulse = 1.0 + pulseBand * (0.8 + audioBass * 2.0);
        glow += 0.01 / (0.01 + abs(shardDist)) * u.zoom_params.z * (1.0 + audioHigh * 0.45) * seamPulse;
        // Crack dust — a wider gray veil where fracture spread opens the slab.
        glow += exp(-abs(shardDist) * 5.0) * spread * 0.015;
    }

    return vec3<f32>(d, mat, glow);
}

// Tetrahedron gradient: 4 taps instead of 6 (same 0.001-scale footprint).
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.000577;
    let k1 = vec3<f32>(1.0, -1.0, -1.0);
    let k2 = vec3<f32>(-1.0, -1.0, 1.0);
    let k3 = vec3<f32>(-1.0, 1.0, -1.0);
    let k4 = vec3<f32>(1.0, 1.0, 1.0);
    return normalize(k1 * map(p + k1 * e).x + k2 * map(p + k2 * e).x
                   + k3 * map(p + k3 * e).x + k4 * map(p + k4 * e).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }

    var uv = (fragCoord * 2.0 - dims) / dims.y;
    // Rescue: pixel y runs down; the camera basis is +y up, so the old image was
    // upside-down (liquid floor at the top, sky gradient at the bottom).
    uv.y = -uv.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 2.0, 12.0);
    // Mouse interaction for camera orbit
    let mouseX = u.zoom_config.y * 2.0 - 1.0;
    let mouseY = u.zoom_config.z * 2.0 - 1.0;

    let temp_ro_yz = rot(mouseY * 1.0) * ro.yz;
    ro.y = temp_ro_yz.x;
    ro.z = temp_ro_yz.y;

    let temp_ro_xz = rot(mouseX * 3.14) * ro.xz;
    ro.x = temp_ro_xz.x;
    ro.z = temp_ro_xz.y;


    let ta = vec3<f32>(0.0, 2.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.2 * ww);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = -1.0;
    var accumGlow = 0.0;

    for (var i = 0; i < 120; i++) {
        var p = ro + rd * t;
        var res = map(p);
        d = res.x;
        m = res.y;
        accumGlow += res.z;

        if (d < 0.001 || t > 30.0) { break; }
        t += d * 0.8; // Reduce step size for better glow accumulation and fracture detail
    }

    var col = vec3<f32>(0.02, 0.02, 0.03); // Dark background sky
    // Add subtle gradient to sky
    col += vec3<f32>(0.05, 0.1, 0.2) * max(0.0, rd.y);

    if (t < 30.0) {
        var p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lig = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let dif = max(dot(n, lig), 0.0);
        let fre = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);

        if (m == 1.0) {
            // Liquid Floor
            let time = u.config.x;
            let aud = plasmaBuffer[0].xyz;
            // ── Idea 6 (shading side): the ring train's height field tilts the floor
            // normal (forward-difference slope along the radius), so the existing
            // sheen / Fresnel / pool terms ring outward from under the slab.
            let rr = length(p.xz);
            let hR = ringHeight(rr, time, u.zoom_params.y, aud.y);
            let ringSlope = (ringHeight(rr + 0.05, time, u.zoom_params.y, aud.y) - hR) / 0.05;
            let radial = p.xz / max(rr, 0.001);
            let nF = normalize(n + vec3<f32>(-radial.x, 0.0, -radial.y) * ringSlope * 2.2);
            let difF = max(dot(nF, lig), 0.0);
            let freF = pow(1.0 - max(dot(nF, -rd), 0.0), 4.0);
            let ringN = clamp(hR * 24.0, -1.0, 1.0);   // display gain on the physical height
            let refl = reflect(rd, nF);
            // Fake reflections by stepping once into the reflection direction
            let refRes = map(p + refl * 2.0);
            var refCol = vec3<f32>(0.02, 0.03, 0.05);
            if (refRes.y == 2.0) {
                refCol = vec3<f32>(0.1, 0.1, 0.12);
            }
            col = mix(vec3<f32>(0.0, 0.05, 0.1) * difF, refCol, freF * 0.8 + 0.2);

            // Idea 3: seam light pool — crack light leaks onto the liquid through the
            // same rotated 1.5 cell grid as the fracture (bright seams, shard shadows).
            let bob = slabBob(time, u.zoom_params.y, aud.y);
            let slabBottom = bob + 2.0 - 4.0;
            let gap = max(slabBottom - p.y, 0.0);
            let q = rot(slabYaw(time, u.zoom_params.w, (aud.x + aud.y + aud.z) / 3.0)) * p.xz;
            let foot = sdBox(vec3<f32>(q.x, 0.0, q.y), vec3<f32>(1.5 + u.zoom_params.x, 1.0, 1.5 + u.zoom_params.x));
            let footMask = 1.0 - smoothstep(-0.2, 1.6 + gap, foot);
            let cellF = abs(fract(q / 1.5) - 0.5);
            let seamDist = 0.5 - max(cellF.x, cellF.y);
            let seamW = 0.03 + u.zoom_params.x * 0.2;
            let seam = 1.0 - smoothstep(0.0, seamW, seamDist);
            let proximity = 1.0 / (1.0 + gap * gap * 1.5);
            // Idea 6: crests brighten and troughs dim the pooled seam light
            let poolLight = footMask * proximity * (0.25 + seam * 1.6) * u.zoom_params.z * (1.0 + aud.z * 0.4)
                          * (1.0 + 1.6 * ringN);
            col += vec3<f32>(0.1, 0.5, 1.0) * poolLight * (0.35 + 0.65 * freF + 0.3 * difF);
            // Idea 6: a crest glint rides each ring a little beyond the pool, fading with radius
            let crest = max(ringN, 0.0);
            col += vec3<f32>(0.3, 0.75, 1.0) * crest * crest * 0.9 * exp(-rr * 0.12) * u.zoom_params.z * (0.4 + 0.6 * freF);
        } else if (m == 2.0) {
            // Monolith Material
            var matCol = vec3<f32>(0.05, 0.05, 0.06);
            // Idea 1 — shard identity from the same cell grid as the fracture
            let cellId = floor(p / 1.5);
            let shardHue = hash31(cellId);
            matCol = mix(matCol, vec3<f32>(0.04 + shardHue * 0.08, 0.05, 0.07 + (1.0 - shardHue) * 0.06), 0.85);
            col = matCol * dif + fre * vec3<f32>(0.1, 0.2, 0.3);
            // Idea 2 — glint on fracture planes (crack noise already carves the SDF)
            let crackGlint = noise(p * 3.0);
            col += vec3<f32>(0.55, 0.82, 1.0) * pow(fre, 2.2) * crackGlint * (0.35 + u.zoom_params.z * 0.4);
            // ── Idea 7: chipped-edge wear (§12.2E SDF curvature) ──────────────
            // Tetrahedron Laplacian: (sum of 4 taps - 4 d) / (2 e^2) with the hit
            // distance `d` the march already holds — 4 map() calls. Large and
            // positive on convex edges (stone chipped pale and sharp), negative in
            // concave seams (grime). Crack-noise ripple is ~+-3, so the threshold
            // sits above it. Only monolith pixels pay for the taps.
            let ce = 0.025;
            let kt1 = vec3<f32>(1.0, -1.0, -1.0);
            let kt2 = vec3<f32>(-1.0, -1.0, 1.0);
            let kt3 = vec3<f32>(-1.0, 1.0, -1.0);
            let kt4 = vec3<f32>(1.0, 1.0, 1.0);
            let kSum = map(p + kt1 * ce).x + map(p + kt2 * ce).x + map(p + kt3 * ce).x + map(p + kt4 * ce).x;
            let curv = (kSum - 4.0 * d) / (2.0 * ce * ce);
            let edgeWear = smoothstep(3.0, 12.0, curv);
            let seamGrime = smoothstep(3.0, 12.0, -curv);
            col += vec3<f32>(0.46, 0.5, 0.55) * edgeWear * (0.3 + 0.7 * dif + 0.4 * fre);
            col *= 1.0 - 0.4 * seamGrime;
        } else if (m == 3.0) {
            col = vec3<f32>(0.16, 0.15, 0.14) * dif + fre * vec3<f32>(0.35, 0.4, 0.45);
        }
    }

    // Add Core Glow
    let glowColor = vec3<f32>(0.1, 0.5, 1.0); // Cyan/Blue glow
    col += accumGlow * glowColor * 0.02;
    col += accumGlow * vec3<f32>(0.55, 0.52, 0.48) * u.zoom_params.x * 0.01;

    // Subtle vignette
    col *= 1.0 - 0.3 * length(uv);

    let coord = vec2<i32>(id.xy);
    let previous = textureLoad(dataTextureC, coord, 0).rgb;
    // Rescue: `previous` is already ACES display colour; decaying it by 0.82 and
    // re-tone-mapping with 1.12 exposure has a non-zero fixed point (~0.69), so any
    // pixel above ~0.05 (the sky's blue channel!) climbed to a saturated, hard-edged
    // blue dome and never faded. Decode to scene-linear (and undo the exposure)
    // before the 0.82 decay so trails actually decay.
    let previousLinear = acesInverse(previous) / 1.12;
    col = max(max(col, vec3<f32>(0.0)), previousLinear * 0.82);
    col = acesToneMap(col * 1.12);
    let hitMask = select(0.0, 1.0, t < 30.0);
    let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(0.06 + hitMask * 0.68 + luma * 0.24, 0.0, 0.98);
    let depth = select(1.0, clamp(t / 30.0, 0.0, 0.995), t < 30.0);

    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
