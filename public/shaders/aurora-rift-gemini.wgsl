// ═══════════════════════════════════════════════════════════════════
//  Aurora Rift Gemini – Hyper-Spectral Flux v2
//  Enhanced aurora with magnetic field simulation, shimmering
//  particle effects, and a dual-palette color system.
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-02
//  Ideas: field-line arcs from the two-pole stream function; pulsating aurora patches (per-cell blink periods)
//  A packing: pre-ACES HDR diffused RGB + emission coverage alpha; ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════
//  HEAD fixes (2026-11-02): the pasted Uniforms declared zoom_params before zoom_config, so
//  "Scale" was time·3.5 (the rift dissolved to noise within a minute) and Flow/Diffusion/Octaves
//  were mouse x/y/down — hand-migrated to the prelude; the four extra roles take their mid-slider
//  constants. fbm summed white hash noise (per-pixel random curl) → smooth value noise. History is
//  an exact textureLoad; output is ACES-mapped (shimmer added ×100 HDR) with a coverage alpha.
#include "_prelude.wgsl"

// --- (Hash functions, noise, fbm, curlNoise, voronoiCell, quaternionRotate, hsv2rgb - unchanged) ---

fn hash2(p: vec2<f32>) -> f32 {
    var h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash4(p: vec4<f32>) -> f32 {
    let dot4 = dot(p, vec4<f32>(1.0, 57.0, 113.0, 157.0));
    return fract(sin(dot4) * 43758.5453123);
}

fn noise4d(p: vec4<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    
    var sum = 0.0;
    for (var w: i32 = 0; w <= 1; w = w + 1) {
        for (var z: i32 = 0; z <= 1; z = z + 1) {
            for (var y: i32 = 0; y <= 1; y = y + 1) {
                for (var x: i32 = 0; x <= 1; x = x + 1) {
                    let corner = i + vec4<f32>(f32(x), f32(y), f32(z), f32(w));
                    let wx = select(1.0 - u.x, u.x, x == 1);
                    let wy = select(1.0 - u.y, u.y, y == 1);
                    let wz = select(1.0 - u.z, u.z, z == 1);
                    let ww = select(1.0 - u.w, u.w, w == 1);
                    sum = sum + wx * wy * wz * ww * hash4(corner);
                }
            }
        }
    }
    return sum * 2.0 - 1.0;
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum = sum + amp * (vnoise(p * freq + time * 0.1) - 0.5);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.001;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>(n2 - n4, n1 - n3) / (2.0 * eps);
}

// Returns (F1, nearest cell's integer id, F2) — Idea 2 needs the id, the border needs F2 − F1.
fn voronoiCell(p: vec2<f32>) -> vec4<f32> {
    var i = floor(p);
    var f = fract(p);
    var best = 1e5;
    var second = 1e5;
    var bestCell = i;
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let cellPos = i + vec2<f32>(f32(x), f32(y));
            let seed = vec2<f32>(hash2(cellPos), hash2(cellPos + 13.37));
            let point = cellPos + seed - 0.5;
            let d = length(point - p);
            bestCell = select(bestCell, cellPos, d < best);
            second = select(min(second, d), best, d < best);
            best = min(best, d);
        }
    }
    return vec4<f32>(best, bestCell, second);
}

