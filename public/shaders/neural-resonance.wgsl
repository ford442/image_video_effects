// ────────────────────────────────────────────────────────────────────────────────
//  Neural Resonance - Pareidolia Feedback Shader
//  Runaway neural feedback loop with hallucinogenic pareidolic effects.
//  Creates breathing fractal scales, watching eyes, spiraling vortices.
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
// ────────────────────────────────────────────────────────────────────────────────

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=contrastBoost, y=evolutionSpeed, z=seedStrength, w=depthMod
  zoom_params: vec4<f32>,       // x=amplification, y=curlStrength, z=feedbackMix, w=chromaticDrift
  ripples:     array<vec4<f32>, 50>,
};

// ───────────────────────────────────────────────────────────────────────────────
//  Calculate luminance for curl noise
// ───────────────────────────────────────────────────────────────────────────────
fn luminance(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
}

// ───────────────────────────────────────────────────────────────────────────────
//  Calculate gradient of luminance (4 texture samples)
// ───────────────────────────────────────────────────────────────────────────────
fn luminanceGradient(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
    let l0 = luminance(textureSampleLevel(feedbackTex, videoSampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rgb);
    let l1 = luminance(textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb);
    let l2 = luminance(textureSampleLevel(feedbackTex, videoSampler, uv - vec2<f32>(0.0, texel.y), 0.0).rgb);
    let l3 = luminance(textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb);
    return vec2<f32>(l1 - l0, l3 - l2);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Calculate curl (2D rotation) from gradient derivatives
// ───────────────────────────────────────────────────────────────────────────────
fn curlNoise(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    let gx0 = luminanceGradient(uv - vec2<f32>(texel.x, 0.0), texel);
    let gx1 = luminanceGradient(uv + vec2<f32>(texel.x, 0.0), texel);
    let gy0 = luminanceGradient(uv - vec2<f32>(0.0, texel.y), texel);
    let gy1 = luminanceGradient(uv + vec2<f32>(0.0, texel.y), texel);

    // Curl is z-component of cross product of gradients
    return (gy1.x - gy0.x - gx1.y + gx0.y) * 0.5;
}

// ───────────────────────────────────────────────────────────────────────────────
//  Gaussian blur (3x3 for performance)
// ───────────────────────────────────────────────────────────────────────────────
fn gaussianBlur3x3(uv: vec2<f32>, texel: vec2<f32>, radius: f32) -> vec3<f32> {
    var sum = vec3<f32>(0.0);
    let scale = texel * radius;
    
    // 3x3 Gaussian weights (sigma ≈ 0.8)
    sum += textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(-scale.x, -scale.y), 0.0).rgb * 0.0625;
    sum += textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(0.0, -scale.y), 0.0).rgb * 0.125;
    sum += textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(scale.x, -scale.y), 0.0).rgb * 0.0625;
    sum += textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(-scale.x, 0.0), 0.0).rgb * 0.125;
    sum += textureSampleLevel(feedbackTex, videoSampler, uv, 0.0).rgb * 0.25;
    sum += textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(scale.x, 0.0), 0.0).rgb * 0.125;
    sum += textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(-scale.x, scale.y), 0.0).rgb * 0.0625;
    sum += textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(0.0, scale.y), 0.0).rgb * 0.125;
    sum += textureSampleLevel(feedbackTex, videoSampler, uv + vec2<f32>(scale.x, scale.y), 0.0).rgb * 0.0625;
    
    return sum;
}

