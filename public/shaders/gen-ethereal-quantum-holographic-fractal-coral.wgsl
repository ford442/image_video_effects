// ----------------------------------------------------------------
// Ethereal Quantum-Holographic Fractal-Coral
// Category: generative
// ----------------------------------------------------------------

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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // params mapped from UI
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Cellular/Voronoi Noise approximation
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453) * 2.0 - 1.0;
}

fn voronoi(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    var res = 8.0;
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash3(p + b) * 0.5 + 0.5;
                let d = dot(r, r);
                res = min(res, d);
            }
        }
    }
    return sqrt(res);
}

// smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// parameters mapped from UI
// zoom_params.x = Fractal Density (1.0 to 8.0)
// zoom_params.y = Holographic Frequency (1.0 to 20.0)
// zoom_params.z = Bio-Luminescence Intensity (0.0 to 3.0)
// zoom_params.w = Audio Pulse Propagation (0.5 to 5.0)

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    let t = u.config.x * 0.2;

    // Audio input (low frequency energy)
    let audioEnergy = plasmaBuffer[0].x * u.zoom_params.w;

    // Mouse attraction
    let mouse = u.zoom_config.yz * 2.0 - 1.0; // center mapped
    p = p - vec3<f32>(mouse.x * 2.0, -mouse.y * 2.0, 0.0) * exp(-length(p) * 0.5);

    // KIFS setup
    var d = 1000.0;
    var scale = 1.0;
    let iterations = i32(min(floor(u.zoom_params.x) + i32(audioEnergy * 2.0), 10.0));

    let fold = vec3<f32>(1.5, 1.2, 1.5) + vec3<f32>(sin(t), cos(t * 0.8), sin(t * 1.2)) * 0.1;

    for (var i = 0; i < iterations; i++) {
        p = abs(p);
        p = p - fold;

        let rotMatrix1 = rot(t * 0.3 + f32(i) * 0.2);
        let rotMatrix2 = rot(t * 0.5 - f32(i) * 0.3);

        p = vec3<f32>(rotMatrix1 * p.xy, p.z);
        p = vec3<f32>(p.x, rotMatrix2 * p.yz);

        let r2 = dot(p, p);
        let s = max(0.5, 2.0 / clamp(r2, 0.1, 1.0));
        p = p * s;
        scale = scale * s;
    }

    // Base geometry is a sphere/cylinder combination in folded space
    let baseGeom = (length(p) - 1.2) / scale;

    // Combine with voronoi noise to make it organic coral-like
    let noiseFreq = u.zoom_params.y;
    let organicNoise = voronoi(p_in * noiseFreq + t) * 0.1;

    d = smin(baseGeom, baseGeom + organicNoise, 0.2);

    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

// Holographic color palette generator
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var p = ro;
    var tDist = 0.0;
    var d = 0.0;
    var col = vec3<f32>(0.0);

    var glow = 0.0;
    let maxGlow = u.zoom_params.z;
    let audioEnergy = plasmaBuffer[0].x;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * tDist;
        d = map(p);

        if (d < SURF_DIST) {
            break;
        }
        if (tDist > MAX_DIST) {
            break;
        }

        tDist = tDist + d;
        // Accumulate volumetric glow based on proximity and audio
        glow = glow + (0.01 / (0.01 + abs(d))) * (0.1 + audioEnergy * 0.5);
    }

    if (tDist < MAX_DIST) {
        let n = calcNormal(p);
        let viewDir = -rd;

        // Fresnel for holographic effect
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 2.0);

        // Base color from position and normal
        let holoFreq = u.zoom_params.y * 0.1;
        let c1 = palette(length(p) * holoFreq + u.config.x * 0.5,
                         vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));

        // Chromatic interference
        let interference = sin(dot(n, vec3<f32>(1.0)) * 10.0 + u.config.x) * 0.5 + 0.5;

        col = mix(c1, vec3<f32>(1.0), fresnel * interference);

        // Audio reactive pulsing from the interior
        col = col + vec3<f32>(0.2, 0.8, 1.0) * audioEnergy * maxGlow * fresnel;
    }

    // Add volumetric glow (scattering)
    col = col + vec3<f32>(0.1, 0.5, 0.8) * glow * 0.05 * maxGlow;

    // Background fog / attenuation
    col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.02 * tDist));

    return clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    let uv = (fragCoord * 2.0 - res) / min(res.x, res.y);

    // Camera setup
    let camTime = u.config.x * 0.1;
    let ro = vec3<f32>(sin(camTime) * 3.0, cos(camTime) * 2.0, -5.0 + sin(camTime * 0.5));
    let target = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(target - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));

    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    let col = render(ro, rd);

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