fn quaternionRotate(col: vec3<f32>, angle: f32, axis: vec3<f32>) -> vec3<f32> {
    let s = sin(angle * 0.5);
    var c = cos(angle * 0.5);
    let q = vec4<f32>(normalize(axis) * s, c);
    let t = 2.0 * cross(q.xyz, col);
    return col + q.w * t + cross(q.xyz, t);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    var c = v * s;
    let h6 = h * 6.0;
    var x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Spectral power distribution
// ─────────────────────────────────────────────────────────────────────────────
fn spectralPower(col: vec3<f32>, pattern: f32) -> vec3<f32> {
    let safeCol = max(col, vec3<f32>(0.001));
    let k = clamp(pattern, 0.0, 1.0);   // pattern reaches ~2.8; mix() past 1 extrapolated to negative RGB
    let high = pow(safeCol, vec3<f32>(2.2));
    let low = sqrt(safeCol);
    let band = sin(safeCol * 3.145679);
    return mix(low, high, k) + band * k * 0.15;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ✨ GEMINI UPGRADE: Magnetic field simulation
fn poleA(time: f32, mouse: vec2<f32>) -> vec2<f32> {
    // The pointer drags the first pole (it still wanders a little around it)
    return mix(vec2<f32>(sin(time * 0.5), cos(time * 0.5)) * 0.5 + 0.5, mouse, 0.65);
}

fn poleB(time: f32) -> vec2<f32> {
    return vec2<f32>(sin(time * 0.7), cos(time * 0.4)) * 0.5 + 0.5;
}

fn magneticField(p: vec2<f32>, time: f32, mouse: vec2<f32>) -> vec2<f32> {
    let p1 = poleA(time, mouse);
    let p2 = poleB(time);
    let v1 = p - p1;
    let v2 = p - p2;
    let f1 = v1 / pow(length(v1), 2.0);
    let f2 = v2 / pow(length(v2), 2.0);
    return (f1 - f2) * 0.01;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    var uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let rawMouse = u.zoom_config.yz;
    let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
    let mouse = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);

    let scale = u.zoom_params.x * 3.5 + 0.5;
    let flowSpeed = u.zoom_params.y * 2.8 + 0.2;
    let diffusionRate = u.zoom_params.z * 0.8 + 0.1;
    let fbmOctaves = i32(u.zoom_params.w * 5.0 + 2.0);
    // HEAD read these from the mis-ordered struct's last block (the real sliders); there are only
    // four sliders, so they take the value a centred slider gave.
    let rotSpeed = 1.05;
    let depthParallax = 0.4;
    let emitThresh = 0.175;
    let chromaSpread = 0.25;

    let srcCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ✨ GEMINI UPGRADE: Integrate magnetic field
    let magField = magneticField(uv, time, mouse);
    let curl = curlNoise(uv * scale + depth * depthParallax + magField, time * flowSpeed);

    var totalWarp = vec2<f32>(0.0);
    // (Multi-layer parallax - slightly modified)
    for (var layer: i32 = 0; layer < 4; layer = layer + 1) { // 4 layers
        let layerDepth = f32(layer) / 3.0;
        let layerWeight = 1.0 / (1.0 + abs(depth - layerDepth) * 15.0);
        let advected = curlNoise(uv * scale + curl * 0.4, time * flowSpeed * (1.0 + f32(layer) * 0.5));
        let offset = advected * depthParallax * layerWeight;
        totalWarp += offset * layerWeight;
    }
    
    let vor = voronoiCell(uv * scale * 2.0 + totalWarp);
    let cellDist = vor.x;
    let fbmVal = fbm(uv * scale * 4.0 + curl, time, fbmOctaves);
    let foamPattern = smoothstep(0.0, 0.1, cellDist) * 0.7 + smoothstep(0.2, 0.4, fbmVal) * 0.3;

    let hyper = noise4d(vec4<f32>(uv * scale * 1.5, time * 0.4, sin(time)));
    let hyperMod = (hyper + 1.0) * 0.5;
    
    let waveA = sin(length(uv - 0.5) * 28.0 - time * 3.2);
    let waveB = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 22.0 + time * 2.7);
    let waveC = sin(dot(uv - 0.5, vec2<f32>(1.1, 0.9)) * 30.0 - time * 4.1);
    let interference = (waveA * waveB * waveC + 1.0) * 0.5;

    let pattern = (foamPattern * 0.4 + hyperMod * 0.3 + interference * 0.3) * (1.0 + (1.0 - depth) * 1.8);

    let axis = normalize(srcCol + vec3<f32>(0.12, 0.07, 0.04));
    let angle = time * rotSpeed + pattern * 3.5;
    let quatCol = quaternionRotate(srcCol, angle, axis);

    let disp = pattern * chromaSpread / dims.x * 28.0;
    let rUV = clamp(uv + totalWarp * disp + curl * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + totalWarp * disp * 0.9 + curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + totalWarp * disp * 1.1 - curl * 0.018, vec2<f32>(0.0), vec2<f32>(1.0));
    let dispersed = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    );

    // Rift borders on the Voronoi edges (F2−F1 ≈ 0) with the pattern taken without its depth
    // factor — HEAD keyed on F1 (≈1 inside every cell) × the depth-boosted pattern, so it washed
    // the frame at depth 0 and vanished at depth 1.
    let patternBase = foamPattern * 0.4 + hyperMod * 0.3 + interference * 0.3;
    let edge = 1.0 - smoothstep(0.0, 0.15, vor.w - vor.x);
    var border = smoothstep(emitThresh, 1.0, edge * patternBase * (0.6 + length(curl)) * 2.2);

    // Idea 1: field-line arcs. For the two poles of magneticField the stream function is the
    // difference of the polar angles about each pole; its level sets are the field lines looping
    // pole to pole. cos(N·ψ) is continuous across the atan2 wrap for integer N. The rift light is
    // gathered onto those lines (and a faint arc glow survives between borders near the poles).
    let v1 = uv - poleA(time, mouse);
    let v2 = uv - poleB(time);
    let psi = atan2(v1.y, v1.x) - atan2(v2.y, v2.x);
    let arcs = pow(0.5 + 0.5 * cos(psi * 7.0 + time * 0.3), 3.0);
    let nearPoles = exp(-min(length(v1), length(v2)) * 2.5);
    border = border * (0.3 + 1.1 * arcs) + arcs * nearPoles * 0.25 * (1.0 + mids * 0.5);

    // ✨ GEMINI UPGRADE: Dual palette plasma
    let plasma1 = hsv2rgb(fract(time * 0.07 + pattern + hyper), 0.9, 1.0);
    let plasma2 = hsv2rgb(fract(time * 0.05 + pattern * 0.5 + hyper * 2.0), 0.8, 1.0);
    // Idea 2: pulsating aurora — each foam cell blinks on its own 2–9 s period and phase,
    // switching between a dim glow and full brightness (bass shortens the off-time).
    let period = mix(2.0, 9.0, hash2(vor.yz + 3.1));
    let blink = 0.5 + 0.5 * sin(6.2831853 * (time / period + hash2(vor.yz + 7.7)));
    let pulse = smoothstep(0.6 - bass * 0.2, 0.85, blink);
    let plasma = mix(plasma1, plasma2, 0.5) * mix(0.35, 1.7, pulse);
    
    let emissive = mix(dispersed, plasma, clamp(border, 0.0, 1.0) * 0.6);

    let historyUV = clamp(uv + totalWarp * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));
    let historyCoord = clamp(vec2<i32>(historyUV * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
    let history = textureLoad(dataTextureC, historyCoord, 0).rgb;
    let flowDir = normalize(totalWarp + curl + 0.001);
    let anisotropy = 1.0 - abs(dot(flowDir, normalize(uv - 0.5 + 0.001))) * 0.3;
    let diffused = mix(emissive, history, diffusionRate * anisotropy);

    // ✨ GEMINI UPGRADE: Shimmer effect
    let shimmer_noise = hash2(uv + time * 0.1);
    var shimmer = 0.0;
    if (shimmer_noise > 0.995) {
        shimmer = shimmer_noise * 100.0;
    }
    
    let spectral = spectralPower(diffused, pattern);
    let finalCol = mix(srcCol, spectral, 1.0) + shimmer;

    // Coverage alpha: how much rift light lies over the picture (HEAD wrote 1.0)
    let alpha = clamp(1.0 - exp(-(pattern * 0.6 + clamp(border, 0.0, 1.0) * 2.0)), 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(aces(max(finalCol, vec3<f32>(0.0))), alpha));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(diffused, alpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
