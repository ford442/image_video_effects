// ────────────────────────────────────────────────────────────────────────────────
//  Liquid Warp Interactive
//  Fluid-like distortion driven by mouse flow and noise.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// Simple noise function
fn hash(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let pi = floor(p);
    let pf = fract(p);
    let w = pf * pf * (3.0 - 2.0 * pf);
    return mix(mix(dot(hash(pi + vec2<f32>(0.0, 0.0)), pf - vec2<f32>(0.0, 0.0)),
                   dot(hash(pi + vec2<f32>(1.0, 0.0)), pf - vec2<f32>(1.0, 0.0)), w.x),
               mix(dot(hash(pi + vec2<f32>(0.0, 1.0)), pf - vec2<f32>(0.0, 1.0)),
                   dot(hash(pi + vec2<f32>(1.0, 1.0)), pf - vec2<f32>(1.0, 1.0)), w.x), w.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    // Params
    let distortAmt = u.zoom_params.x * 0.1;
    let flowSpeed = u.zoom_params.y;
    let scale = u.zoom_params.z * 10.0 + 2.0;
    // let viscosity = u.zoom_params.w; // Unused for now, maybe for color mixing?

    let mouse = u.zoom_config.yz;
    let click = u.zoom_config.w;

    // Base flow noise
    let n1 = noise(uv * scale + vec2<f32>(time * flowSpeed, time * flowSpeed * 0.5));
    let n2 = noise(uv * scale - vec2<f32>(time * flowSpeed * 0.7, time * flowSpeed));

    var flow = vec2<f32>(n1, n2);

    // Mouse Interaction: Displace flow away from mouse or swirl
    let mVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let mDist = length(mVec);
    let mForce = smoothstep(0.3, 0.0, mDist) * 0.2; // stronger near mouse

    // Add mouse influence to flow
    flow += (mVec / (mDist + 0.001)) * mForce * (1.0 + click * 2.0);

    // Distorted UV
    let distUV = uv + flow * distortAmt;

    // Sample with distorted UV
    let color = textureSampleLevel(videoTex, videoSampler, distUV, 0.0).rgb;

    // Slight chromatic aberration based on flow intensity
    let r = textureSampleLevel(videoTex, videoSampler, distUV + flow * 0.005, 0.0).r;
    let b = textureSampleLevel(videoTex, videoSampler, distUV - flow * 0.005, 0.0).b;

    let finalColor = vec3<f32>(r, color.g, b);

    textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
}
