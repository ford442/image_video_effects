// ═══════════════════════════════════════════════════════════════════
//  Ripple Bloom
//  Category: hybrid
//  Features: ripple-distortion, hdr-bloom, multi-pass-composite, mouse-driven
//  Complexity: High
//  Created: 2026-05-31
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

const PI: f32 = 3.141592653589793;

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let rippleFreq = u.zoom_params.x * 10.0 + 3.0;
    let rippleAmp = u.zoom_params.y * 0.02 + 0.003;
    let bloomThreshold = u.zoom_params.z;
    let bloomIntensity = u.zoom_params.w * 2.0;

    var mouse = u.zoom_config.yz;

    // Phase 1: Ripple distortion
    var displacement = vec2<f32>(0.0);

    // Mouse-centered ripple
    let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let mouseWave = sin(mouseDist * rippleFreq - time * 4.0) * rippleAmp;
    let mouseFalloff = exp(-mouseDist * 2.0);
    displacement += normalize(uv - mouse + vec2<f32>(0.001)) * mouseWave * mouseFalloff;

    // Ripple clicks
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 3.0) {
            let ripplePos = ripple.xy;
            let dist = length((uv - ripplePos) * vec2<f32>(aspect, 1.0));
            let wave = sin(dist * rippleFreq * 1.5 - elapsed * 10.0) * rippleAmp;
            let attenuation = exp(-elapsed * 2.0);
            let radiusMask = exp(-dist * dist * 8.0);
            displacement += normalize(uv - ripplePos + vec2<f32>(0.001)) * wave * attenuation * radiusMask;
        }
    }

    // Global ambient ripple
    let ambientWave = sin(uv.x * rippleFreq * 0.5 + time * 0.5) * cos(uv.y * rippleFreq * 0.5 + time * 0.7) * rippleAmp * 0.3;
    displacement += vec2<f32>(ambientWave);

    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Phase 2: HDR Bloom on bright areas
    var bloom = vec3<f32>(0.0);
    let bloomSamples = 12;
    for (var i: i32 = 0; i < bloomSamples; i = i + 1) {
        let angle = f32(i) / f32(bloomSamples) * 2.0 * PI;
        for (var j: i32 = 1; j <= 3; j = j + 1) {
            let dist = f32(j) * 0.012;
            let offset = vec2<f32>(cos(angle), sin(angle)) * dist;
            let sampleUV = clamp(displacedUV + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
            let lum = luminance(sampleColor);
            let brightMask = smoothstep(bloomThreshold, bloomThreshold + 0.3, lum);
            let weight = brightMask / f32(j) / f32(bloomSamples);
            bloom += sampleColor * weight;
        }
    }

    // Tonemap bloom
    bloom = bloom / (1.0 + bloom * 0.5);

    // Composite: base + bloom
    let finalColor = baseColor + bloom * bloomIntensity;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
