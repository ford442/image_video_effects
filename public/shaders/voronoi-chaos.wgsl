// ═══════════════════════════════════════════════════════════════════
//  Voronoi Chaos
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-11, 2026-11-09
//  Ideas: bass-snap shard jitter on top of the continuous mouse repulsion;
//         held-pointer trail smear from exact dataTextureC history;
//         fracture seams from the F1/F2 bisector distance (Worley border, section 12.2);
//         impact shatter (a click front tumbles the shards it crosses)
//  Rescues: tile colour follows the pushed seed (m_sample); no time*audio phase jumps; no black holes when the nearest seed is >1 cell away
//  A packing: display RGBA history (previously unused; A/C now genuinely read/written)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// Voronoi Chaos
// Generates a Voronoi grid where cell centers are agitated by mouse position and time.
//
// Param1: Cell Size (Default: 0.5)
// Param2: Chaos Amount (Default: 0.5)
// Param3: Color Mix (Default: 0.5) - Mixes between distorted sampling and cell ID color
// Param4: Center Dot Size (Default: 0.2)

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mousePos = u.zoom_config.yz;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

    // Params
    let cellsScale = u.zoom_params.x * 20.0 + 4.0;
    let chaos = u.zoom_params.y;
    let colorMix = u.zoom_params.z;
    let dotSize = u.zoom_params.w * 0.1;
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let event = u.ripples[ri];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length(uv - event.xy) - age * 0.38) * 62.0);
    }

    // Aspect corrected coordinates for voronoi calculation
    let aspect = resolution.x / resolution.y;
    let st = vec2<f32>(uv.x * aspect, uv.y) * cellsScale;

    let i_st = floor(st);
    let f_st = fract(st);

    // ── Rescue R3: HEAD started the search at 1.0, but pushed seeds can all sit farther than
    // one cell from a pixel; the search then kept cell (0,0) and drew black holes (the arcs in HEAD).
    var m_dist = 8.0;
    var m_dist2 = 8.0;
    var m_diff1 = vec2<f32>(0.0);
    var m_diff2 = vec2<f32>(1.0, 0.0);
    var m_point = vec2<f32>(0.0);
    var m_sample = vec2<f32>(0.0);
    var m_id = vec2<f32>(0.0);

    // Search neighbors
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let id = i_st + neighbor;

            // Random point in cell
            var point = hash2(id);

            // Animate point
            // Base movement
            // ── Rescue R-phase: HEAD multiplied time by (0.5 + mids), so every mids change
            // jumped the phase by time*dMids radians (strobing). Time stays alone; mids
            // phase-modulates the swim with a bounded amplitude (identical at zero audio).
            point = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * point + audio.y * 1.2 * sin(time * 1.3 + 6.2831 * point.yx).x);

            // Mouse interaction: push points away from mouse
            if (mousePos.x >= 0.0) {
                 // Convert grid ID to UV space
                 var cellCenterUV = (id + point) / cellsScale;
                 cellCenterUV.x /= aspect; // revert aspect

                 let dToMouse = distance(cellCenterUV, mousePos);
                 let repulsion = smoothstep(0.5, 0.0, dToMouse) * chaos * (0.4 + held * 1.6);

                 // Shift point relative to cell center
                 point = point + vec2<f32>(sin(dToMouse * 20.0 - time * 5.0), cos(dToMouse * 20.0 - time * 5.0)) * repulsion;
            }

            // Tile colour is sampled where the shard IS (swim + pointer push), but not at the
            // 6 Hz bass-snap jump: the geometry snaps, the picture it carries does not flicker.
            let swumPoint = point;

            // Bass-snap shard jitter: on top of the continuous mouse repulsion
            // above, a bass transient gives cell points a brief discontinuous
            // snap (held for one ~1/6s beat window), proportional to chaos —
            // a percussive shatter-beat native to this file's own repulsion
            // mechanism rather than a new overlay.
            let snapSeed = hash2(id + floor(time * 6.0));
            let snapGate = step(0.82 - audio.x * 0.5, snapSeed.x);
            point = point + (snapSeed - 0.5) * snapGate * chaos * 0.5;

            // ── Idea 2: impact shatter. Each click is a front travelling out at 0.38 uv/s (the same
            // front the colour ring uses); seeds inside its band get a one-shot jolt along their own
            // hash direction, so a click tumbles the shards it crosses instead of only tinting them.
            var jolt = 0.0;
            let seedUV = vec2<f32>((id.x + swumPoint.x) / (cellsScale * aspect), (id.y + swumPoint.y) / cellsScale);
            for (var rj = 0u; rj < rippleCount; rj = rj + 1u) {
                let ev = u.ripples[rj];
                let evAge = time - ev.z;
                let live = step(0.0, evAge) * step(evAge, 2.5);
                let evBand = exp(-abs(length(seedUV - ev.xy) - max(evAge, 0.0) * 0.38) * 14.0);
                jolt = jolt + live * exp(-max(evAge, 0.0) * 1.8) * evBand;
            }
            let joltDir = (hash2(id + vec2<f32>(13.7, 4.1)) - 0.5) * 2.0;
            let joltVec = joltDir * min(jolt, 1.0) * (0.25 + chaos * 0.6);
            point = point + joltVec;
            let samplePoint = swumPoint + joltVec;

            let diff = neighbor + point - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist2 = m_dist;
                m_diff2 = m_diff1;
                m_diff1 = diff;
                m_dist = dist;
                m_point = point;
                m_sample = samplePoint;
                m_id = id;
            } else if (dist < m_dist2) {
                m_dist2 = dist;
                m_diff2 = diff;
            }
        }
    }

    // Now we have the closest point info (m_dist) and the cell ID (m_id)

    // Calculate color
    // 1. Distortion sampling
    // ── Rescue R2: HEAD re-derived the unperturbed seed (no pointer push, no snap) and sampled
    // the picture there, so a shard pushed by the cursor showed the photo from where it used to
    // be (the comment promised "re-apply mouse chaos"). Sample at the seed the loop actually used.
    let cellCenterGrid = m_id + m_sample;

    // Sampling at cell center (creating mosaic effect)
    let sampleUV_Grid = cellCenterGrid / cellsScale;
    let sampleUV = vec2<f32>(sampleUV_Grid.x / aspect, sampleUV_Grid.y);

    let colDistorted = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // 2. Cell Color (random)
    // ── Rescue R-phase: bass used to scale time (phase jumps); it now stretches the ring spatial
    // frequency instead, time keeps its fixed 3 rad/s.
    let ridge = sin(m_dist * (70.0 + chaos * 80.0) * (1.0 + audio.x * 0.12) - time * 3.0);
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + ridge * 2.0 + time + audio.z * 2.0);
    let colCell = vec4<f32>(mix(vec3<f32>(hash2(m_id), 0.5 + 0.5*sin(m_id.x)), spectral, 0.45), 1.0);

    // Mix
    var color = mix(colDistorted, colCell, colorMix * 0.35); // Keep mostly image by default
    color = color + vec4<f32>(spectral * (abs(ridge) * 0.08 + clickFront * 0.24), 0.0);

    // Add center dots
    var dotCoverage = 0.0;
    if (m_dist < dotSize) {
        color = mix(color, vec4<f32>(0.0, 0.0, 0.0, 1.0), 0.5);
        dotCoverage = 1.0;
    }

    // ── Idea 1: fracture seams. Worley F2 - F1 is the distance to the shard border; HEAD only
    // kept F1, so neighbouring tiles of similar colour merged with no crack between them.
    // Dark crack core + a thin lit lip just outside it; width grows with Chaos.
    let crackW = 0.03 + chaos * 0.05;
    // Plain F2 - F1 is only the border distance for far-apart seeds (close seed pairs give long
    // fuzzy wedges), so the gap is the true distance to the bisector of the two nearest seeds.
    let dSep = m_diff2 - m_diff1;
    let borderGap = max(dot(0.5 * (m_diff1 + m_diff2), dSep) / max(length(dSep), 1e-4), 0.0);
    let crack = 1.0 - smoothstep(0.0, crackW, borderGap);
    let lip = smoothstep(0.0, crackW, borderGap) * (1.0 - smoothstep(crackW, crackW * 2.4, borderGap));
    color = vec4<f32>(color.rgb * (1.0 - crack * 0.7) + spectral * lip * (0.14 + audio.z * 0.10), color.a);

    // Highlight cells near mouse
    if (mousePos.x >= 0.0) {
       var d = distance(sampleUV, mousePos);
       if (d < 0.1) {
           color = color + vec4<f32>(0.2, 0.2, 0.2, 0.0) * (1.0 - d * 10.0);
       }
    }

    // Held-pointer trail smear: exact dataTextureC history blended in while
    // the pointer is held, giving the chaos field a short trailing ghost
    // instead of the previously write-only/unused history buffer.
    let history = textureLoad(dataTextureC, clamp(vec2<i32>(global_id.xy), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1)), 0);
    color = vec4<f32>(mix(color.rgb, max(color.rgb, history.rgb * 0.92), held * 0.55), color.a);

    // Semantic alpha: ridge/shatter/dot coverage instead of the source
    // texture's near-opaque alpha.
    let alpha = clamp(0.5 + abs(ridge) * 0.22 + clickFront * 0.3 + dotCoverage * 0.25 + crack * 0.12, 0.0, 1.0);
    let finalColor = vec4<f32>(acesToneMap(max(color.rgb, vec3<f32>(0.0))), alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    // Pass depth
    var d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
