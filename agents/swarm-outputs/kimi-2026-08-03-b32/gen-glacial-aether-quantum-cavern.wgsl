// ═══════════════════════════════════════════════════════════════════
//  Glacial-Aether Quantum-Cavern
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-depth,
//            temporal-ice-formation, audio-fracture, bass-fog,
//            faceted-ice-sdf, sdf-normals, 3-point-lighting, fresnel-rim,
//            thin-film-iridescence, per-facet-glints, frost-tessellation
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-08-03 — Visualist b32 (octahedral facet SDF, SDF normals,
//            3-point lighting + Fresnel, material IDs, frost inlay, thin-film)
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ─── Geometry helpers ───
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}

fn hash31(p: vec3<f32>) -> f32 {
    var q = fract(p * 0.1031);
    q += dot(q, q.yzx + vec3<f32>(33.33));
    return fract((q.x + q.y) * q.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Thin-film interference palette for ice-shell iridescence
fn thinFilm(cosV: f32, thickness: f32) -> vec3<f32> {
    let phase = thickness * 7.0 * (1.0 - cosV);
    return 0.5 + 0.5 * cos(phase + vec3<f32>(0.0, 2.0943951, 4.1887902));
}

// Faceted ice-crystal SDF: sphere-fold fractal intersected with octahedral
// prisms; material id in .y (0 = ice wall, 1 = crystal facet, 2 = plasma vein)
fn mapCavern(p: vec3<f32>, bass: f32) -> vec2<f32> {
    var q = p;
    var scale = 1.0;
    let cavernScale = u.zoom_params.w * (1.0 + bass * 0.3);
    for (var i = 0; i < 4; i++) {
        q = abs(q) - vec3<f32>(1.0) * cavernScale;
        let qxy = q.xy * rotate(u.config.x * (0.1 + u.zoom_params.z * 0.35) + bass * 0.25);
        q = vec3<f32>(qxy.x, qxy.y, q.z);
        let qxz = q.xz * rotate(u.config.x * 0.15);
        q = vec3<f32>(qxz.x, q.y, qxz.y);
        q = q * 1.4;
        scale = scale * 1.4;
    }
    let inv = 1.0 / max(scale, 0.001);
    let iceR = max(u.zoom_params.x * 2.0, 0.001);
    let sphereD = (length(q) - iceR) * inv;
    let octD = sdOctahedron(q, iceR * 1.22) * inv;
    // Ice Density also sharpens the faceting (0.1 → rounded, 1.0 → hard crystal)
    let facetMix = mix(0.3, 0.9, clamp(u.zoom_params.x, 0.0, 1.0));
    let crystalD = mix(sphereD, max(sphereD, octD), facetMix);
    // Plasma veins: thin emissive shells nested inside the crystal
    let vein = abs(sphereD + 0.06) - 0.014;
    let d = min(crystalD, vein);
    var matId = select(0.0, 1.0, octD > sphereD);
    matId = select(matId, 2.0, vein < crystalD);
    return vec2<f32>(d, matId);
}

fn mapDist(p: vec3<f32>, bass: f32) -> f32 {
    return mapCavern(p, bass).x;
}

// Tetrahedral SDF gradient → real surface normals
fn calcNormal(p: vec3<f32>, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.0025, -0.0025);
    return normalize(
        e.xyy * mapDist(p + e.xyy, bass) +
        e.yyx * mapDist(p + e.yyx, bass) +
        e.yxy * mapDist(p + e.yxy, bass) +
        e.xxx * mapDist(p + e.xxx, bass));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let coord = vec2<i32>(id.xy);
    let uv = vec2<f32>(id.xy) / res;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var col = vec3<f32>(0.0);

    let camPulse = 1.0 + bass * 0.4;
    var ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x) * camPulse;
    var rd = normalize(vec3<f32>(uv * 2.0 - 1.0, 1.0));
    rd = vec3<f32>(rd.xy * rotate((u.zoom_config.y - 0.5) * 3.14), rd.z);
    let yz = rd.yz * rotate((u.zoom_config.z - 0.5) * 3.14);
    rd = vec3<f32>(rd.x, yz.x, yz.y);

    // Chromatic depth separation: R and B march at slightly different offsets
    let rdR = normalize(rd + vec3<f32>(0.002 * bass, 0.0, 0.0));
    let rdB = normalize(rd - vec3<f32>(0.002 * treble, 0.0, 0.0));

    var t = 0.0;
    let max_dist = 20.0;
    var hit = false;
    var min_dist = 100.0;
    var steps = 0.0;
    var matId = 0.0;

    for (var i = 0; i < 64; i++) {
        let p = ro + rd * t;
        let dm = mapCavern(p, bass);
        min_dist = min(min_dist, dm.x);
        steps += 1.0;
        if (dm.x < 0.01) { hit = true; matId = dm.y; break; }
        if (t > max_dist) { break; }
        t += dm.x;
    }

    let glow = u.zoom_params.y * (1.0 + mids * 0.5);
    let depth_fade = 1.0 / max(1.0 + t * t * 0.1, 0.001);
    let p = ro + rd * t;
    let fracture = fract(length(p) * u.zoom_params.z * 5.0 + u.config.x * (0.2 + u.zoom_params.z));

    // ─── Surface geometry: normals, facet identity, lighting ───
    let n = calcNormal(p, bass);
    // Quantized normal → stable per-facet seed (octahedral facets share normals)
    let facetHash = hash31(round(n * 3.0));
    // Step-count ambient occlusion: deep crevices accumulate more steps
    let ao = clamp(1.15 - steps * (1.0 / 64.0) * 0.6, 0.25, 1.0);

    // 3-point lighting: glacial key, aurora fill, aether rim
    let keyDir = normalize(vec3<f32>(0.5, 0.8, -0.45));
    let fillDir = normalize(vec3<f32>(-0.7, -0.2, 0.35));
    let keyCol = vec3<f32>(0.75, 0.9, 1.1);
    let fillCol = vec3<f32>(0.2, 0.9, 0.65);
    let rimCol = vec3<f32>(0.85, 0.4, 1.0);
    let dif = max(dot(n, keyDir), 0.0);
    let fill = max(dot(n, fillDir), 0.0) * 0.45;
    let cosV = clamp(dot(-rd, n), 0.0, 1.0);
    let fres = pow(clamp(1.0 - cosV, 0.0, 1.0), 4.0);
    // Per-facet glints: specular flashes, chromatically split via rdR / rdB
    let specG = pow(max(dot(reflect(rd, n), keyDir), 0.0), 48.0);
    let specR = pow(max(dot(reflect(rdR, n), keyDir), 0.0), 48.0);
    let specB = pow(max(dot(reflect(rdB, n), keyDir), 0.0), 48.0);
    let glintBoost = (0.4 + facetHash * 2.2) * (1.0 + treble * 1.5);
    let glint = vec3<f32>(specR, specG, specB) * glintBoost;

    // Material-ID palettes: ice wall / crystal facet / plasma vein
    let veinMask = select(0.0, 1.0, matId > 1.5);
    let facetMask = select(0.0, 1.0, matId > 0.5 && matId < 1.5);
    let iceAlbedo = vec3<f32>(0.10, 0.34, 0.62);
    let facetAlbedo = mix(vec3<f32>(0.5, 0.82, 1.0), vec3<f32>(0.75, 0.6, 1.0), facetHash);
    let albedo = mix(iceAlbedo, facetAlbedo, facetMask);

    // Tessellated frost inlay: triangular grid projected triplanar-style
    let an = abs(n);
    let tw = an / max(an.x + an.y + an.z, 0.001);
    let inlay = p.yz * tw.x + p.xz * tw.y + p.xy * tw.z;
    let frostScale = 5.0 + u.zoom_params.z * 10.0;
    let sp = inlay * frostScale;
    let l1 = abs(fract(sp.x + sp.y * 0.57735027) - 0.5);
    let l2 = abs(fract(sp.x - sp.y * 0.57735027) - 0.5);
    let l3 = abs(fract(sp.y * 1.1547005) - 0.5);
    let frostLine = 1.0 - smoothstep(0.015, 0.07, min(min(l1, l2), l3));

    // Thin-film iridescence on crystal shells
    let iri = thinFilm(cosV, 0.6 + facetHash * 1.7) * fres;

    var hitColor = albedo * (keyCol * dif + fillCol * fill + vec3<f32>(0.06)) * ao;
    hitColor += rimCol * fres * (0.55 + mids * 0.4);
    hitColor += glint * 0.55;
    hitColor += iri * glow * 0.4;
    hitColor += frostLine * vec3<f32>(0.7, 0.95, 1.1) * (0.12 + bass * 0.35) * ao;
    hitColor += vec3<f32>(0.25, 0.85, 1.0) * veinMask * glow * (1.3 + mids);
    hitColor += vec3<f32>(0.2, 0.8, 1.0) * step(0.95, fracture) * (bass + treble);
    hitColor *= depth_fade * glow;

    let missColor = vec3<f32>(0.05, 0.1, 0.2) * (1.0 / max(1.0 + min_dist * 10.0, 0.001)) * glow;
    col = select(missColor, hitColor, hit);
    col += vec3<f32>(0.2, 0.5, 0.6) * (mids + bass * 0.5) * 0.1;

    // Temporal ice formation: previous frame crystallizes
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    let iceForm = mix(col, prev * 0.92, 0.06 + bass * 0.02);
    col = mix(col, iceForm, 0.5);

    // Audio-reactive fracture overlay
    let fractureOverlay = vec3<f32>(0.3, 0.6, 0.9) * step(0.97, fract(length(p) * 10.0 + bass * 5.0)) * treble;
    col += fractureOverlay;

    let hitMask = select(0.0, 1.0, hit);
    let alpha = clamp(0.25 + hitMask * 0.4 + depth_fade * 0.3 + bass * 0.15, 0.0, 1.0);

    let depthOut = select(0.0, clamp(1.0 - t / max_dist, 0.0, 1.0), hit);

    col = acesToneMap(col * 1.1);
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
