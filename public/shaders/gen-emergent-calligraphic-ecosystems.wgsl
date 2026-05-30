// ═══════════════════════════════════════════════════════════════════
//  Emergent Calligraphic Ecosystems
//  Category: generative
//  Description: Interacting strokes following local orientation rules
//  spontaneously form complex alien writing systems. Mouse plants seeds
//  or disturbs regions. Audio influences stroke behavior and interaction.
//  Complexity: Medium-High
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
    // Combine noise layers for complex flow topology
    return (n1 * 2.0 - 1.0) * PI + n2 * mids * 2.0 + n3 * bass * PI;
}

// Stroke primitive: a curved brushstroke from a seed
fn stroke(uv: vec2<f32>, seed: vec2<f32>, t: f32, strokeLen: f32,
          inkWidth: f32, orientation: f32) -> f32 {
    let d = uv - seed;
    // Project onto stroke axis
    let along = d.x * cos(orientation) + d.y * sin(orientation);
    let across = -d.x * sin(orientation) + d.y * cos(orientation);

    // Stroke bounded along its length, thin across
    let inLength = smoothstep(0.0, 0.1, along) * smoothstep(strokeLen + 0.05, strokeLen, along);
    // Taper at ends (calligraphic pressure modulation)
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
    let clusterBirth = seedHash.x * 5.0; // staggered appearance
    let age = clamp(t * 0.2 - clusterBirth, 0.0, 1.0);
    if (age <= 0.0) { return 0.0; }

    for (var k = 0; k < numStrokes; k++) {
        let kf = f32(k);
        let strokeHash = hash22(clusterSeed + vec2<f32>(kf * 0.37, kf * 0.73));
        // Position within cluster (slight spread)
        let localOffset = (strokeHash - 0.5) * 0.08 * (1.0 + mids * 0.5);
        let strokeSeed = clusterSeed + localOffset;

        // Orientation from flow field + stroke-specific perturbation
        let baseAngle = flowAngle(clusterSeed, t * 0.5, mids, bass);
        let strokeAngle = baseAngle + (strokeHash.x - 0.5) * PI * 0.6 +
                          treble * PI * 0.3 * sin(t * 2.0 + kf);

        // Stroke length varies with audio
        let sLen = 0.02 + strokeHash.y * 0.06 + bass * 0.02;
        let sWidth = inkWidth * (0.5 + strokeHash.x * 0.5) * (0.8 + mids * 0.4);

        // Growth animation
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

    let strokeDensity = u.zoom_params.x;                // 0..1
    let inkWidth      = u.zoom_params.y * 0.012 + 0.003; // 0.003..0.015
    let complexity    = u.zoom_params.z * 2.0 + 1.0;    // 1..3 glyph scale
    let neonMode      = u.zoom_params.w;                 // 0=ink, 1=neon

    let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
    let mouseDist = length(uvA - mousePos);
    // Mouse disturbs flow near cursor: inflates stroke density
    let mouseBoost = exp(-mouseDist * mouseDist * 20.0) * (1.0 + bass * 2.0);

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

            let effectiveDensity = strokeDensity + mouseBoost * 0.4;
            let ink = glyphCluster(uvA, clusterSeed, t, bass, mids, treble,
                                   effectiveDensity, inkWidth);
            if (ink > 0.0) {
                // Color per cluster based on its seed
                let clusterHash = hash22(neighbor * 0.1 + 0.5);
                let hue = clusterHash.x + t * 0.02 + bass * 0.15;
                let clusterCol = vec3<f32>(
                    0.5 + 0.5 * cos(hue * TAU),
                    0.5 + 0.5 * cos(hue * TAU + 2.094),
                    0.5 + 0.5 * cos(hue * TAU + 4.189)
                );
                inkColor += clusterCol * ink;
                totalInk += ink;
            }
        }
    }

    // Background: paper-like cream or dark void
    let bgPaper = mix(
        vec3<f32>(0.95, 0.93, 0.88),  // cream paper
        vec3<f32>(0.02, 0.02, 0.05),  // dark void
        neonMode
    );

    // Ink / neon color
    let inkCol = mix(
        vec3<f32>(0.05, 0.05, 0.08),  // dark ink
        inkColor * 1.5 + vec3<f32>(0.3, 0.2, 0.4) * treble, // neon
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

    // Mouse seed pulse: a bright seed planted by click
    let seedPulse = exp(-mouseDist * mouseDist * 100.0) * (0.5 + bass * 0.5);
    color += mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.8, 0.6, 1.0), neonMode) * seedPulse;

    textureStore(writeTexture, global_id.xy, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
