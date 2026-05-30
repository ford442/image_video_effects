// ═══════════════════════════════════════════════════════════════════
//  Emergent Script Gardens
//  Category: generative
//  Description: Interacting calligraphic strokes self-organize into
//  alien symbolic gardens. Mouse plants stroke seeds. Audio controls
//  curvature, length, and local interaction rules.
//  Complexity: Medium-High
//  Created: 2026-05-31
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
    let w = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), w.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), w.x),
        w.y
    );
}

fn ruleAngle(p: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32, curvature: f32) -> f32 {
    let slow = smoothNoise(p * 2.0 + vec2<f32>(t * 0.06, -t * 0.04));
    let local = smoothNoise(p * (4.0 + mids * 3.0) + vec2<f32>(-t * 0.11, t * 0.09));
    let script = smoothNoise(p * 9.0 + vec2<f32>(t * 0.21, t * 0.17));
    return (slow - 0.5) * TAU + (local - 0.5) * PI * curvature + (script - 0.5) * treble * PI + bass * 0.4;
}

fn brushStroke(uv: vec2<f32>, seed: vec2<f32>, lengthScale: f32, inkWidth: f32, angle: f32, bend: f32) -> f32 {
    let d = uv - seed;
    let ca = cos(angle);
    let sa = sin(angle);
    let along = d.x * ca + d.y * sa;
    let curvedAcross = -d.x * sa + d.y * ca + sin(along * 22.0 + bend) * inkWidth * 1.6;
    let body = smoothstep(0.0, 0.018, along) * smoothstep(lengthScale + 0.02, lengthScale, along);
    let taper = pow(sin(clamp(along / max(lengthScale, 0.001), 0.0, 1.0) * PI), 0.65);
    let width = smoothstep(inkWidth, 0.0, abs(curvedAcross)) * taper;
    return body * width;
}

fn glyphGarden(uv: vec2<f32>, cluster: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32,
               strokeDensity: f32, curvature: f32, inkWidth: f32) -> f32 {
    var ink = 0.0;
    let count = i32(clamp(4.0 + strokeDensity * 8.0 + treble * 2.0, 4.0, 14.0));
    let clusterHash = hash22(cluster * 13.7 + 0.4);
    let bloom = smoothstep(0.0, 0.45, fract(t * 0.06 + clusterHash.x));

    for (var i: i32 = 0; i < count; i++) {
        let fi = f32(i);
        let h = hash22(cluster + vec2<f32>(fi * 0.71, fi * 1.37));
        let orbit = vec2<f32>(cos(h.x * TAU), sin(h.x * TAU)) * h.y * 0.055 * (1.0 + mids * 0.45);
        let seed = cluster + orbit;
        let angle = ruleAngle(seed, t + fi * 0.3, bass, mids, treble, curvature) + (h.x - 0.5) * PI * 0.7;
        let len = (0.028 + h.y * 0.07 + bass * 0.025) * bloom;
        let bend = t * (0.5 + mids) + fi + h.x * TAU;
        ink += brushStroke(uv, seed, len, inkWidth * (0.65 + h.x * 0.8), angle, bend);
    }

    return clamp(ink, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let p = vec2<f32>(uv.x * aspect, uv.y);
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let strokeDensity = u.zoom_params.x;
    let curvature = mix(0.2, 1.8, u.zoom_params.y) * (1.0 + mids * 0.35);
    let gardenScale = mix(4.0, 11.0, u.zoom_params.z);
    let palette = u.zoom_params.w;
    let inkWidth = mix(0.0035, 0.014, strokeDensity) * (1.0 + mids * 0.25);

    let mouse = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
    let mouseDown = step(0.5, u.zoom_config.w);
    let mouseDist = length(p - mouse);
    let plantedSeed = exp(-mouseDist * mouseDist * 70.0) * (0.35 + bass * 0.65) * (0.35 + mouseDown * 0.65);

    let grid = p * gardenScale;
    let cell = floor(grid);
    var totalInk = 0.0;
    var chroma = vec3<f32>(0.0);

    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            let neighbor = cell + vec2<f32>(f32(x), f32(y));
            let jitter = (hash22(neighbor + 2.17) - 0.5) * 0.35;
            let cluster = (neighbor + 0.5 + jitter) / gardenScale;
            let mouseBoost = exp(-length(cluster - mouse) * length(cluster - mouse) * 24.0) * 0.55;
            let ink = glyphGarden(p, cluster, time, bass, mids, treble,
                                  clamp(strokeDensity + mouseBoost, 0.0, 1.0), curvature, inkWidth);
            if (ink > 0.0) {
                let h = hash22(neighbor * 0.23 + 0.5);
                let hue = h.x + time * 0.018 + bass * 0.1;
                let clusterColor = vec3<f32>(
                    0.5 + 0.5 * cos(hue * TAU),
                    0.5 + 0.5 * cos(hue * TAU + 2.094),
                    0.5 + 0.5 * cos(hue * TAU + 4.189)
                );
                chroma += clusterColor * ink;
                totalInk += ink;
            }
        }
    }

    let prev = textureLoad(dataTextureC, coord, 0);
    let persistence = mix(0.74, 0.91, palette) + bass * 0.03;
    totalInk = clamp(max(totalInk + plantedSeed, prev.a * persistence), 0.0, 1.0);

    let normalizedChroma = chroma / max(dot(chroma, vec3<f32>(0.3333)), 0.001);
    let paper = vec3<f32>(0.94, 0.91, 0.84) + hash12(p * 260.0) * 0.025;
    let night = vec3<f32>(0.012, 0.014, 0.035);
    let background = mix(paper, night, palette);
    let inkColor = mix(vec3<f32>(0.055, 0.045, 0.065), normalizedChroma * 0.75 + vec3<f32>(0.16, 0.09, 0.22), palette);
    var color = mix(background, inkColor, smoothstep(0.02, 0.72, totalInk));
    color += normalizedChroma * totalInk * palette * (0.35 + treble * 0.55);
    color += vec3<f32>(0.7, 0.55, 1.0) * plantedSeed * palette;

    let alpha = clamp(totalInk * (0.35 + palette * 0.55) + plantedSeed * 0.25, 0.0, 1.0);
    textureStore(dataTextureA, gid.xy, vec4<f32>(color, alpha));
    textureStore(writeTexture, gid.xy, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(totalInk, 0.0, 0.0, 0.0));
}
