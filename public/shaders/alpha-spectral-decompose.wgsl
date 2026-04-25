// ═══════════════════════════════════════════════════════════════════
//  Alpha Spectral Decompose
//  Category: visual-effects
//  Features: mouse-driven, rgba-data-channel
//  Complexity: Medium
//  RGBA Channels:
//    R = Low frequency band (large-scale structure)
//    G = Mid-low frequency band
//    B = Mid-high frequency band
//    A = High frequency band (fine detail, edges)
//  Why f32: Filtered band values can be negative (Gabor kernels have
//  negative lobes) and need sub-percent precision for recomposition.
// ═══════════════════════════════════════════════════════════════════

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

// Gabor-like oriented filter
fn gaborFilter(uv: vec2<f32>, angle: f32, frequency: f32, sigma: f32) -> f32 {
    let rotUV = vec2<f32>(
        uv.x * cos(angle) + uv.y * sin(angle),
        -uv.x * sin(angle) + uv.y * cos(angle)
    );
    let gauss = exp(-dot(rotUV, rotUV) / (2.0 * sigma * sigma));
    let wave = cos(rotUV.x * frequency * 6.283185307);
    return gauss * wave;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let ps = 1.0 / res;

    // === DECOMPOSE INTO 4 FREQUENCY BANDS ===
    // Sample neighborhood for multi-scale analysis
    var bandLow = vec3<f32>(0.0);
    var bandMidLow = vec3<f32>(0.0);
    var bandMidHigh = vec3<f32>(0.0);
    var bandHigh = vec3<f32>(0.0);

    let sampleCount = 8;
    for (var i = 0; i < sampleCount; i = i + 1) {
        let angle = f32(i) * 6.283185307 / f32(sampleCount);
        for (var r = 1; r <= 3; r = r + 1) {
            let radius = f32(r) * 2.0 * ps.x;
            let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
            let luma = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));

            // Weight by distance (approximating Gaussian at different scales)
            let dist = f32(r);
            let wLow = exp(-dist * dist / 8.0);       // Large scale
            let wMidLow = exp(-dist * dist / 3.0);    // Medium scale
            let wMidHigh = exp(-dist * dist / 1.0);   // Small scale
            let wHigh = exp(-dist * dist / 0.3);      // Fine scale

            bandLow += sampleColor * wLow;
            bandMidLow += sampleColor * wMidLow;
            bandMidHigh += sampleColor * wMidHigh;
            bandHigh += sampleColor * wHigh;
        }
    }

    // Normalize
    bandLow /= f32(sampleCount * 3);
    bandMidLow /= f32(sampleCount * 3);
    bandMidHigh /= f32(sampleCount * 3);
    bandHigh /= f32(sampleCount * 3);

    // Difference-of-Gaussians style: extract bands
    let sourceLuma = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lowLuma = dot(bandLow, vec3<f32>(0.299, 0.587, 0.114));
    let midLowLuma = dot(bandMidLow, vec3<f32>(0.299, 0.587, 0.114));
    let midHighLuma = dot(bandMidHigh, vec3<f32>(0.299, 0.587, 0.114));
    let highLuma = dot(bandHigh, vec3<f32>(0.299, 0.587, 0.114));

    let bandR = lowLuma;
    let bandG = midLowLuma - lowLuma * 0.5;
    let bandB = midHighLuma - midLowLuma * 0.5;
    let bandA = highLuma - midHighLuma * 0.5;

    // Store decomposition
    textureStore(dataTextureA, coord, vec4<f32>(bandR, bandG, bandB, bandA));

    // === RECOMPOSITION WITH PARAM GAINS ===
    let gainLow = u.zoom_params.x * 3.0;
    let gainMidLow = u.zoom_params.y * 3.0;
    let gainMidHigh = u.zoom_params.z * 3.0;
    let gainHigh = u.zoom_params.w * 3.0;

    var recomposed = vec3<f32>(0.0);
    // Each band contributes a tinted version
    recomposed += vec3<f32>(1.0, 0.8, 0.6) * bandR * gainLow;
    recomposed += vec3<f32>(0.6, 1.0, 0.7) * bandG * gainMidLow;
    recomposed += vec3<f32>(0.5, 0.7, 1.0) * bandB * gainMidHigh;
    recomposed += vec3<f32>(1.0, 1.0, 1.0) * bandA * gainHigh;

    // Add back some original color to preserve recognizability
    let originalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    recomposed = mix(recomposed, originalColor, 0.2);
    recomposed = clamp(recomposed, vec3<f32>(0.0), vec3<f32>(1.0));

    // === MOUSE INTERACTION ===
    // Mouse radial frequency boost
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.3, 0.0, mouseDist) * u.zoom_config.w;
    recomposed += vec3<f32>(bandA * mouseInfluence * 2.0);
    recomposed = clamp(recomposed, vec3<f32>(0.0), vec3<f32>(1.0));

    // === RIPPLE PULSE ===
    let time = u.config.x;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.8 && rDist < 0.15) {
            let pulse = smoothstep(0.15, 0.0, rDist) * max(0.0, 1.0 - age);
            recomposed += vec3<f32>(bandHigh * pulse * 3.0);
        }
    }
    recomposed = clamp(recomposed, vec3<f32>(0.0), vec3<f32>(1.0));

    // Total spectral energy for alpha
    let spectralEnergy = abs(bandR) + abs(bandG) + abs(bandB) + abs(bandA);

    textureStore(writeTexture, coord, vec4<f32>(recomposed, spectralEnergy * 0.5));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
