// ═══════════════════════════════════════════════════════════════════
//  Hyperbolic Crystal Symbiosis
//  Category: generative
//  Description: Competing crystal growth in hyperbolic geometry.
//  Local curvature influenced by audio and mouse. Non-Euclidean tiling
//  with iridescent jewel-like coloring and symmetry breaking.
//  Complexity: High
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Poincaré disk model: Möbius transform (hyperbolic translation)
fn hyperbolicTranslate(z: vec2<f32>, a: vec2<f32>) -> vec2<f32> {
    // T_a(z) = (z - a) / (1 - conj(a)*z) in complex arithmetic
    let num = z - a;
    let den_r = 1.0 - (a.x * z.x + a.y * z.y);
    let den_i = -(a.x * z.y - a.y * z.x);  // -conj(a)*z imaginary part simplified
    let denom = den_r * den_r + den_i * den_i + 1e-8;
    return vec2<f32>(
        (num.x * den_r + num.y * den_i) / denom,
        (num.y * den_r - num.x * den_i) / denom
    );
}

// Hyperbolic distance in Poincaré disk
fn hyperbolicDist(z: vec2<f32>) -> f32 {
    let r2 = dot(z, z);
    if (r2 >= 1.0) { return 10.0; } // outside disk
    return 2.0 * atanh(sqrt(r2));
}

// Complex rotation
fn crot(z: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(c * z.x - s * z.y, s * z.x + c * z.y);
}

// Hyperbolic tiling: p,q tessellation (e.g. {4,5} or {5,4})
// Returns (cellDist, cellId) in hyperbolic space
fn hyperbolicTiling(z: vec2<f32>, p: f32, q: f32, bass: f32) -> vec2<f32> {
    var w = z;
    var cellId = 0.0;

    let r2 = dot(w, w);
    if (r2 >= 0.999) {
        return vec2<f32>(100.0, 0.0);
    }

    // Apply p-fold symmetry
    let pAngle = TAU / p;
    let angle = atan2(w.y, w.x);
    let sector = floor((angle + PI) / pAngle);
    w = crot(w, -sector * pAngle);
    cellId = sector;

    // Fundamental domain: reflect to reduce to the tile
    let reflectCenter = vec2<f32>(0.5 + bass * 0.05, 0.0);
    let reflectR2 = dot(reflectCenter, reflectCenter);

    for (var iter = 0; iter < 8; iter++) {
        // Inversion in the reflection circle
        let dToCenter = w - reflectCenter;
        let d2 = dot(dToCenter, dToCenter);
        if (d2 < 1e-6) { break; }
        let inside = dot(w, w);
        if (inside < reflectR2 && d2 > 0.01) {
            w = reflectCenter + (1.0 / reflectR2) * dToCenter * reflectR2 / d2;
            cellId += 1.0;
        }
        // Re-apply p-fold symmetry
        let a2 = atan2(w.y, w.x);
        let s2 = floor((a2 + PI) / pAngle);
        w = crot(w, -s2 * pAngle);
        cellId += s2 * 0.1;
    }

    return vec2<f32>(hyperbolicDist(w), fract(cellId * 0.137));
}

// Crystal facet pattern: Voronoi-like in hyperbolic coordinates
fn crystalFacet(z: vec2<f32>, t: f32, growthSpeed: f32, mutation: f32) -> vec4<f32> {
    var minD = 100.0;
    var minId = 0.0;
    var secondD = 100.0;

    let numSeeds = 7;
    for (var k = 0; k < numSeeds; k++) {
        let kf = f32(k);
        let seedAngle = kf * TAU / f32(numSeeds) + t * growthSpeed * 0.1;
        let seedR = 0.4 + mutation * 0.15 * sin(kf * 2.7 + t * growthSpeed * 0.05);
        let seed = vec2<f32>(seedR * cos(seedAngle), seedR * sin(seedAngle) * 0.7);

        // Translate to seed's local frame in hyperbolic geometry
        let localZ = hyperbolicTranslate(z, seed);
        let d = hyperbolicDist(localZ);

        if (d < minD) {
            secondD = minD;
            minD = d;
            minId = hash12(vec2<f32>(kf + 0.5, kf * 1.3));
        } else if (d < secondD) {
            secondD = d;
        }
    }

    let border = secondD - minD;
    return vec4<f32>(minD, secondD, border, minId);
}

