// ═══════════════════════════════════════════════════════════════════
//  Crystalline Pulse — UPGRADED
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven, crystalline, diamond-lattice, phonon
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-06-07
//  Upgraded: 2026-11-08
//  Ideas: pyramidal facet shading; phonon wavefront sweep; Laue diffraction glints
//  A packing: display RGBA (ACES), alpha = crystal presence
//  Wolfram Data: Bravais lattice (FCC), diamond structure, phonon ω = 2√(k/m)|sin(ka/2)|
//  By: Kimi Agent
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash12(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    return fract((p3.x + p3.y) * p3.z + (p3.x * p3.y) * 0.5);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash22(i).x;
    let b = hash22(i + vec2<f32>(1.0, 0.0)).x;
    let c = hash22(i + vec2<f32>(0.0, 1.0)).x;
    let d = hash22(i + vec2<f32>(1.0, 1.0)).x;
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * vnoise2(p * freq);
        freq *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Voronoi cell helper (returns cell center + distance)
fn voronoi(p: vec2<f32>) -> vec4<f32> {
    let n = floor(p);
    let f = fract(p);
    var minDist = 1.0;
    var cellId = vec2<f32>(0.0);
    var toC = vec2<f32>(0.0);
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let g = vec2<f32>(f32(x), f32(y));
            let o = hash22(n + g);
            let r = g + o - f;
            let d = dot(r, r);
            if (d < minDist) {
                minDist = d;
                cellId = n + g + o;
                toC = r;
            }
        }
    }
    return vec4<f32>(sqrt(minDist), hash12(cellId), toC);
}

// ═══ CHUNK: Bravais lattice / diamond cubic (Wolfram Alpha crystallography) ═══
// Cubic: a=b=c, α=β=γ=90°
// FCC: atoms at corners + face centers → in 2D projection: (i+j)%2 == 0
// Diamond: FCC with basis at (0,0,0) and (1/4,1/4,1/4)
// Phonon frequency: ω = 2√(k/m) |sin(ka/2)| — acoustic branch
fn diamondLattice(uv: vec2<f32>, scale: f32, time: f32, omega: f32) -> f32 {
    let p = uv * scale;
    let ip = floor(p);
    let fp = fract(p);

    // FCC lattice: only even parity sites are occupied
    let fcc = select(0.0, 1.0, (i32(ip.x) + i32(ip.y)) % 2 == 0);

    // Diamond basis: second atom offset by (0.25, 0.25)
    let bp = fp - vec2<f32>(0.25, 0.25);
    let diamond = fcc * (1.0 - smoothstep(0.0, 0.15, length(bp - 0.5)));

    // Phonon wave: sin(dot(k, pos) - ω * time)
    let k = vec2<f32>(1.0, 0.7);
    let phonon = sin(dot(k, p) - omega * time) * 0.5 + 0.5;

    return diamond * phonon;
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 0.9);
    let d = vec3<f32>(0.55, 0.66, 0.77);
    return a + b * cos(TAU * (c * t + d));
}

