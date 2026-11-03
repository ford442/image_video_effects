// ═══════════════════════════════════════════════════════════════════
//  Nano Assembler Crystal
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12, 2026-11-01
//  Ideas: hex facet lock of orientation; recalescence glow from latent heat; six-fold interface anisotropy with gradient confidence (§12.2 tactic 1+3); tip-triggered sidebranch noise (Mullins-Sekerka); orientation-domain boundary seams with impurity segregation
//  A packing: raw (phase, temp, orientation, impurity + 2.0 ownership offset)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = fract(p * vec2<f32>(0.1031, 0.1030));
    p2 += dot(p2, p2.yx + 33.33);
    return fract((p2.xx + p2.yx) * p2.xy);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// A.a carries impurity + 2.0. C written by another shader (or empty) never has
// a > 1.5, so such texels read as default liquid and the main body reseeds.
const OWNED_OFFSET: f32 = 2.0;
const HEX_STEP: f32 = 1.0471975512;

fn stateAt(coord: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    let s = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0);
    let owned = s.a > 1.5;
    return select(vec4<f32>(0.0, -0.2, 0.0, 0.05),
                  vec4<f32>(s.r, s.g, s.b, s.a - OWNED_OFFSET), owned);
}

// Misorientation between two grains, 0..1. The hex lattice repeats every 60 deg,
// so the difference is folded modulo one hex step (max 30 deg) and normalised.
fn domainStep(a: f32, b: f32) -> f32 {
    let d = a - b;
    return abs(d - round(d / HEX_STEP) * HEX_STEP) / (0.5 * HEX_STEP);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dims = vec2<i32>(res);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let prevState = stateAt(coord, dims);
    var phase = prevState.r;
    var temp = prevState.g;
    var orientation = prevState.b;
    var impurity = prevState.a;

    let owned = textureLoad(dataTextureC, coord, 0).a > 1.5;
    if (time < 0.1 || !owned) {
        phase = 0.0;
        temp = -0.2;
        orientation = 0.0;
        impurity = hash12(uv * 100.0) * 0.1;
        // Polycrystal seeding: jittered 20x20 seeds, each pixel inherits the random
        // orientation of its nearest seed (HEAD: one radial atan2 field, so the
        // whole sheet was two hue domains split on the atan2 branch cut).
        let seed_grid = 20.0;
        let sg = uv * seed_grid;
        let gi = floor(sg);
        let gf = fract(sg);
        var seedD = 9.0;
        var seedId = gi;
        for (var j = -1; j <= 1; j = j + 1) {
            for (var i = -1; i <= 1; i = i + 1) {
                let id = gi + vec2<f32>(f32(i), f32(j));
                let jit = hash2(id + vec2<f32>(11.0, 5.0)) * 0.6 + vec2<f32>(0.2);
                let d = length(vec2<f32>(f32(i), f32(j)) + jit - gf);
                let closer = d < seedD;
                seedD = select(seedD, d, closer);
                seedId = select(seedId, id, closer);
            }
        }
        orientation = (hash12(seedId * 1.7 + vec2<f32>(3.1, 8.3)) - 0.5) * 6.28318530718;
        if (seedD < 0.06) {
            phase = 1.0;
            temp = 0.0;
        }
    }

    phase = clamp(phase, 0.0, 1.0);
    temp = clamp(temp, -1.0, 1.0);
    impurity = clamp(impurity, 0.0, 1.0);

    let assembly_progress = u.zoom_params.x;
    let particle_density = u.zoom_params.y;
    let scatter_force = u.zoom_params.z;
    let rebuild_speed = u.zoom_params.w;

    let grid_size = mix(50.0, 5.0, particle_density);
    let grid_coord = floor(uv * grid_size) / grid_size;
    let cell_uv = fract(uv * grid_size);

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let aspect = u.config.z / max(u.config.w, 1.0);
    let dist_vec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let mouseDist = length(dist_vec);
    let mouse_repel = smoothstep(0.2, 0.0, mouseDist);

    let current_state = clamp(assembly_progress - mouse_repel * scatter_force * (1.0 + audio.x * 0.2), 0.0, 1.0);
    let pulse = 0.5 + 0.5 * sin(time * rebuild_speed * 2.0);
    let anim_state = mix(current_state, current_state * pulse, rebuild_speed * 0.5);

    phase = mix(phase, anim_state, 0.02);

    let left = stateAt(coord + vec2<i32>(-1, 0), dims);
    let right = stateAt(coord + vec2<i32>(1, 0), dims);
    let down = stateAt(coord + vec2<i32>(0, -1), dims);
    let up = stateAt(coord + vec2<i32>(0, 1), dims);

    let lapPhase = left.r + right.r + down.r + up.r - 4.0 * phase;

    let anisotropy = mix(0.0, 0.5, u.zoom_params.y);
    let angle = orientation;
    let gradPhase = vec2<f32>(right.r - left.r, up.r - down.r) * 0.5;
    // ── Idea 1: six-fold interface anisotropy with gradient confidence ──
    // HEAD scaled growth by a 2-fold |n·dir| although the grain hex-locks to
    // 60°. The standard snowflake phase-field law is 1 + eps*cos(6(θn - θ));
    // |∇φ| (computed and discarded at HEAD) is the confidence, so impurity-hash
    // noise in flat regions no longer scrambles orientation (confetti at HEAD).
    let gMag = length(gradPhase);
    let gConf = smoothstep(0.004, 0.03, gMag);
    let nAngle = select(0.0, atan2(gradPhase.y, gradPhase.x), gMag > 1e-6);
    let anisoFactor = 1.0 + anisotropy * cos(6.0 * (nAngle - angle)) * gConf;

    let supercooling = mix(0.1, 0.8, u.zoom_params.x);
    let growthRate = mix(0.001, 0.01, u.zoom_params.z) * (1.0 + audio.y * 0.25);
    let m = temp + supercooling * (1.0 - 2.0 * impurity);
    let phaseReaction = phase * (1.0 - phase) * (phase - 0.5 + m * 0.5);

    // ── Idea 2: tip-triggered sidebranch noise (Mullins-Sekerka) ────────
    // Thermal (Langevin) noise on the reaction, only on the interface band and
    // only where the front is convex (-lap > 0): tips split, flat fronts don't.
    let sbNoise = hash12(vec2<f32>(gid.xy) + floor(time * 30.0) * 17.31) - 0.5;
    let interfaceBand = 4.0 * phase * (1.0 - phase);
    let tipCurv = clamp(-lapPhase * 6.0, 0.0, 1.0);
    let sidebranch = 1.0 + 1.6 * sbNoise * interfaceBand * tipCurv;

    phase += phaseReaction * growthRate * anisoFactor * sidebranch + lapPhase * 0.1 * growthRate;
    phase = clamp(phase, 0.0, 1.0);

    let lapTemp = left.g + right.g + down.g + up.g - 4.0 * temp;
    let latentHeat = (phase - prevState.r) * 0.5;
    temp += lapTemp * 0.05 + latentHeat;
    temp = clamp(temp, -1.0, 1.0);

    let lapOrient = left.b + right.b + down.b + up.b - 4.0 * orientation;
    orientation += lapOrient * 0.01 * phase;
    if (phase > 0.1 && phase < 0.9) {
        // relax along the shortest hex-equivalent arc toward the interface normal
        let toNormal = nAngle - orientation;
        let hexDelta = toNormal - round(toNormal / HEX_STEP) * HEX_STEP;
        orientation += hexDelta * 0.05 * gConf;
    }

    // Idea 1 — hex facet lock: snap orientation to 60° when phase is high
    let hexStep = 6.28318530718 / 6.0;
    let snapped = round(orientation / hexStep) * hexStep;
    orientation = mix(orientation, snapped, smoothstep(0.55, 0.92, phase) * 0.35);

    let lapImpurity = left.a + right.a + down.a + up.a - 4.0 * impurity;
    let phaseChange = phase - prevState.r;
    // ── Idea 3: orientation-domain boundary seams ───────────────────────
    // Where two solid domains of different (hex-locked) orientation meet, solute
    // piles up: the already-loaded neighbours give the boundary strength.
    let solidL = smoothstep(0.5, 0.8, min(phase, left.r));
    let solidR = smoothstep(0.5, 0.8, min(phase, right.r));
    let solidD = smoothstep(0.5, 0.8, min(phase, down.r));
    let solidU = smoothstep(0.5, 0.8, min(phase, up.r));
    let seam = clamp(max(max(smoothstep(0.3, 0.9, domainStep(orientation, left.b)) * solidL,
                             smoothstep(0.3, 0.9, domainStep(orientation, right.b)) * solidR),
                         max(smoothstep(0.3, 0.9, domainStep(orientation, down.b)) * solidD,
                             smoothstep(0.3, 0.9, domainStep(orientation, up.b)) * solidU)),
                     0.0, 1.0);
    impurity += lapImpurity * 0.02 - phaseChange * 0.1 + seam * 0.004;
    impurity = clamp(impurity, 0.0, 1.0);

    let mouseInfluence = smoothstep(0.04, 0.0, mouseDist) * mouseDown;
    if (mouseDown > 0.5) {
        phase = mix(phase, 0.0, mouseInfluence * 0.5);
        temp = mix(temp, 0.3, mouseInfluence);
    }

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.3 && rDist < 0.03) {
            let nucleation = smoothstep(0.03, 0.0, rDist) * max(0.0, 1.0 - age * 3.0);
            phase = mix(phase, 1.0, nucleation * 0.5);
        }
    }
    phase = clamp(phase, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(phase, temp, orientation, impurity + OWNED_OFFSET));

    let border = 0.1;
    let cell_dist = max(abs(cell_uv.x - 0.5), abs(cell_uv.y - 0.5)) * 2.0;
    let core_radius = 0.5 - border;
    let bot_alpha = exp(-pow(max(0.0, cell_dist - core_radius) / max(border * 0.5, 0.0001), 2.0) * 2.0);

    let orientNorm = fract(orientation / 6.283185307);
    let h6 = orientNorm * 6.0;
    let c = 0.8;
    let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
    var crystalColor: vec3<f32>;
    if (h6 < 1.0) { crystalColor = vec3(c, x, 0.3); }
    else if (h6 < 2.0) { crystalColor = vec3(x, c, 0.3); }
    else if (h6 < 3.0) { crystalColor = vec3(0.3, c, x); }
    else if (h6 < 4.0) { crystalColor = vec3(0.3, x, c); }
    else if (h6 < 5.0) { crystalColor = vec3(x, 0.3, c); }
    else { crystalColor = vec3(c, 0.3, x); }

    let liquidColor = vec3<f32>(0.05, 0.08, 0.15) * (1.0 + temp * 0.5);
    let disassembled_glow = vec3<f32>(0.2, 0.8, 1.0) * bot_alpha * (1.0 - phase);

    let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);
    let interfaceColor = vec3<f32>(0.9, 0.95, 1.0);

    var displayColor = mix(liquidColor, crystalColor, smoothstep(0.4, 0.6, phase));
    displayColor = mix(displayColor, interfaceColor, interfaceMask * 0.5);
    displayColor += disassembled_glow;

    // Idea 2 — recalescence glow from the latent-heat temperature spike
    let recalescence = max(latentHeat, 0.0) * (1.4 + audio.z * 0.5);
    displayColor += vec3<f32>(1.0, 0.82, 0.45) * recalescence * 3.2;

    displayColor = mix(displayColor, vec3<f32>(0.8, 0.6, 0.4), impurity * 0.3);
    // Idea 3 (display): dark seam along domain boundaries, solute-warm at the core
    displayColor = mix(displayColor, vec3<f32>(0.22, 0.14, 0.08), seam * 0.55);

    let edge_dist = abs(cell_dist - core_radius);
    let edge_highlight = (1.0 - smoothstep(0.0, 0.05, edge_dist)) * (1.0 - anim_state);
    displayColor += vec3<f32>(0.0, 1.0, 1.0) * edge_highlight;

    let mapped = aces(max(displayColor, vec3<f32>(0.0)));
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let alpha = clamp(src.a * 0.15 + phase * 0.7 + recalescence * 2.0 + bot_alpha * (1.0 - phase) * 0.35, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
