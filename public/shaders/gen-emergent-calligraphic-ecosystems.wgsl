// ═══════════════════════════════════════════════════════════════════
//  Emergent Calligraphic Ecosystems
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-10-31
//  Ideas: brush pressure swell along the stroke; prey-predator ink chase along the flow; paper-fibre ink feathering; glyph death phase (dry, crack, rebirth);
//         capillary backrun blooms; ligature bridge strokes between nearby glyph clusters;
//         wet-edge pooling that dries with cluster age (C wet-edge/drying); dry-brush paper granulation (C paper granulation);
//         golden-angle stroke spacing inside each glyph cluster (E golden-angle layout)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

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

fn smoothNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

// Flow field direction at a point, influenced by curlNoise-like approach
fn flowAngle(p: vec2<f32>, t: f32, mids: f32, bass: f32) -> f32 {
    let n1 = smoothNoise(p * 3.0 + vec2<f32>(t * 0.12, 0.0));
    let n2 = smoothNoise(p * 3.0 + vec2<f32>(0.0, t * 0.09) + vec2<f32>(5.2, 1.3));
    let n3 = smoothNoise(p * 1.5 + vec2<f32>(t * 0.06, t * 0.04));
    return (n1 * 2.0 - 1.0) * PI + n2 * mids * 2.0 + n3 * bass * PI;
}

// Stroke primitive: a curved brushstroke from a seed
fn stroke(uv: vec2<f32>, seed: vec2<f32>, t: f32, strokeLen: f32,
          inkWidth: f32, orientation: f32, wick: f32, wet: f32) -> f32 {
    let d = uv - seed;
    let along = d.x * cos(orientation) + d.y * sin(orientation);
    let across = -d.x * sin(orientation) + d.y * cos(orientation);

    let inLength = smoothstep(0.0, 0.1, along) * smoothstep(strokeLen + 0.05, strokeLen, along);
    let taper = sin(clamp(along / max(strokeLen, 0.001), 0.0, 1.0) * PI);
    // Idea 1 — brush pressure swell: real calligraphy width breathes along the stroke
    let pressure = 1.0 + 0.38 * sin(along * 16.0 + orientation + t * 0.7);
    let w = inkWidth * pressure;
    // Idea 7 — wet-edge pooling: fresh ink is thin in the middle and pools dark at the rim; it flattens as the glyph dries (wet -> 0)
    let rim = smoothstep(0.35, 0.95, abs(across) / max(w, 0.0005));
    let pooling = 1.0 - 0.22 * wet * (1.0 - rim);
    // Idea 8 — dry-brush granulation: fixed paper tooth (screen-space, does not slide with the stroke) leaves pigment gaps in the core, more as the ink dries
    let tooth = smoothNoise(uv * 150.0);
    let granule = 1.0 - (0.06 + 0.26 * (1.0 - wet)) * smoothstep(0.35, 0.8, tooth) * (1.0 - rim);
    let inWidth = smoothstep(w, 0.0, abs(across)) * taper * pooling * granule;

    // Idea 3 — ink feathering: wet ink wicks past the edge along anisotropic paper fibres
    let fibre = smoothNoise(uv * vec2<f32>(310.0, 46.0)) * 0.6 + smoothNoise(uv * vec2<f32>(52.0, 290.0)) * 0.4;
    let reach = inkWidth * pressure * (1.4 + fibre * 2.2);
    let feather = smoothstep(reach, inkWidth * pressure, abs(across)) * taper * (0.2 + fibre * 0.3);

    return inLength * max(inWidth, feather * wick);
}

