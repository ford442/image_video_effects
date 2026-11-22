// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam – Pass 1: Field Generation
//  Category: simulation (multi-pass)
//  Features: multi-pass-1, curl-field, voronoi, 4d-noise, audio-reactive, depth-aware
//  Complexity: High
//  Chunks From: aurora-rift-pass1.wgsl (curl/fbm pattern), gen-quantum-foam-alpha.wgsl (voronoi)
//  Created: 2026-05-31
//  By: Claude Sonnet 4.6 (swarm optimization pass)
//  Upgraded: 2026-11-22
//  Ideas: virtual-pair cell lifetimes (nucleate / annihilate); flow-sheared cells along the curl
//         (kept: diffused voids at cell centers; wavefront ridges on constructive interference)
//  Rescue: fbm / curl / voronoi were un-interpolated hashes of position AND time (white noise in
//          space and time); now smooth, time-coherent noise and continuously orbiting seeds.
//  A packing: raw warpX, warpY, pattern, cellBoundary
// ═══════════════════════════════════════════════════════════════════
//  Pass graph: Pass 1 samples the input image and depth, generates the
//              quantum warp field, and writes it to dataTextureA.
//  Outputs: dataTextureA (vec4: warpX, warpY, pattern, cellBoundary)
#include "_prelude.wgsl"
// zoom_params: x=foamScale, y=flowSpeed, z=diffusionRate, w=octaveCount

// ═══════════════════════════════════════════════════════════════════════════
//  Hash functions
// ═══════════════════════════════════════════════════════════════════════════
fn hash3(p: vec3<f32>) -> f32 {
    let p3 = fract(p * vec3<f32>(443.897, 441.423, 997.731));
    return fract(p3.x * p3.y * p3.z + dot(p3, p3 + 19.19));
}

fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