fn edgeGlow(d: f32, thickness: f32) -> f32 {
    return smoothstep(thickness, 0.0, d) - smoothstep(0.0, -thickness, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel = vec2<i32>(id.xy);
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let texel = vec2<f32>(id.xy);
    let uv = texel / dims;

    let t = u.config.x;
    let mouseDown = u.zoom_config.w;
    let mouse = u.zoom_config.yz;

    // Audio reads from plasmaBuffer
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let overall = (bass + mids + treble) / 3.0;

    let density = u.zoom_params.x;
    let shardSize = u.zoom_params.y;
    let glow = u.zoom_params.z;
    let chaos = u.zoom_params.w;

    var p = (uv - 0.5) * 2.0;
    let aspect = dims.x / dims.y;
    p.x *= aspect;

    var mousePos = (mouse - 0.5) * 2.0;
    mousePos.x *= aspect;
    let mDist = length(p - mousePos);
    let mouseInfluence = exp(-mDist * 4.0) * mouseDown;

    // Crystal grid: voronoi cells with time-evolving centers
    let gridScale = 3.0 + density * 5.0;
    var gp = p * gridScale;

    // Mouse defect: displaces nearest lattice site
    if (mouseDown > 0.5) {
        let pushDir = normalize(gp - mousePos * gridScale);
        gp += pushDir * mouseInfluence * 2.0;
    }

    // Add chaos drift
    gp += vec2<f32>(
        fbm(gp + t * 0.05, 3) * chaos,
        fbm(gp + t * 0.07 + 100.0, 3) * chaos
    );

    let voro = voronoi(gp);
    let cellDist = voro.x;
    let cellHash = voro.y;

    // ═══ Wolfram enrichment: diamond lattice + phonon pulse ═══
    // Bass drives phonon frequency ω
    let kSpring = 1.0;
    let mass = 1.0;
    let latticeSpacing = 1.0;
    // ω = 2 * sqrt(k/m) * |sin(k*a/2)|
    let omega = 2.0 * sqrt(kSpring / mass) * abs(sin(latticeSpacing * 0.5));
    let bassOmega = omega * (1.0 + bass * 3.0);

    // Diamond cubic diffraction pattern overlay
    let diamondPattern = diamondLattice(p, gridScale * 0.5, t, bassOmega);

    // Crystal shape: faceted interior
    let crystalEdge = smoothstep(0.0, 0.3 + shardSize * 0.2, cellDist);
    let crystalInterior = 1.0 - crystalEdge;

    // Growth pulse from bass + phonon
    let growth = sin(cellHash * TAU + t * 0.5 + bass * 3.0) * 0.5 + 0.5;
    let crystalSize = crystalInterior * (0.5 + growth * 0.5);

    // Idea 1 — pyramidal facet shading: each crystal is a 5–7 sided pyramid;
    // the facet is the angular sector of the offset to its site, lit from upper-left.
    let rv = -voro.zw;
    let nFacets = 5.0 + floor(cellHash * 3.0);
    let sectorF = (atan2(rv.y, rv.x) + PI) / TAU * nFacets + cellHash * 7.0;
    let sector = floor(sectorF);
    let ridge = smoothstep(0.82, 1.0, abs(fract(sectorF) - 0.5) * 2.0);
    let facetAng = (sector + 0.5) / nFacets * TAU + cellHash * 2.0;
    let facetN = normalize(vec3<f32>(cos(facetAng) * 0.6, sin(facetAng) * 0.6, 1.0));
    let lightDir = normalize(vec3<f32>(-0.5, -0.6, 0.65));
    let facetLit = 0.12 + 1.15 * pow(max(dot(facetN, lightDir), 0.0), 3.0);

    // Idea 2 — phonon wavefront sweep: the acoustic wave along k is drawn as a
    // travelling compression front that lights crystals as it passes (idle-visible).
    let kDir = normalize(vec2<f32>(1.0, 0.7));
    let frontPhase = fract(dot(p, kDir) * 0.35 - t * 0.08 * (1.0 + bass * 1.5));
    let front = exp(-pow((frontPhase - 0.5) * 18.0, 2.0)) * (0.6 + mids * 0.6);

    // Color per cell with hue rotation from mids
    let colorT = cellHash + t * 0.02 + mids * 0.3;
    var col = palette(colorT);

    // Interior depth gradient
    col *= 0.6 + crystalSize * 0.4;
    let facetMask = smoothstep(0.05, 0.4, crystalInterior);
    col *= mix(1.0, facetLit, facetMask);
    col += vec3<f32>(0.7, 0.9, 1.0) * ridge * facetMask * 0.35 * (0.5 + glow);
    col += vec3<f32>(0.2, 0.5, 1.0) * front * (crystalInterior * 0.8 + 0.06);

    // Edge glow
    let edge = edgeGlow(cellDist - 0.15, 0.03 + glow * 0.05);
    col += edge * vec3<f32>(0.4, 0.7, 1.0) * glow * (1.0 + treble * 2.0);

    // Treble refraction sparkles at crystal edges
    let sparkle = hash12(floor(p * 120.0 + t * 0.01));
    let sparkleGlow = smoothstep(0.98, 1.0, sparkle) * treble * 3.0 * edge;
    col += vec3<f32>(0.8, 0.9, 1.0) * sparkleGlow;

    // Idea 3 — Laue diffraction glints: when the wavefront crosses a crystal,
    // its site flashes a 6-spot reciprocal-lattice star (hex Bragg spots).
    let rr = length(rv);
    let ang6 = atan2(rv.y, rv.x) * 3.0 + cellHash * TAU;
    let spokes = pow(abs(cos(ang6)), 24.0);
    let spotR = 0.18 + shardSize * 0.08;
    let spots = spokes * exp(-pow((rr - spotR) * 22.0, 2.0));
    let core = exp(-rr * rr * 260.0);
    let laue = (spots + core) * (0.25 + front * 1.6 + treble * 0.8) * step(0.55, cellHash + front * 0.4);
    col += vec3<f32>(0.85, 0.95, 1.0) * laue * (0.6 + glow * 0.8);

    // Diamond lattice phonon overlay
    col += vec3<f32>(0.3, 0.6, 0.9) * diamondPattern * bass * 0.5;

    // Bass pulse: whole scene brightens on beats
    col *= 1.0 + bass * 0.3;

    // Mouse disruption glow
    if (mouseDown > 0.5) {
        let disruptGlow = exp(-mDist * 3.0) * 0.4;
        col += vec3<f32>(0.2, 0.6, 1.0) * disruptGlow;
    }

    // Background: dark space between crystals
    let bg = 0.05 + 0.02 * fbm(p * 2.0 + t * 0.01, 3);
    col = mix(vec3<f32>(bg, bg, bg * 1.2), col, clamp(crystalSize + edge * 0.3 + laue * 0.5, 0.0, 1.0));

    // Vignette
    let vig = 1.0 - smoothstep(0.5, 1.5, length(p));
    col *= vig;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // Temporal feedback
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    col = mix(prev.rgb * 0.96, col, 0.25);

    // ACES tone map + semantic alpha
    col = acesToneMap(col * 1.1);
    let alpha = clamp(length(col) * 1.2, 0.2, 0.95);

    let outColor = vec4<f32>(col * (0.8 + overall * 0.2), alpha);
    textureStore(writeTexture, pixel, outColor);
    textureStore(dataTextureA, pixel, outColor);
    textureStore(writeDepthTexture, pixel, vec4<f32>(crystalSize, 0.0, 0.0, 1.0));
}
