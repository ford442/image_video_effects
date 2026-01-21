// ────────────────────────────────────────────────────────────────────────────────
//  Digital Haze
//  A thick pixelated fog that obscures the image, cleared by the mouse cursor.
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    let mouse = u.zoom_config.yz;
    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    // Params
    let pixelStrength = u.zoom_params.x * 100.0 + 10.0; // Grid size roughly
    let clearRadius = u.zoom_params.y * 0.4 + 0.05;
    let noiseAmt = u.zoom_params.z;

    // Calculate Grid
    // We want the pixelation to be coarse far away, and fine/none near mouse.

    // Mask: 0.0 near mouse (clear), 1.0 far away (haze)
    let mask = smoothstep(clearRadius, clearRadius + 0.2, dist);

    // Dynamic Pixelation
    // If mask is 0, we want UV. If mask is 1, we want quantized UV.
    // However, mixing UVs directly can cause tearing.
    // Instead, let's sample both and mix colors.

    // Haze Layer (Pixelated + Noise)
    let gridSize = vec2<f32>(pixelStrength * aspect, pixelStrength);
    let quantizedUV = floor(uv * gridSize) / gridSize;

    // Add some digital noise to the quantized UV
    let seed = quantizedUV + vec2<f32>(time * 0.1, time * 0.05);
    let noiseVal = (hash(seed) - 0.5) * noiseAmt * 0.05;

    let hazeUV = quantizedUV + noiseVal;

    let colClear = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let colHaze = textureSampleLevel(videoTex, videoSampler, hazeUV, 0.0).rgb;

    // Apply a "digital" tint to the haze
    let greenTint = vec3<f32>(0.0, 0.1, 0.0) * noiseAmt;
    let finalHaze = colHaze + greenTint;

    let finalColor = mix(colClear, finalHaze, mask);

    textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
}
