// ----------------------------------------------------------------
// Ethereal Neon-Bismuth Origami
// Category: generative
// Features: audio-reactive, mouse-driven, upgraded-rgba
// Upgraded: 2026-11-10, 2026-11-22
// Ideas: (1) hopper-crystal oxide terraces — stepped film thickness along
//        the hit depth gives bismuth's banded staircase iridescence;
//        (2) origami crease glow — normal discontinuity between neighbouring
//        surface points lights the folds in neon; (3) floor: ACES display,
//        coverage alpha, depth + dataTextureA writes;
//        2026-11-22: hopper stair-step rings that follow each cube facet
//        (Chebyshev inset of the folded cube); step-count ambient occlusion
//        (§12.2E) that darkens the recesses and thins the oxide film there;
//        rescues: pixel-centred uv (the centre row sat in the fold plane);
//        true rotation in the KIFS loop (HEAD sheared — see the loop comment).
// A packing: ACES display RGBA
// ----------------------------------------------------------------
#include "_prelude.wgsl"

// ----------------------------------------------------------------
// Shader Code
// ----------------------------------------------------------------

// 2D Rotation Matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Bismuth/Iridescent Color Palette based on Cosine Gradients
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.3, 0.20, 0.20);
    return a + b * cos(6.28318 * (c * t + d));
}

// Kaleidoscopic Iterated Function System (KIFS) for Bismuth geometry.
// x = distance, y = hopper inset of the facet this point sits on (0 at the
// facet rim, 1 at its centre), z = world spacing of one hopper step.
// `unfold` = bass breath added to the fold/unfold clock (0 = HEAD).
fn mapEx(p_in: vec3<f32>, time: f32, mouse_pos: vec3<f32>, unfold: f32) -> vec3<f32> {
    var p = p_in;

    // Mouse Interaction: Bloom effect
    let dist_to_mouse = length(p - mouse_pos);
    let bloom_factor = smoothstep(2.0, 0.0, dist_to_mouse) * u.zoom_params.y; // u.zoom_params.y is Bloom Strength

    let scale = 1.2 + sin(time * 0.5) * 0.1 + unfold + bloom_factor * 0.5;

    var d = 100.0;
    var inset = 0.0;
    var stepW = 0.0;

    // Iterative space folding
    for (var i = 0; i < 4; i = i + 1) {
        // Fold 1
        p = abs(p) - vec3<f32>(1.0, 1.0, 1.0) * u.zoom_params.x; // u.zoom_params.x is Scale

        // Rotate. RESCUE (2026-11-22): HEAD wrote `p.x = …; p.y = p.x*s + …`,
        // reusing the already-rotated component, so the map was a shear, not a
        // rotation: the SDF stopped being a distance bound and the folded cube
        // frames collapsed into slabs (plaid grid at many clock values). The
        // rotations below use both ORIGINAL components, as intended.
        let rxy = vec2<f32>(p.x * cos(time * 0.2) - p.y * sin(time * 0.2),
                            p.x * sin(time * 0.2) + p.y * cos(time * 0.2));
        p.x = rxy.x;
        p.y = rxy.y;

        let ryz = vec2<f32>(p.y * cos(time * 0.3) - p.z * sin(time * 0.3),
                            p.y * sin(time * 0.3) + p.z * cos(time * 0.3));
        p.y = ryz.x;
        p.z = ryz.y;

        // Scale
        p = p * scale;

        // Cube SDF
        let q = abs(p) - vec3<f32>(0.5);
        let current_d = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);

        // Min distance, scaled back
        let levelK = pow(scale, f32(-i - 1));
        let sd = current_d * levelK;

        // ── Idea 1: hopper stair-step rings ─────────────────────────────
        // q is this cube's own facet frame. On a face the largest component
        // is ~0 (the surface) and the MEDIAN component is minus the Chebyshev
        // distance to the nearest facet edge: the inset a hopper crystal
        // steps down by. Recorded only for the level that owns the surface.
        let qlo = min(q.x, min(q.y, q.z));
        let qhi = max(q.x, max(q.y, q.z));
        let qmed = q.x + q.y + q.z - qlo - qhi;
        let owns = sd < d;
        inset = select(inset, clamp(-qmed * 2.0, 0.0, 1.0), owns);
        stepW = select(stepW, 0.125 * levelK, owns);
        d = min(d, sd);
    }

    return vec3<f32>(d, inset, stepW);
}

