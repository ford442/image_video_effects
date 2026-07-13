// ═══════════════════════════════════════════════════════════════════════════════
//  Chrono-Erosion - Feedback Melting
//  Category: generative
//  Description: Datamosh-like flow where video melts along a domain-warped
//               curl-noise vector field with FBM erosion pits, feedback decay,
//               and audio-driven turbulence.
//  Features: audio-reactive, temporal, feedback, domain-warping, curl-noise,
//            erosion-pits, voronoi, aces-tonemap, chromatic-aberration
// ═══════════════════════════════════════════════════════════════════════════════

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

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x), u2.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s = s + a * valueNoise(p * f);
        f = f * 2.0;
        a = a * 0.5;
    }
    return s;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
    return p + strength * q;
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.01;
    let n0 = fbm(p + vec2<f32>(eps, 0.0) + t, 4);
    let n1 = fbm(p - vec2<f32>(eps, 0.0) + t, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps) + t, 4);
    let n3 = fbm(p - vec2<f32>(0.0, eps) + t, 4);
    let dndx = (n0 - n1) / (2.0 * eps);
    let dndy = (n2 - n3) / (2.0 * eps);
    return vec2<f32>(dndy, -dndx);
}

fn voronoi(p: vec2<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 1.0e10;
    var cellId = 0.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = neighbor + hash21(i + neighbor);
            let diff = point - f;
            let d = dot(diff, diff);
            let closer = f32(d < minDist);
            minDist = mix(minDist, d, closer);
            cellId = mix(cellId, hash21(i + neighbor), closer);
        }
    }
    return vec2<f32>(sqrt(minDist), cellId);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let pixel = vec2<i32>(id.xy);
    let uv01 = vec2<f32>(id.xy) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioOverall = bass + mids + treble;

    let decay = u.zoom_params.x * 0.92 + 0.04;
    let flowIntensity = u.zoom_params.y * 0.06 + 0.005;
    let turbulence = u.zoom_params.z * 2.5;
    let feedbackMix = u.zoom_params.w;

    // Domain-warped coordinate for erosion flow
    var wuv = domainWarp(uv * 3.0 + vec2<f32>(time * 0.07, time * 0.05), 0.35 + turbulence * 0.1, 4);
    let flow = curlNoise(wuv, time * 0.12) * flowIntensity;

    // Mouse smudge with SDF falloff
    let mouse = u.zoom_config.yz;
    let mouseDelta = uv01 - mouse;
    let mouseDist = length(mouseDelta);
    let mouseInfluence = smoothstep(0.35, 0.0, mouseDist);
    let mouseFlow = normalize(mouseDelta + vec2<f32>(0.001)) * mouseInfluence * 0.025;
    let totalFlow = flow + mouseFlow;

    // Branchless audio shock - direction from hash
    let shock = max(bass - 0.55, 0.0) * 0.035;
    let shockAngle = time * 7.0 + hash21(uv01 * 20.0 + time) * TAU;
    let shockVec = vec2<f32>(cos(shockAngle), sin(shockAngle)) * shock;

    // Displaced UV with domain-warp feedback
    let displacedUV = clamp(uv01 + (totalFlow + shockVec) * (1.0 + turbulence), vec2<f32>(0.0), vec2<f32>(1.0));

    // Voronoi erosion pits modulate the blend
    let voro = voronoi(uv * 5.0 + fbm(uv * 4.0 + time * 0.1, 3));
    let pit = smoothstep(0.15, 0.0, voro.x) * (0.5 + 0.5 * sin(voro.y * TAU + time));

    let current = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
    let feedback = textureSampleLevel(dataTextureC, u_sampler, displacedUV, 0.0).rgb;
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;

    // Melt blend: current + feedback + erosion pits
    let mixFactor = clamp(decay + pit * 0.15 + feedbackMix * 0.15, 0.0, 1.0);
    var melted = mix(current, feedback, mixFactor);
    melted = mix(melted, melted * (1.0 - pit * 0.35), pit);

    // Flow-magnitude chromatic shift
    let flowMag = length(totalFlow + shockVec) * 25.0;
    let shiftR = melted.r * (1.0 + flowMag * bass);
    let shiftG = melted.g * (1.0 + flowMag * 0.5);
    let shiftB = melted.b * (1.0 - flowMag * 0.25);
    var outCol = vec3<f32>(shiftR, shiftG, shiftB);

    // Branchless color inversion on strong beats
    let invertMix = saturate((audioOverall - 0.85) * 0.6);
    outCol = mix(outCol, vec3<f32>(1.0) - outCol, invertMix);

    // Temporal trail with decay
    let trail = mix(prev * decay, outCol, 0.18 + bass * 0.08);
    outCol = clamp(trail, vec3<f32>(0.0), vec3<f32>(1.5));

    // Chromatic aberration
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001 + flowMag * 0.0003;
    let dir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));
    outCol = vec3<f32>(
        outCol.r + dir.x * caStr,
        outCol.g,
        outCol.b - dir.y * caStr * 0.5
    );

    outCol = acesToneMap(outCol * (0.95 + mids * 0.25));

    let alpha = clamp(luma(outCol) * 1.6 + pit * 0.2, 0.15, 0.95) * (0.75 + depth * 0.25);

    textureStore(dataTextureA, pixel, vec4<f32>(outCol, alpha));
    textureStore(writeTexture, pixel, vec4<f32>(outCol, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
