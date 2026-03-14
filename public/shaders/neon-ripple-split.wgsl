// ═══════════════════════════════════════════════════════════════
//  Neon Ripple Split - RGB Split with Alpha Emission
//  Category: lighting-effects
//  Physics: Ripple-based RGB split with emissive glow
//  Alpha: Core ripple = 0.3, Glow = 0.0 (additive)
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
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mousePos = u.zoom_config.yz;

    // Parameters
    // x: speed, y: splitAmount, z: glowIntensity, w: occlusionBalance
    let speed = u.zoom_params.x * 4.0 + 1.0;
    let splitAmount = u.zoom_params.y * 0.05 + 0.002;
    let glowIntensity = u.zoom_params.z * 2.0;
    let freq = 10.0 + 40.0;
    let occlusionBalance = u.zoom_params.w;

    var totalWave = 0.0;
    var totalSlope = 0.0;

    // 1. Mouse interaction (continuous ripple source)
    if (mousePos.x >= 0.0) {
        var aspect = resolution.x / resolution.y;
        var dVec = uv - mousePos;
        var dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        // Circular sine wave from mouse
        let phase = dist * freq - time * speed;
        let attenuation = 1.0 / (1.0 + dist * 10.0);

        var wave = sin(phase) * attenuation;
        totalWave += wave;
        totalSlope += cos(phase) * freq * attenuation;
    }

    // 2. Click Ripples
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rData = u.ripples[i];
        let rPos = rData.xy;
        let rStart = rData.z;
        let t = time - rStart;

        if (t > 0.0 && t < 3.0) {
            var aspect = resolution.x / resolution.y;
            var dVec = uv - rPos;
            var dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

            // Expanding ring
            let currentRadius = t * (speed * 0.2);
            let ringDist = dist - currentRadius;
            let ringWidth = 0.1;

            if (abs(ringDist) < ringWidth) {
                let x = ringDist / ringWidth;
                // Windowed sine
                var wave = sin(x * 3.14159 * 2.0) * (1.0 - abs(x));
                let amp = 1.0 - (t / 3.0);

                totalWave += wave * amp * 2.0;
                totalSlope += cos(x * 3.14159 * 2.0) * amp * 2.0;
            }
        }
    }

    // Clamp wave for safety
    totalWave = clamp(totalWave, -2.0, 2.0);

    // RGB Split logic
    // Displace R, G, and B by different amounts based on wave slope/height
    let offsetR = vec2<f32>(totalWave * splitAmount, 0.0);
    let offsetG = vec2<f32>(0.0, totalWave * splitAmount);
    let offsetB = vec2<f32>(-totalWave * splitAmount, -totalWave * splitAmount);

    let r = textureSampleLevel(readTexture, u_sampler, uv + offsetR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + offsetG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + offsetB, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Add Neon Glow - Boost where wave is high
    let glow = abs(totalWave) * glowIntensity;

    // Cyclical color shift for the glow
    let glowColor = vec3<f32>(
        sin(time * 2.0 + totalWave) * 0.5 + 0.5,
        sin(time * 2.0 + totalWave + 2.0) * 0.5 + 0.5,
        sin(time * 2.0 + totalWave + 4.0) * 0.5 + 0.5
    );

    // Emission calculation
    let emission = glowColor * glow * 2.0;

    // Calculate alpha based on emission intensity
    let glowStrength = length(emission);
    let finalAlpha = calculateEmissiveAlpha(glowStrength, occlusionBalance);

    // Store with emission alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