// Distance only (march, normals, AO): the same fold loop as mapEx() without the
// hopper-inset bookkeeping, which only the single hit-point evaluation needs.
fn map(p_in: vec3<f32>, time: f32, mouse_pos: vec3<f32>, unfold: f32) -> f32 {
    var p = p_in;
    let dist_to_mouse = length(p - mouse_pos);
    let bloom_factor = smoothstep(2.0, 0.0, dist_to_mouse) * u.zoom_params.y;
    let scale = 1.2 + sin(time * 0.5) * 0.1 + unfold + bloom_factor * 0.5;
    let c1 = cos(time * 0.2); let s1 = sin(time * 0.2);
    let c2 = cos(time * 0.3); let s2 = sin(time * 0.3);
    var d = 100.0;
    var levelK = 1.0;
    for (var i = 0; i < 4; i = i + 1) {
        p = abs(p) - vec3<f32>(1.0, 1.0, 1.0) * u.zoom_params.x;
        let rxy = vec2<f32>(p.x * c1 - p.y * s1, p.x * s1 + p.y * c1);
        p.x = rxy.x;
        p.y = rxy.y;
        let ryz = vec2<f32>(p.y * c2 - p.z * s2, p.y * s2 + p.z * c2);
        p.y = ryz.x;
        p.z = ryz.y;
        p = p * scale;
        levelK = levelK / scale;
        let q = abs(p) - vec3<f32>(0.5);
        d = min(d, (length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0)) * levelK);
    }
    return d;
}