// Jewel iridescent color
fn jewelColor(cellId: f32, dist: f32, border: f32, t: f32,
              bass: f32, mids: f32, treble: f32) -> vec3<f32> {
    let hue = cellId + t * 0.05 + bass * 0.3;
    let saturation = 0.7 + mids * 0.3;
    let lightness = 0.3 + 0.4 * smoothstep(0.3, 0.0, dist);

    let r = lightness + saturation * 0.5 * cos(hue * TAU);
    let g = lightness + saturation * 0.5 * cos(hue * TAU + 2.094 + treble * 0.5);
    let b = lightness + saturation * 0.5 * cos(hue * TAU + 4.189 + mids * 0.3);
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let growthSpeed  = u.zoom_params.x * 1.5 + 0.3;  // 0.3..1.8
    let competition  = u.zoom_params.y;               // 0..1 crystal competition
    let curvature    = u.zoom_params.z * 0.7 + 0.3;   // 0.3..1.0 hyperbolic curvature
    let mutation     = u.zoom_params.w * 0.5;          // 0..0.5 growth mutation

    // Map screen UV to Poincaré disk, centered and scaled
    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    // Mouse controls focal point of the hyperbolic plane
    let focus = (mousePos - 0.5) * 0.6;

    // Convert UV to disk coordinates
    var diskUV = (uv - 0.5) * 2.2; // scale to near unit disk
    diskUV.x *= res.x / res.y; // aspect correct

    // Audio modulates curvature: bass expands, treble contracts
    let curv = curvature * (1.0 + bass * 0.3 - treble * 0.1);
    diskUV *= curv;

    // Apply focus translation from mouse
    diskUV = hyperbolicTranslate(diskUV, focus * 0.8);

    let r2 = dot(diskUV, diskUV);
    if (r2 >= 0.99) {
        // Outside disk: boundary color
        let boundaryColor = vec3<f32>(0.05, 0.04, 0.08);
        textureStore(writeTexture, global_id.xy, vec4<f32>(boundaryColor, 1.0));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
        return;
    }

    // Tiling parameters: vary with audio
    let p = 5.0 + competition * 2.0; // 5..7 p-fold symmetry
    let q = 4.0;

    let tiling = hyperbolicTiling(diskUV, p, q, bass);
    let cellDist = tiling.x;
    let cellId   = tiling.y;

    // Crystal facets
    let crystalData = crystalFacet(diskUV, t, growthSpeed + bass * 0.3, mutation + mids * 0.2);
    let facetDist = crystalData.x;
    let facetId   = crystalData.w;
    let facetBorder = crystalData.z;

    // Combine tiling and crystal growth
    let combinedId = fract(cellId * 0.7 + facetId * 0.3);

    var color = jewelColor(combinedId, facetDist, facetBorder,
                            t, bass, mids, treble);

    // Facet borders: bright edges (symmetry breaking)
    let edgeWidth = 0.15 + competition * 0.2;
    let edgeGlow = smoothstep(edgeWidth, 0.0, facetBorder) *
                   (0.5 + treble * 0.5);
    color += vec3<f32>(1.0, 0.95, 0.85) * edgeGlow * 1.5;

    // Tiling boundaries: deeper structural lines
    let tilingEdge = smoothstep(0.05, 0.0, abs(cellDist - 1.5)) * 0.3;
    color = mix(color, vec3<f32>(1.0, 1.0, 1.0), tilingEdge * mids);

    // Crystal growth front: glowing rim at mutation threshold
    let growthFront = smoothstep(0.1, 0.0, abs(facetDist - (0.8 + bass * 0.3)));
    color += vec3<f32>(0.8, 1.0, 0.9) * growthFront * treble * 0.8;

    // Vignette from disk edge
    let diskEdge = 1.0 - smoothstep(0.7, 1.0, sqrt(r2));
    color *= diskEdge;

    textureStore(writeTexture, global_id.xy, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
