// ═══════════════════════════════════════════════════════════════════
//  Emergent Calligraphic Ecosystems
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven
//  Complexity: High
//  Enrichment: Lotka-Volterra Predator-Prey Dynamics (Wolfram Alpha)
//    - dx/dt = αx - βxy (prey growth minus predation)
//    - dy/dt = δxy - γy (predator growth minus starvation)
//    - Equilibrium: x = γ/δ, y = α/β
//    - Population oscillations create cyclic color waves
//  Created: 2026-06-07
//  By: Kimi Shader Agent
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
          inkWidth: f32, orientation: f32) -> f32 {
    let d = uv - seed;
    let along = d.x * cos(orientation) + d.y * sin(orientation);
    let across = -d.x * sin(orientation) + d.y * cos(orientation);

    let inLength = smoothstep(0.0, 0.1, along) * smoothstep(strokeLen + 0.05, strokeLen, along);
    let taper = sin(clamp(along / strokeLen, 0.0, 1.0) * PI);
    let inWidth = smoothstep(inkWidth, 0.0, abs(across)) * taper;

    return inLength * inWidth;
}

// Calligraphic glyph cluster: N strokes around a seed, self-organizing into glyphs
fn glyphCluster(uv: vec2<f32>, clusterSeed: vec2<f32>, t: f32,
                bass: f32, mids: f32, treble: f32,
                strokeDensity: f32, inkWidth: f32) -> f32 {
    var totalInk = 0.0;
    let numStrokes = i32(clamp(strokeDensity * 6.0 + 3.0, 3.0, 9.0));
    let seedHash = hash22(clusterSeed);
    let clusterBirth = seedHash.x * 5.0;
    let age = clamp(t * 0.2 - clusterBirth, 0.0, 1.0);
    if (age <= 0.0) { return 0.0; }

    for (var k = 0; k < numStrokes; k++) {
        let kf = f32(k);
        let strokeHash = hash22(clusterSeed + vec2<f32>(kf * 0.37, kf * 0.73));
        let localOffset = (strokeHash - 0.5) * 0.08 * (1.0 + mids * 0.5);
        let strokeSeed = clusterSeed + localOffset;

        let baseAngle = flowAngle(clusterSeed, t * 0.5, mids, bass);
        let strokeAngle = baseAngle + (strokeHash.x - 0.5) * PI * 0.6 +
                          treble * PI * 0.3 * sin(t * 2.0 + kf);

        let sLen = 0.02 + strokeHash.y * 0.06 + bass * 0.02;
        let sWidth = inkWidth * (0.5 + strokeHash.x * 0.5) * (0.8 + mids * 0.4);

        let growLen = sLen * smoothstep(0.0, 0.3, age);
        totalInk += stroke(uv, strokeSeed, t, growLen, sWidth, strokeAngle);
    }
    return clamp(totalInk, 0.0, 1.0);
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
    // Mouse introduces invasive species disturbance
    let invasiveBoost = exp(-mouseDist * mouseDist * 25.0) * (1.0 + bass * 2.0);

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

    // Check 3x3 neighborhood of clusters (strokes can bleed over cell edges)
    for (var jj: i32 = -1; jj <= 1; jj++) {
        for (var ii: i32 = -1; ii <= 1; ii++) {
            let neighbor = gridCell + vec2<f32>(f32(ii), f32(jj));
            let clusterSeed = (neighbor + 0.5) / gridScale;

            // Invasive species from mouse boost density locally
            let effectiveDensity = strokeDensity + invasiveBoost * 0.4;
            let ink = glyphCluster(uvA, clusterSeed, t, bass, mids, treble,
                                   effectiveDensity, inkWidth);
            if (ink > 0.0) {
                // Ecosystem color driven by Lotka-Volterra cycles
                // Flora color = green scaled by prey population
                let floraCol = vec3<f32>(0.0, preyBloom, 0.1) * (0.6 + mids * 0.4);
                // Fauna glow = red-orange scaled by predator population
                let faunaCol = vec3<f32>(predatorBloom, predatorBloom * 0.3, 0.0) * (0.5 + treble * 0.5);
                // Mix based on cluster hash for spatial variety
                let clusterHash = hash22(neighbor * 0.1 + 0.5);
                let ecosystemMix = clusterHash.x;
                let clusterCol = mix(floraCol, faunaCol, ecosystemMix);

                inkColor += clusterCol * ink;
                totalInk += ink;
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
        // Neon glow halo
        color += normInkColor * totalInk * neonMode * treble * 0.5;
    }

    // Subtle paper texture
    let paperGrain = hash12(uvA * 200.0) * 0.03 * (1.0 - neonMode);
    color += paperGrain;

    // Mouse invasive species pulse: a bright seed planted by click
    let seedPulse = exp(-mouseDist * mouseDist * 100.0) * (0.5 + bass * 0.5);
    color += mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.8, 0.6, 1.0), neonMode) * seedPulse;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES tone mapping
    color = acesToneMap(color * 1.1);

    // Semantic alpha
    let alpha = clamp(length(color) * 1.2, 0.2, 0.95);

    // Temporal feedback: ecosystem succession
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    let feedback = mix(prev.rgb * 0.96, color, 0.25);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(feedback, 1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0));
}
