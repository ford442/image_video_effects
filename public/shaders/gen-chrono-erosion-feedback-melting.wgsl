// ═══════════════════════════════════════════════════════════════════════════════
//  Chrono-Erosion - Feedback Melting
//  Category: artistic
//  Description: Datamosh-like flow where video melts along a curl-noise
//               vector field with feedback decay and audio-driven turbulence.
//  Features: audio-reactive, temporal, feedback
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.01;
    let n0 = noise(p + vec2<f32>(eps, 0.0) + t);
    let n1 = noise(p - vec2<f32>(eps, 0.0) + t);
    let n2 = noise(p + vec2<f32>(0.0, eps) + t);
    let n3 = noise(p - vec2<f32>(0.0, eps) + t);
    let dndx = (n0 - n1) / (2.0 * eps);
    let dndy = (n2 - n3) / (2.0 * eps);
    return vec2<f32>(dndy, -dndx);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let audioOverall = plasmaBuffer[0].x + plasmaBuffer[0].y + plasmaBuffer[0].z;

    // Parameters
    let decay = u.zoom_params.x * 0.9 + 0.05;
    let flowIntensity = u.zoom_params.y * 0.05 + 0.005;
    let turbulence = u.zoom_params.z * 2.0;
    let feedbackMix = u.zoom_params.w;

    // Curl-noise flow field
    var flow = curlNoise(uv * 3.0, time * 0.1) * flowIntensity;

    // Mouse smudge
    let mouse = u.zoom_config.yz;
    let mouseDelta = uv - mouse;
    let mouseDist = length(mouseDelta);
    let mouseInfluence = smoothstep(0.3, 0.0, mouseDist);
    flow = flow + normalize(mouseDelta + vec2<f32>(0.001)) * mouseInfluence * 0.02;

    // Audio turbulence spikes
    if (bass > 0.6) {
        let shock = bass * 0.03;
        let shockAngle = time * 7.0 + hash(uv * 10.0) * 6.28318;
        flow = flow + vec2<f32>(cos(shockAngle), sin(shockAngle)) * shock;
    }

    // Displaced UV for feedback sample
    let displacedUV = clamp(uv + flow * (1.0 + turbulence), vec2<f32>(0.0), vec2<f32>(1.0));

    // Read current frame and feedback
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let feedback = textureSampleLevel(dataTextureC, u_sampler, displacedUV, 0.0).rgb;

    // Melt blend: weighted mix with decay
    let melted = mix(current, feedback, decay);

    // Color shift based on flow magnitude
    let flowMag = length(flow) * 20.0;
    let shiftR = melted.r * (1.0 + flowMag * bass);
    let shiftG = melted.g * (1.0 + flowMag * 0.5);
    let shiftB = melted.b * (1.0 - flowMag * 0.3);

    var outCol = vec3<f32>(shiftR, shiftG, shiftB);

    // Audio-reactive color inversion on strong beats
    if (audioOverall > 0.7) {
        outCol = mix(outCol, vec3<f32>(1.0) - outCol, (audioOverall - 0.7) * 0.5);
    }

    outCol = clamp(outCol, vec3<f32>(0.0), vec3<f32>(1.5));

    // Write feedback to dataTextureA for next frame
    textureStore(dataTextureA, id.xy, vec4<f32>(outCol, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, id.xy, vec4<f32>(outCol, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