// ═══════════════════════════════════════════════════════════════════════════
//  4D gradient noise for hyper-dimensional structure
// ═══════════════════════════════════════════════════════════════════════════
fn noise4d(p: vec4<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n000 = hash3(i.xyz);
    let n100 = hash3(i.xyz + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = hash3(i.xyz + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = hash3(i.xyz + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = hash3(i.xyz + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = hash3(i.xyz + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = hash3(i.xyz + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = hash3(i.xyz + vec3<f32>(1.0, 1.0, 1.0));

    let nx00 = mix(n000, n100, u.x);
    let nx10 = mix(n010, n110, u.x);
    let nx01 = mix(n001, n101, u.x);
    let nx11 = mix(n011, n111, u.x);

    let nxy0 = mix(nx00, nx10, u.y);
    let nxy1 = mix(nx01, nx11, u.y);

    return mix(nxy0, nxy1, u.z);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Smooth, time-coherent pseudo-noise (rescue: the old fbm hashed position and
//  time per sample, so every pixel and every frame was independent static).
//  Each octave is a product of two plane waves; the wave directions turn by the
//  golden angle from octave to octave and the phases drift with time, so the
//  field is smooth in space AND time. Octave gain 0.55 / lacunarity 2.15 are
//  the old values. curlNoise() is the analytic gradient of the same wave sum
//  but with a steeper octave gain (a gradient grows with frequency, so the flow
//  would otherwise be dominated by its finest octave).
// ═══════════════════════════════════════════════════════════════════════════
const GOLD_C: f32 = -0.737277;   // cos(137.5 deg)
const GOLD_S: f32 = 0.675590;    // sin(137.5 deg)
const CURL_GAIN: f32 = 0.3;      // keeps |curl| near 1, the scale every consumer assumes

fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 6.2831853;
    var d = vec2<f32>(0.8, 0.6);
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        let fi = f32(i);
        let e = vec2<f32>(d.x * 0.6 - d.y * 0.8, d.x * 0.8 + d.y * 0.6);
        let ph = time * (1.0 + fi * 0.2);
        value = value + amp * sin(dot(p, d) * freq + ph) * sin(dot(p, e) * freq * 1.13 + ph * 0.7 + fi * 1.7);
        d = vec2<f32>(d.x * GOLD_C - d.y * GOLD_S, d.x * GOLD_S + d.y * GOLD_C);
        freq = freq * 2.15;
        amp = amp * 0.55;
    }
    return value;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Curl noise for divergence-free flow: (d psi/dy, -d psi/dx) of the fbm above
// ═══════════════════════════════════════════════════════════════════════════
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    var g = vec2<f32>(0.0);
    var amp = 0.5;
    var freq = 6.2831853;
    var d = vec2<f32>(0.8, 0.6);
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let fi = f32(i);
        let e = vec2<f32>(d.x * 0.6 - d.y * 0.8, d.x * 0.8 + d.y * 0.6);
        let ph = time * (1.0 + fi * 0.2);
        let a = dot(p, d) * freq + ph;
        let b = dot(p, e) * freq * 1.13 + ph * 0.7 + fi * 1.7;
        g = g + amp * (cos(a) * sin(b) * freq * d + sin(a) * cos(b) * freq * 1.13 * e);
        d = vec2<f32>(d.x * GOLD_C - d.y * GOLD_S, d.x * GOLD_S + d.y * GOLD_C);
        freq = freq * 2.15;
        amp = amp * 0.42;
    }
    return vec2<f32>(g.y, -g.x) * CURL_GAIN;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Voronoi with feature detection.
//  Rescue: feature points used to be hash(cell, time) on the line y = 0.7 x, so
//  they re-rolled every frame. They now orbit their cell centre continuously.
//  Idea 2 (flow-sheared cells): distances are measured in a metric stretched
//  along flowDir. Returns (F1, F2, hash id of the nearest cell).
// ═══════════════════════════════════════════════════════════════════════════
fn voronoi(p: vec2<f32>, time: f32, flowDir: vec2<f32>, stretch: f32) -> vec3<f32> {
    let i = floor(p);
    let f = fract(p);
    let perp = vec2<f32>(-flowDir.y, flowDir.x);
    var minDist1 = 1000.0;
    var minDist2 = 1000.0;
    var minId = 0.0;

    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let h1 = hash3(vec3<f32>(i + neighbor, 7.0));
            let h2 = fract(h1 * 91.7 + 0.37);
            let orbit = vec2<f32>(
                cos(time * (0.35 + 0.5 * h1) + 6.2831853 * h1),
                sin(time * (0.35 + 0.5 * h2) + 6.2831853 * h2)
            );
            let point = neighbor + vec2<f32>(0.5) + 0.4 * orbit;
            let delta = point - f;
            let dist = length(vec2<f32>(dot(delta, flowDir) / stretch, dot(delta, perp)));
            if (dist < minDist1) {
                minDist2 = minDist1;
                minDist1 = dist;
                minId = h1;
            } else if (dist < minDist2) {
                minDist2 = dist;
            }
        }
    }
    return vec3<f32>(minDist1, minDist2, minId);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main compute shader - PASS 1: Field Generation
// ═══════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let uv = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time = u.config.x;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Audio reactivity — bass energizes foam turbulence, treble sharpens cell edges
    let bass   = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let foamScale = clamp(u.zoom_params.x, 0.0, 1.0) * 3.0 + 1.0;
    let flowSpeed = clamp(u.zoom_params.y, 0.0, 1.0);
    let diffusion = clamp(u.zoom_params.z, 0.0, 1.0);
    let octaveCount = i32(clamp(u.zoom_params.w, 0.0, 1.0) * 4.0 + 3.0);
    let depthParallax = u.zoom_config.y * 0.2;

    // Distance-based LOD for octaves
    let dist = length(uv - 0.5);
    let lodOctaves = i32(mix(f32(octaveCount), 2.0, smoothstep(0.3, 0.7, dist)));
    // The warp bends the voronoi lookup, so it stays large-scale (<= 3 octaves);
    // finer octaves would shred the cell edges. Octave Count drives the interior detail.
    let warpOctaves = min(lodOctaves, 3);

    // Curl noise for divergence-free flow field
    let curl = curlNoise(uv * foamScale * 0.5, time * flowSpeed);

    // Multi-layer parallax warp (unrolled for performance — eliminates loop overhead).
    // Each layer reads its own curl (own scale, offset and clock). The old nested
    // curlNoise(baseP + curl * lv) folded the lookup over itself and produced static.
    // Precompute shared constants
    let baseP = uv * foamScale * 0.5;
    let fs    = flowSpeed;

    // Layer 0 — foreground depth plane
    let lw0  = 1.0 / (1.0 + abs(depth - 0.0) * 15.0);
    let lv0  = 1.0;
    let ac0  = curlNoise(baseP * (1.0 + 0.35 * lv0) + vec2<f32>(3.7, 1.3) * lv0, time * fs * lv0);
    let ang0 = time * fs * lv0;
    let lo0  = ac0 * depthParallax * lw0 + vec2<f32>(cos(ang0), sin(ang0)) * lw0 * 0.1;
    let ln0  = fbm((uv + lo0) * foamScale, time * lv0, warpOctaves) * lw0 * lv0;

    // Layer 1 — mid depth plane
    let lw1  = 1.0 / (1.0 + abs(depth - 0.33) * 15.0);
    let lv1  = 1.5;
    let ac1  = curlNoise(baseP * (1.0 + 0.35 * lv1) + vec2<f32>(3.7, 1.3) * lv1, time * fs * lv1);
    let ang1 = time * fs * lv1 + 2.094;
    let lo1  = ac1 * depthParallax * lw1 + vec2<f32>(cos(ang1), sin(ang1)) * lw1 * 0.1;
    let ln1  = fbm((uv + lo1) * foamScale, time * lv1, warpOctaves) * lw1 * lv1;

    // Layer 2 — background depth plane
    let lw2  = 1.0 / (1.0 + abs(depth - 0.66) * 15.0);
    let lv2  = 2.0;
    let ac2  = curlNoise(baseP * (1.0 + 0.35 * lv2) + vec2<f32>(3.7, 1.3) * lv2, time * fs * lv2);
    let ang2 = time * fs * lv2 + 4.188;
    let lo2  = ac2 * depthParallax * lw2 + vec2<f32>(cos(ang2), sin(ang2)) * lw2 * 0.1;
    let ln2  = fbm((uv + lo2) * foamScale, time * lv2, warpOctaves) * lw2 * lv2;

    let parallaxWeight = lw0 + lw1 + lw2;
    var totalWarp = vec2<f32>(ln0 + ln1 + ln2) / max(parallaxWeight, 0.001);
    totalWarp = totalWarp + curl * 0.05;

    // ── Idea 2: flow-sheared cells ──────────────────────────────────────
    // Foam bubbles elongate along the shear: the cell metric is stretched along
    // the local curl direction, and Flow Speed sets how hard.
    let flowDir = curl / max(length(curl), 0.0001);
    let shearStretch = 1.0 + 0.8 * flowSpeed;

    // Voronoi-FBM hybrid with feature detection
    // The warp bends the lookup by well under one cell per cell-width (slope < 1);
    // the old x2.0 folded the map over itself and the cells dissolved into speckle.
    let cell = voronoi(uv * foamScale + totalWarp * 0.35, time, flowDir, shearStretch);

    // ── Idea 1: virtual-pair lifetimes ──────────────────────────────────
    // Every cell runs its own clock: it nucleates, peaks, and annihilates.
    // sin^2 of a per-cell phase gives a smooth 0 -> 1 -> 0 life.
    let lifePace = 0.10 + 0.12 * flowSpeed;
    let lifeS = sin(3.14159265 * fract(time * lifePace * (0.6 + cell.z) + cell.z * 7.0));
    let cellLife = lifeS * lifeS;
    let cellPattern = (1.0 - smoothstep(0.0, 0.08, cell.x)) * (0.3 + 0.7 * cellLife);
    let cellBoundary = smoothstep(0.08, 0.12, cell.y - cell.x);
    let cellInterior = fbm(uv * foamScale * 5.0 + cell.z * 2.0, time, max(lodOctaves - 2, 2));
    let hybridPattern = mix(cellInterior, cellPattern, cellBoundary);

    // 4D hyper-noise
    let hyperNoise = noise4d(vec4<f32>(uv * foamScale * 2.0, time * 0.3, time * 0.1));

    // Phase interference from three wavefronts
    let wave1 = sin(length(uv - 0.5) * 25.0 - time * 4.0);
    let wave2 = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 18.0 + time * 3.0);
    let wave3 = sin(dot(uv - 0.5, vec2<f32>(1.0, 1.0)) * 30.0 - time * 5.0);
    let interference = (wave1 * wave2 * wave3 + 1.0) * 0.5;

    // Depth-aware pattern combination — bass swells foam presence in foreground
    let depthWeight = 1.0 + (1.0 - depth) * 2.0;
    let bassBoost = 1.0 + bass * 0.7;
    let edgeSharp = 1.0 + treble * 0.4; // treble sharpens cell boundaries
    var pattern = (hybridPattern * 0.4 * edgeSharp + interference * 0.3 + hyperNoise * 0.3) * depthWeight * bassBoost;
    // Idea 1 — voids at cell centers; Diffusion Rate sets the hole radius
    let voidR = mix(40.0, 8.0, diffusion);
    let foamVoid = exp(-cell.x * cell.x * voidR);
    // A collapsing pair (low life) leaves a deeper transient void than a young one.
    pattern *= 1.0 - foamVoid * 0.85 * (0.4 + 0.6 * (1.0 - cellLife));
    // Idea 2 — three-wave crossings become foam ridges in the cell boundary
    var ridgeBoundary = cellBoundary;
    let waveRidge = smoothstep(0.72, 0.95, interference);
    ridgeBoundary = clamp(ridgeBoundary + waveRidge * (0.35 + diffusion * 0.25), 0.0, 1.0);
    totalWarp *= mix(1.0, 0.55, diffusion);

    // Pack field data: RGB = warp/direction + pattern, A = cell data
    let field = vec4<f32>(totalWarp.x, totalWarp.y, pattern, ridgeBoundary);

    // Store field for Pass 2
    textureStore(dataTextureA, coord, field);

    // Pass-through input to maintain chain (Pass 2 will do final compositing)
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    textureStore(writeTexture, coord, inputColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
