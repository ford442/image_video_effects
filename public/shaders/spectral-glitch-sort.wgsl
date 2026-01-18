// ────────────────────────────────────────────────────────────────────────────────
//  Spectral Glitch Sort – Interactive Luma Displacement
//  - Simulates a pixel-sorting effect by displacing pixels based on their luminance.
//  - Bright/Dark pixels are "dragged" in the direction of the mouse.
//  - Uses noise to create glitchy artifacts.
// ────────────────────────────────────────────────────────────────────────────────

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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = u.config.zw;
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / dims;

    // Parameters
    let strength = mix(0.0, 0.5, u.zoom_params.x);
    let threshold = u.zoom_params.y;
    let angleParam = u.zoom_params.z * 6.28;
    let noiseAmt = u.zoom_params.w;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouseDist = distance(uv, mouse);

    // Calculate direction vector from angle or mouse position relative to center
    // Let's make angle relative to mouse position?
    // If angle param is used, it overrides. But let's mix.
    let dir = vec2<f32>(cos(angleParam), sin(angleParam));

    // 1. Sample original color to get luma
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = getLuma(c);

    // 2. Determine displacement
    // Only displace if luma is above/below threshold
    var dispFactor = smoothstep(threshold, threshold + 0.2, luma);

    // Reverse direction if below threshold? No, just mask.

    // Noise to make it "glitchy" (blocky)
    let blockUV = floor(uv * 20.0) / 20.0;
    let noiseVal = hash12(blockUV + u.config.x * 0.1);

    // Mouse proximity increases strength
    let influence = 1.0 - smoothstep(0.0, 0.5, mouseDist);
    let finalStrength = strength * (1.0 + influence * 2.0);

    if (noiseAmt > 0.0) {
        finalStrength *= mix(1.0, noiseVal * 2.0, noiseAmt);
    }

    // 3. Offset UV
    // We offset the READ coordinate.
    // If we want "bright pixels to move right", we read from the LEFT.
    let offset = -dir * finalStrength * dispFactor;

    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));

    // 4. Sample again
    var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // Chromatic Aberration on edges of the sort
    if (length(offset) > 0.01) {
        let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(0.002, 0.0), 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(0.002, 0.0), 0.0).b;
        finalColor.r = r;
        finalColor.b = b;
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
