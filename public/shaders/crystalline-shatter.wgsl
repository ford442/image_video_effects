// ═══════════════════════════════════════════════════════════════════
//  Crystalline Shatter
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba, semantic-alpha
//  Complexity: Medium-High
//  Upgraded: 2026-10-05
//  Ideas: facet tilt Fresnel + light flash; conchoidal ribs; stress-line crack branching
//  A packing: ACES display RGBA (C not read)
// ═══════════════════════════════════════════════════════════════════
//  Voronoi cell decomposition gives each fragment an independent
//  refraction vector and chromatic offset, making the image look
//  shattered into crystal facets. Bass branches new hairline cracks;
//  the shatter amount is also mouse-proximity-driven.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=CellScale, y=Refraction, z=ChromaticAberration, w=EdgeGlow

fn hash2f(p: vec2<f32>) -> vec2<f32> {
    let k = vec2<f32>(0.3183099, 0.3678794);
    let x = p * k + k.yx;
    return fract(16.0 * k * fract(x.x * x.y * (x.x + x.y))) * 2.0 - 1.0;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

struct Vor {
    d1: f32,          // distance to nearest site
    edge: f32,        // d2 - d1 (closeness to cell boundary)
    cell: f32,        // unique hash per cell
    rel: vec2<f32>,   // pixel position relative to the nearest site (cell units)
};

// Voronoi: nearest dist, edge dist, cell-id hash, offset from site
fn voronoi(uv: vec2<f32>) -> Vor {
    let i = floor(uv);
    let f = fract(uv);

    var minDist1 = 8.0;
    var minDist2 = 8.0;
    var cellHash  = 0.0;
    var nearestPoint = vec2<f32>(0.0);

    for (var y = -2; y <= 2; y++) {
        for (var x = -2; x <= 2; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point    = hash2f(i + neighbor) * 0.5 + neighbor + 0.5;
            let d        = length(point - f);
            if (d < minDist1) {
                minDist2    = minDist1;
                minDist1    = d;
                nearestPoint = point;
                cellHash     = fract(sin(dot(i + neighbor, vec2<f32>(127.1, 311.7))) * 43758.5453);
            } else if (d < minDist2) {
                minDist2 = d;
            }
        }
    }
    // edge distance = distance difference between nearest and second nearest
    return Vor(minDist1, minDist2 - minDist1, cellHash, f - nearestPoint);
}

// Idea 3 helper: cheap 3x3 Voronoi edge distance for the hairline branch layer
fn voronoiEdge3(uv: vec2<f32>) -> f32 {
    let i = floor(uv);
    let f = fract(uv);
    var m1 = 8.0;
    var m2 = 8.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let nb = vec2<f32>(f32(x), f32(y));
            let p  = hash2f(i + nb + vec2<f32>(17.0, 59.0)) * 0.5 + nb + 0.5;
            let d  = length(p - f);
            if (d < m1) { m2 = m1; m1 = d; } else if (d < m2) { m2 = d; }
        }
    }
    return m2 - m1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;

    // Audio (plasmaBuffer[0] = bass / mids / treble)
    let audio  = plasmaBuffer[0];
    let bass   = audio.x;
    let mid    = audio.y;
    let treble = audio.z;

    // Params
    let cellScale  = mix(4.0, 25.0, u.zoom_params.x) * (1.0 + bass * 0.5);
    let refraction = mix(0.0, 0.06,  u.zoom_params.y);
    let chromatic  = mix(0.0, 0.012, u.zoom_params.z);
    let edgeGlow   = mix(0.0, 1.0,   u.zoom_params.w);

    // Mouse proximity increases shatter
    let mouse      = u.zoom_config.yz;
    let mouseDist  = length(uv - mouse);
    let mouseStr   = 1.0 - smoothstep(0.0, 0.5, mouseDist);

    let vor = voronoi(uv * cellScale);
    let cell     = vor.cell;     // unique hash per cell
    let edgeDist = vor.edge;     // closeness to cell boundary

    // Per-cell refraction direction (random vector per cell)
    let refVec = hash2f(vec2<f32>(cell * 113.0, cell * 47.0));
    let refStr = refraction * (1.0 + mouseStr * 2.0) * (1.0 + bass * 1.5);

    // Idea 2: Conchoidal ribs — concentric fracture ripples around each facet's
    // origin (its Voronoi site), widening outward (sqrt spacing) and strongest
    // toward the crack walls; they nudge the refraction radially.
    let r        = length(vor.rel);
    let radial   = vor.rel / max(r, 1e-4);
    let ribPhase = sqrt(r) * 46.0 - cell * 37.0;
    let ribs     = sin(ribPhase);
    let wallW    = 1.0 - smoothstep(0.0, 0.35, edgeDist);
    let ribAmt   = ribs * (0.35 + 0.65 * wallW);

    // 0.04: keeps the rib displacement slope below ~0.5 at rest (0.12 folded
    // the photo over itself on ~17 px rib periods).
    let baseUV = uv + refVec * refStr + radial * ribAmt * refStr * 0.04;

    // Chromatic aberration: sample R/G/B at slightly offset UVs
    let caDir = normalize(refVec + vec2<f32>(0.0001));
    let rUV = clamp(baseUV + caDir * chromatic,        vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(baseUV,                             vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(baseUV - caDir * chromatic,        vec2<f32>(0.0), vec2<f32>(1.0));

    let r_ = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let gS = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let b_ = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let a  = gS.a;

    var col = vec3<f32>(r_, gS.g, b_);
    // rib shading (~3%): the ripple crests catch a little more light
    col = col * (1.0 + ribAmt * 0.03 * smoothstep(0.0, 0.2, u.zoom_params.y));

    // Idea 1: Facet tilt Fresnel + light flash — refVec is the facet's slope, so
    // build a flat tilted normal from it (tilt follows the Refraction slider).
    let tilt   = 0.5 + 1.6 * u.zoom_params.y;
    let nrm    = normalize(vec3<f32>(refVec * tilt, 1.0));
    let viewV  = normalize(vec3<f32>((uv - 0.5) * 0.6, 1.0));
    let cosT   = clamp(dot(nrm, viewV), 0.0, 1.0);
    // Schlick-style Fresnel (stylised exponent 3 so grazing facets read)
    let fres   = 0.04 + 0.96 * pow(1.0 - cosT, 3.0);
    let reflUV = clamp(uv + nrm.xy * 0.22, vec2<f32>(0.0), vec2<f32>(1.0));
    let envC   = textureSampleLevel(readTexture, u_sampler, reflUV, 0.0).rgb;
    let envL   = dot(envC, vec3<f32>(0.299, 0.587, 0.114));
    let envRef = mix(vec3<f32>(envL), envC, 0.4) * vec3<f32>(0.85, 0.95, 1.1);
    col = mix(col, envRef, clamp(fres, 0.0, 0.45));
    // slow sweeping key light: whole flat facets flash when aligned
    let lightL = normalize(vec3<f32>(cos(time * 0.37) * 0.55, sin(time * 0.29) * 0.55, 1.0));
    let halfV  = normalize(lightL + viewV);
    let flash  = pow(max(dot(nrm, halfV), 0.0), 90.0);
    col = col + vec3<f32>(1.0, 0.98, 0.94) * flash * 0.45 * (1.0 + treble * 1.5)
              * smoothstep(0.0, 0.15, u.zoom_params.y);

    // Edge crack lines: bright and slightly tinted
    let edgeMask  = (1.0 - smoothstep(0.0, 0.04, edgeDist)) * edgeGlow;
    let crackTint = vec3<f32>(0.9, 0.95, 1.0) * (1.0 + treble);
    let glintPulse = 0.4 + 0.6 * sin(cell * 314.1 + time * 3.0 + bass * 5.0);
    col = mix(col, crackTint * glintPulse, edgeMask);

    // Idea 3: Stress-line branching — finer hairline cracks that only grow close
    // to the primary cracks, in a hashed subset of cells; bass widens the subset.
    let branchEdge = voronoiEdge3(uv * cellScale * 3.0);
    let hair       = 1.0 - smoothstep(0.0, 0.035, branchEdge);
    let nearCrack  = 1.0 - smoothstep(0.02, 0.32, edgeDist);
    let branchSel  = step(fract(cell * 7.31), 0.45 + bass * 0.4);
    let branchMask = hair * nearCrack * branchSel * edgeGlow;
    col = mix(col, crackTint * (0.55 + 0.35 * glintPulse), branchMask * 0.55);

    // Slight iridescent tint on facet interior based on cell hash + time
    let iriAngle = cell * 6.28318 + time * 0.3;
    let iri      = vec3<f32>(
        0.5 + 0.5 * cos(iriAngle),
        0.5 + 0.5 * cos(iriAngle + 2.094),
        0.5 + 0.5 * cos(iriAngle + 4.189)
    );
    col = mix(col, col * iri * 1.2, 0.12 * (1.0 + mid));

    // Semantic alpha: source coverage, cracks (incl. branches) raise it
    let alpha = clamp(a + (edgeMask + branchMask * 0.5) * 0.5, 0.0, 1.0);

    let display  = aces(clamp(col, vec3<f32>(0.0), vec3<f32>(1.5)));
    let outColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    // Depth: source depth with a truthful facet relief (tilted plane + crack groove)
    let srcDepth = textureLoad(readDepthTexture, coord, 0).r;
    let facetH   = dot(nrm.xy, vor.rel) * 0.04;
    let groove   = (1.0 - smoothstep(0.0, 0.04, edgeDist)) * 0.06;
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(srcDepth + facetH - groove, 0.0, 1.0), 0.0, 0.0, 0.0));
}
