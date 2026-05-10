// ═══════════════════════════════════════════════════════════════════
//  Signal Tuner
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive
//  Complexity: Low
//  Created: 2026-05-10
//  By: Pixelocity Shader Upgrade Swarm — Phase A
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    // Params
    // x: Frequency
    // y: Amplitude
    // z: Speed (Drift)
    // w: Noise

    let freq = mix(5.0, 100.0, u.zoom_params.x);
    let amp = u.zoom_params.y * 0.1; // Max 0.1 displacement
    let speed = u.zoom_params.z * 5.0;
    let noiseAmt = u.zoom_params.w;

    let time = u.config.x;

    // Audio reactivity — bass boosts wave amplitude
    let bass = plasmaBuffer[0].x;
    let audioAmp = amp * (1.0 + bass * 0.8);

    // Mouse Influence
    let aspect = u.config.z / u.config.w;
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouse = u.zoom_config.yz;
    let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);

    // Radial falloff from mouse
    let dist = distance(uv_corrected, mouse_corrected);
    let mouseInfluence = smoothstep(0.5, 0.0, dist);

    // Wave — vertical wave displacing X
    let wave = sin(uv.y * freq + time * speed) * audioAmp;

    // Modulate wave by mouse influence
    let displacement = vec2<f32>(wave * mouseInfluence, 0.0);

    // Add noise if requested (branchless-safe via select)
    let noiseHash = hash(uv * time);
    let noiseVal = select(0.0, (noiseHash - 0.5) * noiseAmt * mouseInfluence, noiseAmt > 0.01);

    let finalUV = uv + displacement + vec2<f32>(noiseVal, noiseVal);

    // RGB Split (Chromatic Aberration) based on Amplitude
    let split = audioAmp * mouseInfluence * 0.5;

    let r = textureSampleLevel(readTexture, u_sampler, finalUV + vec2<f32>(split, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, finalUV - vec2<f32>(split, 0.0), 0.0).b;

    // Sample depth for alpha blending
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: blend luminance with effect intensity
    let luminance = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
    let effectStrength = clamp(mouseInfluence * audioAmp * 10.0, 0.0, 1.0);
    let depthFactor = mix(1.0, 0.85, depth * 0.5);
    var alpha = mix(1.0, clamp(luminance * 1.2 + 0.2, 0.4, 1.0) * depthFactor, effectStrength);
    alpha = clamp(alpha, 0.3, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(r, g, b, alpha));

    // Pass through depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
