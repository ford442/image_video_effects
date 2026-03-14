// ═══════════════════════════════════════════════════════════════
//  Neon Pulse Stream - Flow Field with Alpha Emission
//  Category: lighting-effects
//  Physics: Flow-field simulation with emissive dye injection
//  Alpha: Core dye = 0.3, Glow = 0.0 (additive)
// ═══════════════════════════════════════════════════════════════

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

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    var mousePos = u.zoom_config.yz;

    // Parameters
    // x: flowSpeed, y: decay, z: neonIntensity, w: occlusionBalance
    let flowSpeed = u.zoom_params.x * 0.02 + 0.001;
    let decay = 0.9 + (u.zoom_params.y * 0.09);
    let neonIntensity = u.zoom_params.z * 5.0;
    let flowChaos = 0.5;
    let occlusionBalance = u.zoom_params.w;

    // 1. Calculate Flow Field from Input Video
    let texelSize = 1.0 / resolution;

    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let lumaC = dot(c.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let lumaR = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumaT = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Gradient vector
    var grad = vec2<f32>(lumaR - lumaC, lumaT - lumaC);

    // Rotate 90 degrees to flow *along* edges instead of across them
    var flowDir = vec2<f32>(-grad.y, grad.x);

    // Normalize
    if (length(flowDir) > 0.001) {
        flowDir = normalize(flowDir);
    } else {
        flowDir = vec2<f32>(0.0);
    }

    // Add some noise-based flow
    let noiseVal = sin(uv.x * 10.0 + time) * cos(uv.y * 10.0 + time);
    flowDir = mix(flowDir, vec2<f32>(cos(noiseVal * 6.28), sin(noiseVal * 6.28)), flowChaos * 0.5);

    // 2. Advect History
    let samplePos = uv - flowDir * flowSpeed;
    var history = textureSampleLevel(dataTextureC, u_sampler, samplePos, 0.0);

    // Decay the history
    history = history * decay;

    // 3. Mouse Injection
    let dVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);
    let brushRadius = 0.02;

    if (dist < brushRadius) {
        // Generate a neon color that cycles over time
        let neonColor = vec3<f32>(
            0.5 + 0.5 * sin(time * 3.0),
            0.5 + 0.5 * sin(time * 3.0 + 2.0),
            0.5 + 0.5 * sin(time * 3.0 + 4.0)
        );

        // Soft brush edge
        let brush = smoothstep(brushRadius, 0.0, dist);

        // Add to history (accumulate)
        history = history + vec4<f32>(neonColor * brush * neonIntensity, brush);
    }

    // Clamp history to avoid blowing out
    history = min(history, vec4<f32>(5.0));

    // 4. Emission calculation
    let emission = history.rgb * neonIntensity;

    // Calculate alpha based on emission intensity and history alpha
    let glowIntensity = length(emission) * history.a;
    let finalAlpha = calculateEmissiveAlpha(glowIntensity, occlusionBalance);

    // Write output with alpha emission
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));
    textureStore(dataTextureA, global_id.xy, history);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
