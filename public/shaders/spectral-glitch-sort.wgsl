// ═══════════════════════════════════════════════════════════════════
//  Spectral Glitch Sort
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // y=MouseX, z=MouseY
  zoom_params: vec4<f32>,  // x=Strength, y=Threshold, z=Angle, w=Noise
  ripples: array<vec4<f32>, 50>,
};

fn getLuma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = u.config.zw;
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / dims;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters — bass amplifies sort strength
    let strength    = mix(0.0, 0.5, u.zoom_params.x) * (1.0 + bass * 0.4);
    let threshold   = u.zoom_params.y;
    let angleParam  = u.zoom_params.z * 6.28;
    let noiseAmt    = u.zoom_params.w;

    let mouse     = u.zoom_config.yz;
    let mouseDist = distance(uv, mouse);

    let dir = vec2<f32>(cos(angleParam), sin(angleParam));

    let cSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let c = cSample.rgb;
    let luma = getLuma(c);

    let dispFactor = smoothstep(threshold, threshold + 0.2, luma);

    // Glitch noise block
    let blockUV  = floor(uv * 20.0) / 20.0;
    let noiseVal = hash12(blockUV + u.config.x * 0.1);

    // Mouse proximity increases strength
    let influence = 1.0 - smoothstep(0.0, 0.5, mouseDist);
    var finalStrength = strength * (1.0 + influence * 2.0);

    // Branchless noise modulation
    finalStrength *= mix(1.0, noiseVal * 2.0, noiseAmt);

    let offset  = -dir * finalStrength * dispFactor;
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));

    var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // Chromatic aberration — branchless, scaled by offset magnitude
    let aberScale = smoothstep(0.005, 0.03, length(offset));
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.002, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(0.002, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    finalColor.r = mix(finalColor.r, rSample, aberScale);
    finalColor.b = mix(finalColor.b, bSample, aberScale);

    // Treble adds subtle high-freq shimmer
    finalColor += vec3<f32>(0.05) * treble * noiseVal;
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: sort displacement + luma + audio
    let alpha = clamp(dispFactor * 0.5 + aberScale * 0.3 + bass * 0.1 + cSample.a * 0.15, 0.0, 1.0);
    let fc = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