// Calligraphic glyph cluster: N strokes around a seed, self-organizing into glyphs
fn glyphCluster(uv: vec2<f32>, clusterSeed: vec2<f32>, t: f32,
                bass: f32, mids: f32, treble: f32,
                strokeDensity: f32, inkWidth: f32, chase: f32, wick: f32) -> vec2<f32> {
    var totalInk = 0.0;
    let numStrokes = i32(clamp(strokeDensity * 6.0 + 3.0, 3.0, 9.0));
    let seedHash = hash22(clusterSeed);
    let clusterBirth = seedHash.x * 5.0;
    let lived = t * 0.2 - clusterBirth;
    if (lived <= 0.0) { return vec2<f32>(0.0); }
    // Idea 4 — glyph death phase: each cluster lives a cycle, dries and cracks, then is reborn
    let lifeSpan = 4.0 + seedHash.y * 3.0;
    let cycle = fract(lived / lifeSpan);
    let age = clamp(cycle * lifeSpan, 0.0, 1.0);
    let death = smoothstep(0.72, 0.98, cycle);
    let wet = 1.0 - smoothstep(0.0, 0.45, cycle);

    for (var k = 0; k < numStrokes; k++) {
        let kf = f32(k);
        let strokeHash = hash22(clusterSeed + vec2<f32>(kf * 0.37, kf * 0.73));
        // Idea 9 — golden-angle spacing: strokes sit on a Vogel spiral around the seed instead of random clumps
        let vogel = vec2<f32>(cos(kf * 2.39996), sin(kf * 2.39996)) * 0.024 * sqrt((kf + 0.5) / f32(numStrokes));
        let localOffset = mix((strokeHash - 0.5) * 0.08, vogel, 0.5) * (1.0 + mids * 0.5);
        let baseAngle = flowAngle(clusterSeed, t * 0.5, mids, bass);
        // Idea 2 — prey-predator ink chase: flora seeds slide along the flow
        let chaseOff = vec2<f32>(cos(baseAngle), sin(baseAngle)) * chase;
        let strokeSeed = clusterSeed + localOffset + chaseOff;

        let strokeAngle = baseAngle + (strokeHash.x - 0.5) * PI * 0.6 +
                          treble * PI * 0.3 * sin(t * 2.0 + kf);

        let sLen = 0.02 + strokeHash.y * 0.06 + bass * 0.02;
        let sWidth = inkWidth * (0.5 + strokeHash.x * 0.5) * (0.8 + mids * 0.4);

        let growLen = sLen * smoothstep(0.0, 0.3, age);
        totalInk += stroke(uv, strokeSeed, t, growLen, sWidth, strokeAngle, wick, wet);
    }
    // Dried ink cracks into flakes as death advances
    let crack = smoothNoise(uv * 140.0 + clusterSeed * 31.0) * 0.7 + hash12(floor(uv * 420.0)) * 0.3;
    let flake = 1.0 - smoothstep(crack - 0.1, crack + 0.05, death * 1.1);
    return vec2<f32>(clamp(totalInk, 0.0, 1.0) * flake, death);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvA = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let strokeDensity = u.zoom_params.x;
    let inkWidth      = u.zoom_params.y * 0.012 + 0.003;
    let complexity    = u.zoom_params.z * 2.0 + 1.0;
    let neonMode      = u.zoom_params.w;

    let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
    let mouseDist = length(uvA - mousePos);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    var clickInk = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = t - ripple.z;
        if (age >= 0.0 && age < 4.0) {
            let rp = vec2<f32>(ripple.x * aspect, ripple.y);
            let front = abs(length(uvA - rp) - age * 0.11);
            clickInk += (1.0 - smoothstep(0.0, 0.018, front)) * (1.0 - age / 4.0);
        }
    }
    clickInk = min(clickInk, 2.0);
    // Mouse introduces invasive species disturbance
    let invasiveBoost = exp(-mouseDist * mouseDist * 25.0) * (0.3 + held * 0.9) * (1.0 + bass * 2.0);

    // Lotka-Volterra predator-prey oscillations
    // Prey = green flora, Predators = red-orange fauna
    let prey = sin(t * 0.5) * 0.5 + 0.5;
    let predator = cos(t * 0.5 + 1.0) * 0.5 + 0.5;
    // Bass triggers population blooms (increases oscillation amplitude)
    let bloom = 1.0 + bass * 0.8;
    let preyBloom = prey * bloom;
    let predatorBloom = predator * bloom;

    // Tile space into a grid of glyph clusters
    let gridScale = 5.0 * complexity;
    let gridUV = uvA * gridScale;
    let gridCell = floor(gridUV);

    var totalInk = 0.0;
    var inkColor = vec3<f32>(0.0);
    var dryAcc = 0.0;

    // Check 3x3 neighborhood of clusters (strokes can bleed over cell edges)
    for (var jj: i32 = -1; jj <= 1; jj++) {
        for (var ii: i32 = -1; ii <= 1; ii++) {
            let neighbor = gridCell + vec2<f32>(f32(ii), f32(jj));
            let clusterSeed = (neighbor + 0.5) / gridScale;

            // Invasive species from mouse boost density locally
            let effectiveDensity = strokeDensity + invasiveBoost * 0.4;
            let clusterHash0 = hash22(neighbor * 0.1 + 0.5);
            // Flora (low hash) chases predators along the flow; fauna stays put
            let chase = (predatorBloom - 0.5) * 0.028 * (1.0 - clusterHash0.x);
            let glyph = glyphCluster(uvA, clusterSeed, t, bass, mids, treble,
                                     effectiveDensity, inkWidth, chase, 1.0 - neonMode);
            let ink = glyph.x;
            if (ink > 0.0) {
                // Ecosystem color driven by Lotka-Volterra cycles
                // Flora color = green scaled by prey population
                let floraCol = vec3<f32>(0.0, preyBloom, 0.1) * (0.6 + mids * 0.4);
                // Fauna glow = red-orange scaled by predator population
                let faunaCol = vec3<f32>(predatorBloom, predatorBloom * 0.3, 0.0) * (0.5 + treble * 0.5);
                // Mix based on cluster hash for spatial variety
                let clusterHash = hash22(neighbor * 0.1 + 0.5);
                let ecosystemMix = clusterHash.x;
                var clusterCol = mix(floraCol, faunaCol, ecosystemMix);
                let dryGrey = vec3<f32>(dot(clusterCol, vec3<f32>(0.299, 0.587, 0.114))) * 0.55;
                clusterCol = mix(clusterCol, dryGrey, glyph.y);

                inkColor += clusterCol * ink;
                totalInk += ink;
                dryAcc += glyph.y * ink;
            }
        }
    }

    // Background: paper-like cream or dark void
    let bgPaper = mix(
        vec3<f32>(0.95, 0.93, 0.88),
        vec3<f32>(0.02, 0.02, 0.05),
        neonMode
    );

    // Ink / neon color with ecosystem tint
    let ecosystemTint = vec3<f32>(preyBloom * 0.2, predatorBloom * 0.1, 0.05);
    let inkCol = mix(
        vec3<f32>(0.05, 0.05, 0.08) + ecosystemTint,
        inkColor * 1.5 + vec3<f32>(0.3, 0.2, 0.4) * treble,
        neonMode
    );

    var color = bgPaper;
    if (totalInk > 0.0) {
        let normInkColor = inkColor / totalInk;
        color = mix(bgPaper, mix(inkCol, normInkColor * 1.2, neonMode), clamp(totalInk * 2.0, 0.0, 1.0));
        // Dying glyphs: paper-mode ink dries toward a faded sepia, neon ink dims
        let dryness = dryAcc / totalInk;
        let driedPaper = mix(color, bgPaper * vec3<f32>(0.82, 0.74, 0.62), 0.55);
        color = mix(color, mix(driedPaper, color * 0.45, neonMode), dryness);
        // Neon glow halo
        color += normInkColor * totalInk * neonMode * treble * 0.5;

        // Idea 5: capillary backrun blooms at wet-dry boundaries.
        let edgeWet = totalInk * (1.0 - clamp(totalInk, 0.0, 1.0));
        let backrunNoise = 0.5 + 0.5 * smoothNoise(uvA * 120.0 + vec2<f32>(t * 0.4, -t * 0.35));
        let backrun = edgeWet * backrunNoise;
        color += mix(vec3<f32>(0.22, 0.12, 0.04), vec3<f32>(0.28, 0.95, 0.75), neonMode) * backrun * (0.18 + held * 0.35);

        // Idea 6: ligature bridges tying neighboring glyph clusters.
        let bridgeField = pow(max(0.0, sin(flowAngle(uvA * 0.9, t, mids, bass) * 2.0 + uvA.x * 40.0 - uvA.y * 26.0)), 5.0);
        let bridgeMask = smoothstep(0.05, 0.35, totalInk) * (1.0 - smoothstep(0.65, 0.95, totalInk));
        let ligature = bridgeField * bridgeMask;
        color += mix(vec3<f32>(0.05, 0.03, 0.01), vec3<f32>(0.85, 0.5, 1.0), neonMode) * ligature * (0.12 + treble * 0.4);
    }

    // Subtle paper texture
    let paperGrain = hash12(uvA * 200.0) * 0.03 * (1.0 - neonMode);
    color += paperGrain;

    // Mouse invasive species pulse: a bright seed planted by click
    let seedPulse = exp(-mouseDist * mouseDist * 100.0) * (0.5 + bass * 0.5);
    color += mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.8, 0.6, 1.0), neonMode) * seedPulse;
    color += mix(vec3<f32>(0.18, 0.06, 0.02), vec3<f32>(0.3, 1.0, 0.65), neonMode) * clickInk * (0.25 + treble * 0.5);

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES tone mapping
    color = acesToneMap(color * 1.1);

    // Semantic alpha
    let alpha = clamp(totalInk * 0.72 + invasiveBoost * 0.15 + clickInk * 0.2 + length(color) * 0.12, 0.04, 0.96);

    // Temporal feedback: ecosystem succession
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    let feedback = mix(prev.rgb * 0.96, color, 0.25);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(feedback, alpha));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(feedback, alpha));
    let depthOut = clamp(totalInk * 0.65 + invasiveBoost * 0.2 + clickInk * 0.15, 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