// ───────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ───────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = textureDimensions(videoTex);
    let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
        return;
    }

    let uv = vec2<f32>(gid.xy) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    // ──────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ──────────────────────────────────────────────────────────────────────────
    let amplification = u.zoom_params.x * 1.0 + 1.2;        // 1.2 - 2.2
    let curlStrength = u.zoom_params.y * 0.02;               // 0 - 0.02
    let feedbackMix = u.zoom_params.z * 0.1 + 0.9;          // 0.9 - 1.0
    let chromaticDrift = u.zoom_params.w * 0.004;           // 0 - 0.004
    let contrastBoost = u.zoom_config.x * 0.5;              // 0 - 0.5
    let evolutionSpeed = u.zoom_config.y * 2.0 + 1.0;       // 1 - 3
    let seedStrength = u.zoom_config.z * 0.1 + 0.02;        // 0.02 - 0.12
    let depthMod = u.zoom_config.w;                          // 0 - 1

    // ──────────────────────────────────────────────────────────────────────────
    //  Sample inputs
    // ──────────────────────────────────────────────────────────────────────────
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    let videoSample = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let prevFrame = textureSampleLevel(feedbackTex, videoSampler, uv, 0.0).rgb;

    // Depth-modulated kernel radius
    let kernelRadius = mix(1.0, 3.0, depth * depthMod);

    // ──────────────────────────────────────────────────────────────────────────
    //  Iterative Unsharp Masking (Laplacian detail enhancement)
    // ──────────────────────────────────────────────────────────────────────────
    let blurred = gaussianBlur3x3(uv, texel, kernelRadius);
    let detail = prevFrame - blurred;
    
    // Amplify detail with temporal variation for breathing effect
    let ampMod = amplification + sin(time * 0.5) * 0.2;
    let enhancedDetail = detail * ampMod;
    
    // Positive feedback: add detail back
    var result = prevFrame + enhancedDetail;

    // ──────────────────────────────────────────────────────────────────────────
    //  Curl-Noise Domain Warping (DeepDream swirl effect)
    // ──────────────────────────────────────────────────────────────────────────
    let curl = curlNoise(uv, texel);
    let curlAmt = curlStrength * (1.0 + depth * 2.0); // Stronger in background
    
    // Rotation matrix from curl
    let angle = curl * curlAmt;
    let cosA = cos(angle);
    let sinA = sin(angle);

    // ──────────────────────────────────────────────────────────────────────────
    //  Chromatic Aberration Drift (rainbow edges)
    // ──────────────────────────────────────────────────────────────────────────
    let timeOffset = time * 0.1;
    let baseR = vec2<f32>(sin(timeOffset), cos(timeOffset)) * chromaticDrift;
    let baseG = vec2<f32>(cos(timeOffset * 1.3), -sin(timeOffset * 1.3)) * chromaticDrift * 0.5;
    let baseB = vec2<f32>(-sin(timeOffset * 0.7), cos(timeOffset * 0.7)) * chromaticDrift * 0.75;
    
    // Apply curl rotation to chromatic offsets
    let offsetR = vec2<f32>(baseR.x * cosA - baseR.y * sinA, baseR.x * sinA + baseR.y * cosA);
    let offsetG = vec2<f32>(baseG.x * cosA - baseG.y * sinA, baseG.x * sinA + baseG.y * cosA);
    let offsetB = vec2<f32>(baseB.x * cosA - baseB.y * sinA, baseB.x * sinA + baseB.y * cosA);
    
    // Sample with chromatic aberration
    let sampleR = textureSampleLevel(feedbackTex, videoSampler, uv + offsetR, 0.0).r;
    let sampleG = textureSampleLevel(feedbackTex, videoSampler, uv + offsetG, 0.0).g;
    let sampleB = textureSampleLevel(feedbackTex, videoSampler, uv + offsetB, 0.0).b;
    let warpedColor = vec3<f32>(sampleR, sampleG, sampleB);
    
    // Blend warped feedback with enhanced result
    result = mix(result, warpedColor, 0.3);

    // ──────────────────────────────────────────────────────────────────────────
    //  Seed with video input (prevents noise takeover)
    // ──────────────────────────────────────────────────────────────────────────
    result = mix(result, videoSample, seedStrength);

    // ──────────────────────────────────────────────────────────────────────────
    //  Temporal Evolution (breathing patterns)
    // ──────────────────────────────────────────────────────────────────────────
    let evolution = sin(time * evolutionSpeed + uv.x * 10.0) * cos(time * evolutionSpeed * 0.85 + uv.y * 7.0) * 0.05;
    result = result * (1.0 + evolution);

    // ──────────────────────────────────────────────────────────────────────────
    //  Depth-based contrast enhancement
    // ──────────────────────────────────────────────────────────────────────────
    let contrast = 1.0 + depth * contrastBoost;
    result = pow(max(result, vec3<f32>(0.001)), vec3<f32>(contrast));

    // ──────────────────────────────────────────────────────────────────────────
    //  Output (HDR allowed for glow effects)
    // ──────────────────────────────────────────────────────────────────────────
    textureStore(outTex, gid.xy, vec4<f32>(result, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(feedbackOut, gid.xy, vec4<f32>(result, 1.0));
}
