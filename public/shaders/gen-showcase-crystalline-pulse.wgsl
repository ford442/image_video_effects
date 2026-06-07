// gen-showcase-crystalline-pulse.wgsl
// Showcase shader optimized for: idle animation + mouse claim + audio reactivity
// Geometric crystal formations that grow, pulse, and refract. Mouse creates a disruption
// field that shatters and re-forms crystals. Audio-reactive: bass triggers growth pulses,
// mid controls hue shift, treble adds edge lighting / refraction sparkles.

// 13-binding universal layout
@group(0) @binding(0) var nearestSampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTexture: texture_2d<f32>;
@group(0) @binding(5) var nearestClampSampler: sampler;
@group(0) @binding(6) var depthWriteTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_storage_2d<rgba32float, write>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var videoTexture: texture_2d<f32>;
@group(0) @binding(12) var videoSampler: sampler;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

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
fn voronoi(p: vec2<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var minDist = 1.0;
    var cellId = vec2<f32>(0.0);
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let g = vec2<f32>(f32(x), f32(y));
            let o = hash22(n + g);
            let r = g + o - f;
            let d = dot(r, r);
            if (d < minDist) {
                minDist = d;
                cellId = n + g + o;
            }
        }
    }
    return vec2<f32>(sqrt(minDist), hash12(cellId));
}

fn palette(t: f32) -> vec3<f32> {
    // Ice blue → teal → emerald → sapphire
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 0.9);
    let d = vec3<f32>(0.55, 0.66, 0.77);
    return a + b * cos(TAU * (c * t + d));
}

fn edgeGlow(d: f32, thickness: f32) -> f32 {
    return smoothstep(thickness, 0.0, d) - smoothstep(0.0, -thickness, d);
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let texel = vec2<f32>(id.xy);
    let uv = texel / dims;

    let t = u.config.x;
    let mouseDown = u.zoom_config.w;
    let mouse = u.zoom_config.yz;

    let bass = extraBuffer[0];
    let mids = extraBuffer[1];
    let treble = extraBuffer[2];
    let overall = (bass + mids + treble) / 3.0;

    let density = u.zoom_params.x;
    let shardSize = u.zoom_params.y;
    let glow = u.zoom_params.z;
    let chaos = u.zoom_params.w;

    let p = (uv - 0.5) * 2.0;
    let aspect = dims.x / dims.y;
    p.x *= aspect;

    let mousePos = (mouse - 0.5) * 2.0;
    mousePos.x *= aspect;
    let mDist = length(p - mousePos);
    let mouseInfluence = exp(-mDist * 4.0) * mouseDown;

    // Crystal grid: voronoi cells with time-evolving centers
    let gridScale = 3.0 + density * 5.0;
    var gp = p * gridScale;

    // Mouse disruption: push cell coordinates away from mouse
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

    // Crystal shape: faceted interior
    let crystalEdge = smoothstep(0.0, 0.3 + shardSize * 0.2, cellDist);
    let crystalInterior = 1.0 - crystalEdge;

    // Growth pulse from bass
    let growth = sin(cellHash * TAU + t * 0.5 + bass * 3.0) * 0.5 + 0.5;
    let crystalSize = crystalInterior * (0.5 + growth * 0.5);

    // Color per cell with hue rotation from mids
    let colorT = cellHash + t * 0.02 + mids * 0.3;
    var col = palette(colorT);

    // Interior depth gradient
    col *= 0.6 + crystalSize * 0.4;

    // Edge glow
    let edge = edgeGlow(cellDist - 0.15, 0.03 + glow * 0.05);
    col += edge * vec3<f32>(0.4, 0.7, 1.0) * glow * (1.0 + treble * 2.0);

    // Treble refraction sparkles at crystal edges
    let sparkle = hash12(floor(p * 120.0 + t * 0.01)).x;
    let sparkleGlow = smoothstep(0.98, 1.0, sparkle) * treble * 3.0 * edge;
    col += vec3<f32>(0.8, 0.9, 1.0) * sparkleGlow;

    // Bass pulse: whole scene brightens on beats
    col *= 1.0 + bass * 0.3;

    // Mouse disruption glow
    if (mouseDown > 0.5) {
        let disruptGlow = exp(-mDist * 3.0) * 0.4;
        col += vec3<f32>(0.2, 0.6, 1.0) * disruptGlow;
    }

    // Background: dark space between crystals
    let bg = 0.05 + 0.02 * fbm(p * 2.0 + t * 0.01, 3);
    col = mix(vec3<f32>(bg, bg, bg * 1.2), col, crystalSize + edge * 0.3);

    // Vignette
    let vig = 1.0 - smoothstep(0.5, 1.5, length(p));
    col *= vig;

    let final = vec4<f32>(col * (0.8 + overall * 0.2), 1.0);
    textureStore(writeTexture, id.xy, final);
    textureStore(depthWriteTexture, id.xy, vec4<f32>(crystalSize, 0.0, 0.0, 1.0));
}
