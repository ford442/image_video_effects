// ═══════════════════════════════════════════════════════════════════════════════
//  Holographic Projection Failure - Advanced Alpha with Depth-Layered
//  Category: complex-multi-effect
//  Alpha Mode: Depth-Layered Alpha + Effect Intensity
//  Features: advanced-alpha, holographic, failure-effect, glitch
// ═══════════════════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=FailureAmount, y=HolographicIntensity, z=DepthWeight, w=FlickerSpeed
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.3, 1.0, depth);
    let lumaAlpha = mix(0.4, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

// Random
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let failureAmount = clamp(u.zoom_params.x * (1.0 + bass * 0.4), 0.0, 1.0);
    let holographicIntensity = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let flickerSpeed = u.zoom_params.w * 20.0;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let sample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Flicker effect
    let flicker = step(rand(vec2<f32>(time * flickerSpeed, 0.0)), 0.9 - failureAmount * 0.5);

    // Holographic gradient + plasma palette overlay (depth-modulated phase shift)
    let phase = time * 0.5 + uv.x * 5.0 + uv.y * 3.0 + depth * TAU;
    let holographic = vec3<f32>(
        0.3 + 0.4 * sin(phase),
        0.5 + 0.3 * sin(phase + 2.094),
        0.7 + 0.3 * sin(phase + 4.188)
    );
    let palIdx = u32(clamp((phase / TAU + 0.5) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;
    let irid = mix(holographic, holographic * (0.7 + palette * 0.6), 0.4);

    // Failure artifacts — RGB-shifted block glitch
    let block = floor(uv * vec2<f32>(20.0, 5.0));
    let blockNoise = rand(block + time);
    let artifactMask = step(1.0 - failureAmount, blockNoise);
    let shiftAmt = artifactMask * failureAmount * 0.04;
    let rGlitch = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(shiftAmt, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bGlitch = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(shiftAmt, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let glitched = vec3<f32>(rGlitch, sample.g, bGlitch);

    let finalColor = mix(glitched * flicker, irid, holographicIntensity * flicker) + artifactMask * 0.5;

    let alpha = clamp(depthLayeredAlpha(finalColor, uv, depthWeight) * flicker + artifactMask * 0.2 + bass * 0.05, 0.0, 1.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
