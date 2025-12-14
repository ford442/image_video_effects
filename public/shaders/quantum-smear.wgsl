// ────────────────────────────────────────────────────────────────────────────────
//  Quantum Smear - Granular Physics Shader
//  Quantum particle disintegration with stochastic advection and entropy injection.
//  Objects dissolve into pointillist particle clouds that reassemble when motion stops.
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
  zoom_config: vec4<f32>,       // x=voidStrength, y=foamIntensity, z=shimmerAmt, w=depthMod
  zoom_params: vec4<f32>,       // x=scatterRadius, y=entropyScale, z=coherenceStr, w=densityBoost
  ripples:     array<vec4<f32>, 50>,
};

// ───────────────────────────────────────────────────────────────────────────────
//  Hash function for pseudo-random numbers
// ───────────────────────────────────────────────────────────────────────────────
fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    p2 = fract(sin(p2) * 43758.5453);
    return p2 * 2.0 - 1.0; // Return range [-1, 1]
}

fn hash1(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Calculate motion difference between frames
// ───────────────────────────────────────────────────────────────────────────────
fn calculateMotion(current: vec3<f32>, previous: vec3<f32>) -> f32 {
    let diff = current - previous;
    return length(diff) * 2.0; // Amplify motion sensitivity
}

// ───────────────────────────────────────────────────────────────────────────────
//  Stochastic advection with entropy
// ───────────────────────────────────────────────────────────────────────────────
fn stochasticAdvect(uv: vec2<f32>, entropy: f32, depth: f32, baseRadius: f32, entropyScale: f32, time: f32) -> vec2<f32> {
    // Base scatter radius based on depth
    let radius = mix(0.005, baseRadius, depth); // Background = larger scatter
    
    // Add temporal noise
    let noise = hash2(uv * 100.0 + vec2<f32>(time * 0.3, time * 0.7));
    
    // Scale by entropy (motion energy)
    let scale = 1.0 + entropy * entropyScale;
    
    // Create stochastic offset
    let offset = noise * radius * scale;
    
    return uv + offset;
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
    let time = u.config.x;

    // ──────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ──────────────────────────────────────────────────────────────────────────
    let scatterRadius = u.zoom_params.x * 0.15 + 0.01;      // 0.01 - 0.16
    let entropyScale = u.zoom_params.y * 8.0 + 2.0;         // 2 - 10
    let coherenceStr = u.zoom_params.z * 0.15 + 0.03;       // 0.03 - 0.18
    let densityBoost = u.zoom_params.w * 3.0 + 1.0;         // 1 - 4
    let voidStrength = u.zoom_config.x * 0.3;               // 0 - 0.3
    let foamIntensity = u.zoom_config.y * 0.4;              // 0 - 0.4
    let shimmerAmt = u.zoom_config.z * 0.05;                // 0 - 0.05
    let depthMod = u.zoom_config.w;                          // 0 - 1

    // ──────────────────────────────────────────────────────────────────────────
    //  Sample inputs
    // ──────────────────────────────────────────────────────────────────────────
    let videoSample = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    let prevFeedback = textureSampleLevel(feedbackTex, videoSampler, uv, 0.0).rgb;

    // ──────────────────────────────────────────────────────────────────────────
    //  Calculate motion entropy at this pixel
    // ──────────────────────────────────────────────────────────────────────────
    let motion = calculateMotion(videoSample, prevFeedback);

    // ──────────────────────────────────────────────────────────────────────────
    //  Apply stochastic advection to create particle dispersion
    // ──────────────────────────────────────────────────────────────────────────
    let advectedUV = stochasticAdvect(uv, motion, depth * depthMod, scatterRadius, entropyScale, time);
    let advectedSample = textureSampleLevel(feedbackTex, videoSampler, clamp(advectedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    // ──────────────────────────────────────────────────────────────────────────
    //  Entropy injection - motion creates energy bursts
    // ──────────────────────────────────────────────────────────────────────────
    let entropyInjection = motion * 0.3;

    // ──────────────────────────────────────────────────────────────────────────
    //  Quantum foam noise (background boiling)
    // ──────────────────────────────────────────────────────────────────────────
    let foamNoise = hash2(uv * 50.0 + vec2<f32>(time, time * 1.3));
    let foamScale = (1.0 - depth) * foamIntensity; // More foam in background

    // ──────────────────────────────────────────────────────────────────────────
    //  Coherence force - pull particles back towards video frame
    // ──────────────────────────────────────────────────────────────────────────
    let coherence = coherenceStr + depth * 0.1; // Foreground reassembles faster
    let coherentSample = mix(advectedSample, videoSample, coherence);

    // ──────────────────────────────────────────────────────────────────────────
    //  Combine effects
    // ──────────────────────────────────────────────────────────────────────────
    var result = coherentSample;
    result = result + vec3<f32>(entropyInjection); // Add energy as brightness
    result = result + vec3<f32>(foamNoise.x, foamNoise.y, (foamNoise.x + foamNoise.y) * 0.5) * foamScale;

    // ──────────────────────────────────────────────────────────────────────────
    //  Particle density accumulation with HDR
    // ──────────────────────────────────────────────────────────────────────────
    let density = 1.0 + motion * densityBoost;
    result = result * density;

    // ──────────────────────────────────────────────────────────────────────────
    //  Anti-matter voids - create negative density in low-motion areas
    //  voidStrength controls both intensity AND frequency of voids
    // ──────────────────────────────────────────────────────────────────────────
    let voidPotential = max(0.0, 0.1 - motion) * voidStrength;
    if (voidPotential > 0.01) {
        let voidNoise = hash1(uv * 20.0 + vec2<f32>(time * 0.5, 0.0));
        let voidThreshold = 0.95 - voidStrength * 0.3; // More voids when strength is high (0.65-0.95)
        if (voidNoise > voidThreshold) {
            result = result - vec3<f32>(voidPotential * 2.0); // Anti-matter effect
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  Temporal shimmer
    // ──────────────────────────────────────────────────────────────────────────
    let shimmer = sin(time * 10.0 + uv.x * 20.0) * cos(time * 7.0 + uv.y * 15.0) * shimmerAmt;
    result = result * (1.0 + shimmer);

    // ──────────────────────────────────────────────────────────────────────────
    //  Depth-based particle softening
    // ──────────────────────────────────────────────────────────────────────────
    let blurAmount = depth * depthMod * 0.3;
    let luminance = dot(result, vec3<f32>(0.299, 0.587, 0.114));
    result = mix(result, vec3<f32>(luminance), blurAmount);

    // ──────────────────────────────────────────────────────────────────────────
    //  Output (HDR allowed for glowing hotspots and anti-matter voids)
    // ──────────────────────────────────────────────────────────────────────────
    textureStore(outTex, gid.xy, vec4<f32>(result, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(feedbackOut, gid.xy, vec4<f32>(result, 1.0));
}
