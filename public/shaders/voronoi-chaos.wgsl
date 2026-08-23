// ═══════════════════════════════════════════════════════════════════════════════
//  Voronoi Chaos — Agitated Cellular Refraction
//  Category: distortion
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-cell-fft-bands, edge-refraction, chromatic-dispersion,
//            temporal-seam-glow, depth-aware, upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 56 — Turbulent Vortex)
// ═══════════════════════════════════════════════════════════════════════════════
//  The original shader found only the nearest cell centre (F1) and sampled the
//  image there, which gives a flat mosaic. Two structures replace that:
//
//    1. F1/F2 seam field — the second-nearest centre is tracked as well, so the
//       true cell border distance is available. Seams are shaded as bevelled
//       glass edges, and the seam normal refracts the image sample, so each cell
//       behaves like a facet of cracked glass instead of a flat colour patch.
//
//    2. Per-cell FFT bands — every cell is assigned one of the 8 spectrum bins
//       (plasmaBuffer[1..8].x) from its own ID hash. The cell's agitation,
//       brightness and seam width follow that band, so the mosaic breaks up
//       frequency by frequency rather than pulsing as a single mass.
//
//  Fixed in this pass: the closest cell's UV is now carried out of the search
//  loop, so the mouse agitation is included in the sample position. Previously
//  the sample point was recomputed WITHOUT the repulsion term, which made cells
//  near the pointer sample the wrong part of the image. Bounds guarding, ACES,
//  semantic alpha and dataTextureC seam persistence are also new here.
//
//  Param1: Cell Size · Param2: Chaos Amount · Param3: Color Mix · Param4: Dot Size
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=CellSize, y=Chaos, z=ColorMix, w=DotSize
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Spectrum bin owned by a cell, picked deterministically from its grid ID.
fn cellBand(id: vec2<f32>) -> f32 {
    let idx = u32(hash2(id + 17.0).x * 8.0) % 8u;
    return plasmaBuffer[idx + 1u].x;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dims);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let held = step(0.5, u.zoom_config.w);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Params ───────────────────────────────────────────────────────────────
    let cellsScale = u.zoom_params.x * 20.0 + 4.0;
    let colorMix = u.zoom_params.z;
    let dotSize = u.zoom_params.w * 0.1;

    // ── Bounded click shatter pulses ─────────────────────────────────────────
    // A click sends an expanding front that temporarily multiplies the local
    // agitation, so the mosaic visibly cracks apart and settles again.
    var shatter = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.2) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            let front = rDist - age * 0.5;
            shatter += exp(-front * front * 180.0) * exp(-age * 1.6);
        }
    }
    shatter = min(shatter, 1.5);

    let chaos = u.zoom_params.y * (1.0 + bass * 0.5 + held * 0.4) + shatter * 0.8;

    // ── F1 / F2 cellular search ──────────────────────────────────────────────
    let st = vec2<f32>(uv.x * aspect, uv.y) * cellsScale;
    let i_st = floor(st);
    let f_st = fract(st);

    var m_dist = 8.0;      // F1
    var m_dist2 = 8.0;     // F2
    var m_diff = vec2<f32>(0.0);
    var m_id = vec2<f32>(0.0);
    var m_cellUV = uv;
    var m_band = 0.0;

    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let id = i_st + neighbor;

            var point = hash2(id);
            point = 0.5 + 0.5 * sin(time * 0.5 + TAU * point);

            // Per-cell band drives an extra jitter, so the tessellation itself
            // dances with the spectrum rather than only changing colour.
            let band = cellBand(id);
            point += vec2<f32>(sin(time * 2.1 + id.x), cos(time * 1.7 + id.y)) * band * 0.18;

            // Pointer repulsion, aspect-corrected in UV space.
            var cellCenterUV = (id + point) / cellsScale;
            cellCenterUV.x /= aspect;
            let dToMouse = distance(cellCenterUV * vec2<f32>(aspect, 1.0),
                                    mousePos * vec2<f32>(aspect, 1.0));
            let repulsion = smoothstep(0.5, 0.0, dToMouse) * chaos;
            point += vec2<f32>(sin(dToMouse * 20.0 - time * 5.0),
                               cos(dToMouse * 20.0 - time * 5.0)) * repulsion;

            let diff = neighbor + point - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist2 = m_dist;
                m_dist = dist;
                m_diff = diff;
                m_id = id;
                m_band = band;
                // Carry the AGITATED centre out of the loop — this is the fix
                // for the mouse-repulsion sampling mismatch.
                var c = (id + point) / cellsScale;
                c.x /= aspect;
                m_cellUV = c;
            } else if (dist < m_dist2) {
                m_dist2 = dist;
            }
        }
    }

    // Border distance: half the gap between the two nearest centres.
    let edge = (m_dist2 - m_dist) * 0.5;
    let seamWidth = 0.035 + m_band * 0.05 + shatter * 0.04;
    let seam = 1.0 - smoothstep(0.0, seamWidth, edge);

    // ── Structure 1: seam-normal refraction ──────────────────────────────────
    // The direction toward the cell centre acts as the facet normal; the sample
    // point is pushed along it near the seam, bending the image at every border.
    let facetN = normalize(m_diff + vec2<f32>(1e-6));
    let refractAmt = seam * (0.006 + chaos * 0.012);
    let baseUV = m_cellUV + facetN * refractAmt;

    // Chromatic dispersion across the facet edge — glass, not plastic.
    let disp = (0.0015 + treble * 0.006) * seam * (1.0 + shatter);
    let cR = textureSampleLevel(readTexture, u_sampler, baseUV + facetN * disp, 0.0);
    let cG = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);
    let cB = textureSampleLevel(readTexture, u_sampler, baseUV - facetN * disp, 0.0);
    let colDistorted = vec3<f32>(cR.r, cG.g, cB.b);

    // ── Cell tint ────────────────────────────────────────────────────────────
    let idHash = hash2(m_id);
    let colCell = vec3<f32>(idHash, 0.5 + 0.5 * sin(m_id.x));
    var color = mix(colDistorted, colCell, colorMix * 0.2);

    // The cell's own band lights it from within.
    color *= 1.0 + m_band * 0.8 * (1.0 + mids * 0.5);

    // Bevelled seam: dark groove with a bright specular lip.
    color = mix(color, color * 0.25, seam * 0.7);
    color += vec3<f32>(0.85, 0.92, 1.0) * pow(seam, 6.0) * (0.5 + treble * 1.2);

    // Centre dots.
    color = mix(color, vec3<f32>(0.0), 0.5 * step(m_dist, dotSize));

    // Pointer halo.
    let dMouse = distance(m_cellUV * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));
    color += vec3<f32>(0.2, 0.22, 0.3) * smoothstep(0.12, 0.0, dMouse) * (1.0 + held);

    // ── Temporal seam glow ───────────────────────────────────────────────────
    // Seam energy is stored in the display buffer's history and decays, so the
    // cracks leave a fading trace as the tessellation reorganises.
    let prev = textureLoad(dataTextureC, coord, 0);
    color = max(color, prev.rgb * (0.82 - m_band * 0.1));

    color += vec3<f32>(1.0, 0.6, 0.35) * shatter * 0.4;
    color = acesFilm(color);

    // ── Semantic alpha ───────────────────────────────────────────────────────
    // Cell interiors keep the source alpha; seams and shatter fronts are the
    // structural content and stay opaque.
    let alpha = clamp(mix(cG.a, 1.0, max(seam, shatter * 0.6)) * 0.9 + 0.1, 0.0, 1.0);
    let outColor = vec4<f32>(color, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    // Depth: cells sit slightly proud of their seams.
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(d * (1.0 - seam * 0.08), 0.0, 0.0, 0.0));
}