// Calculate normal using finite differences
fn getNormal(p: vec3<f32>, time: f32, mouse_pos: vec3<f32>, unfold: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, mouse_pos, unfold) - map(p - e.xyy, time, mouse_pos, unfold),
        map(p + e.yxy, time, mouse_pos, unfold) - map(p - e.yxy, time, mouse_pos, unfold),
        map(p + e.yyx, time, mouse_pos, unfold) - map(p - e.yyx, time, mouse_pos, unfold)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    // Normalized coordinates (-1 to 1). Pixel-centred: with integer pixel
    // coordinates the centre row had uv.y == 0 exactly, so its ray lay IN the
    // abs() fold plane y = 0 and the crease glow fired along the whole row.
    let uv = (vec2<f32>(id.xy) + 0.5 - 0.5 * resolution) / resolution.y;

    let time = u.config.x * u.zoom_params.w; // u.zoom_params.w is Time Speed

    // Audio: bass breathes the fold/unfold clock, treble lifts the crease neon.
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let unfold = bass * 0.06;

    // Mouse coordinates mapped to 3D space
    var mouse_uv = u.zoom_config.yz;
    if (u.zoom_config.w < 0.5) {
        // Default to center if mouse not pressed
        mouse_uv = vec2<f32>(0.5, 0.5);
    }
    let mouse_pos = vec3<f32>((mouse_uv - 0.5) * 4.0, 0.0);

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -3.0); // Ray origin (camera)
    let rd = normalize(vec3<f32>(uv, 1.0)); // Ray direction

    var p = ro;
    var t = 0.0;
    var i = 0.0;
    var glow = 0.0;

    // Raymarching loop
    for (i = 0.0; i < 100.0; i = i + 1.0) {
        let d = map(p, time, mouse_pos, unfold);
        if (d < 0.001 || t > 10.0) {
            break;
        }
        t = t + d;
        p = ro + rd * t;

        // Volumetric glow accumulation
        glow = glow + 0.02 / (0.1 + d);
    }

    var col = vec3<f32>(0.0);

    if (t < 10.0) {
        // We hit the surface
        let n = getNormal(p, time, mouse_pos, unfold);

        // ── Idea 2 (2026-11-22): step-count ambient occlusion (§12.2E) ──
        // Five taps of the file's own map() along the normal: how much of
        // the neighbourhood is closer than the free distance. The recesses
        // between shards (a hopper crystal's hollow faces) read dark.
        var occ = 0.0;
        var occW = 1.0;
        for (var j = 1; j <= 5; j = j + 1) {
            let h = 0.01 + 0.12 * f32(j) / 5.0;
            occ = occ + (h - map(p + n * h, time, mouse_pos, unfold)) * occW;
            occW = occW * 0.5;
        }
        let ao = clamp(1.0 - 5.0 * occ, 0.0, 1.0);

        // Lighting
        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let view_dir = normalize(ro - p);

        // Thin-film interference (iridescence) based on viewing angle
        let fresnel = 1.0 - max(dot(n, view_dir), 0.0);
        // Idea 1: hopper terraces — film thickness is quantised into steps.
        let terraceCoord = (p.z + p.x * 0.35) * 9.0;
        let terrace = floor(terraceCoord) / 9.0;
        let riser = smoothstep(0.85, 1.0, fract(terraceCoord));
        // Idea 2 (2026-11-22): the oxide film is thinner in the recesses
        // than on the exposed rims, so occlusion slides the film phase.
        col = palette(fresnel * u.zoom_params.z + terrace * 1.7 + time * 0.1 + (1.0 - ao) * 0.18); // u.zoom_params.z is Iridescence Rate
        col = col * (1.0 - riser * 0.35);

        col = col * (diff * 0.8 + 0.2); // Apply diffuse lighting
        col = col * mix(0.4, 1.0, ao);   // Idea 2: recess occlusion

        // ── Idea 1 (2026-11-22): hopper stair-step rings ────────────────
        // Concentric rectangular steps that follow EACH facet (the world-axis
        // terraces above ignore the facets). Rim is highest, centre lowest:
        // every step down is a little darker, each riser is shadowed and each
        // lip catches light. Faded when a step is < ~2 px wide (anti-moire).
        let ex = mapEx(p, time, mouse_pos, unfold);
        let ringCoord = ex.y * 4.0;
        let stair = floor(ringCoord) / 4.0;
        let ringRiser = smoothstep(0.78, 1.0, fract(ringCoord));
        let ringLip = 1.0 - smoothstep(0.0, 0.14, fract(ringCoord));
        let footprint = max(t, 0.05) * 2.0 / resolution.y;
        let ringVis = smoothstep(1.0, 3.0, ex.z / footprint);
        let ringShade = mix(1.0, (1.0 - stair * 0.4) * (1.0 - ringRiser * 0.55), ringVis);
        col = col * ringShade;
        col = col + vec3<f32>(0.85, 0.95, 1.0) * ringLip * 0.16 * (0.3 + diff) * ringVis;

        // Edge highlighting (neon effect)
        let edge = smoothstep(0.4, 0.5, fract(p.x * 5.0)) + smoothstep(0.4, 0.5, fract(p.y * 5.0));
        col = col + vec3<f32>(0.2, 0.8, 1.0) * edge * 0.5;

        // Idea 2: origami crease glow — compare normals across a small step.
        let tang = normalize(cross(n, vec3<f32>(0.0, 1.0, 0.0001)));
        let n2 = getNormal(p + tang * 0.03, time, mouse_pos, unfold);
        let crease = clamp((1.0 - dot(n, n2)) * 6.0, 0.0, 1.0);
        col = col + vec3<f32>(1.0, 0.3, 0.85) * crease * 0.8 * (1.0 + 0.5 * treble);

    }

    // Add volumetric glow
    col = col + vec3<f32>(0.8, 0.2, 0.9) * glow * 0.05;

    // ACES display tone map, then gamma correction (kept).
    col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    let hit = select(0.0, 1.0, t < 10.0);
    let alpha = clamp(hit + glow * 0.04, 0.0, 1.0);
    let outC = vec4<f32>(col, alpha);
    textureStore(writeTexture, id.xy, outC);
    textureStore(dataTextureA, id.xy, outC);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(select(0.0, 1.0 - t / 10.0, t < 10.0), 0.0, 0.0, 0.0));
}
