// ═══════════════════════════════════════════════════════════════════
//  Alpha HDR Bloom Chain
//  Category: visual-effects
//  Features: mouse-driven, rgba-data-channel
//  Complexity: Medium
//  RGBA Channels:
//    R = HDR red channel (can exceed 1.0)
//    G = HDR green channel (can exceed 1.0)
//    B = HDR blue channel (can exceed 1.0)
//    A = Exposure/overexposure value (stops above white point)
//  Why f32: HDR values routinely exceed 1.0 and bloom kernel
//  accumulates many samples; 8-bit would clip immediately.
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

// ACES tone mapping approximation
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    // === READ INPUT ===
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // === COMPUTE HDR EXPOSURE ===
    let maxChannel = max(sourceColor.r, max(sourceColor.g, sourceColor.b));
    let exposure = max(0.0, maxChannel - 1.0);

    // === BLOOM KERNEL ===
    let bloomRadius = mix(0.01, 0.08, u.zoom_params.x);
    let bloomIntensity = u.zoom_params.y * 2.0;
    let bloomSamples = 16;

    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    for (var i = 0; i < bloomSamples; i = i + 1) {
        let angle = f32(i) * 6.283185307 / f32(bloomSamples);
        // Multiple radii for better blur
        let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
        let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let neighborMax = max(neighbor.r, max(neighbor.g, neighbor.b));
        let neighborExposure = max(0.0, neighborMax - 1.0);

        // Gaussian-ish weight
        let weight = exp(-f32(i % 4) * 0.5);
        bloom += neighbor * neighborExposure * weight;
        totalWeight += neighborExposure * weight;
    }

    if (totalWeight > 0.001) {
        bloom /= totalWeight;
    }
    bloom *= bloomIntensity;

    // === COMPOSITE ===
    let hdrColor = sourceColor + bloom;

    // === MOUSE BLOOM BOOST ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseGlow = smoothstep(0.2, 0.0, mouseDist) * mouseDown * 2.0;
    hdrColor += vec3<f32>(mouseGlow * 0.5, mouseGlow * 0.3, mouseGlow * 0.1);

    // === RIPPLE FLASH ===
    let time = u.config.x;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.5 && rDist < 0.1) {
            let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            hdrColor += vec3<f32>(flash * 2.0, flash * 1.5, flash);
        }
    }

    // === TONE MAP ===
    let toneMapExp = mix(0.5, 2.0, u.zoom_params.z);
    let ldrColor = toneMapACES(hdrColor * toneMapExp);

    // === STORE HDR STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, exposure));

    // === WRITE DISPLAY ===
    textureStore(writeTexture, coord, vec4<f32>(ldrColor, exposure + 0.1));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
