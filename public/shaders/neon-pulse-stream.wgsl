// ═══════════════════════════════════════════════════════════════════════════════
//  Neon Pulse Stream - Advanced Alpha with Luminance Key
//  Category: glow/light-effects
//  Alpha Mode: Luminance Key Alpha + Effect Intensity
//  Features: advanced-alpha, streaming-pulses, neon-effect
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
  zoom_params: vec4<f32>,  // x=StreamSpeed, y=StreamDensity, z=LumaThreshold, w=Softness
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 6: Luminance Key Alpha
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

// Combined alpha
fn calculatePulseStreamAlpha(
    color: vec3<f32>,
    streamIntensity: f32,
    params: vec4<f32>
) -> f32 {
    let lumaAlpha = luminanceKeyAlpha(color, params.y, params.z * 0.2);
    return clamp(lumaAlpha * streamIntensity, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // Bass from canonical plasmaBuffer
    let audioBass = plasmaBuffer[0].x;
    let audioReactivity = 1.0 + audioBass * 0.5;

    let streamSpeed = u.zoom_params.x * 3.0;
    let streamDensity = u.zoom_params.y * 10.0 + 3.0;
    let lumaThreshold = u.zoom_params.z * 0.5;
    let softness = u.zoom_params.w * 0.2;

    // Streaming pulses — Gaussian centered at 0.5 (single pow, branchless)
    let streamY = fract(uv.y * streamDensity - time * streamSpeed * audioReactivity);
    let dC = (streamY - 0.5) * 10.0;       // 1/0.1 inlined
    let pulse = exp(-dC * dC);

    // Neon color cycling — single phase, three offsets (vec3 ops, single ALU)
    let phase = time + uv.y * 3.0;
    let neonColor = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));

    // Composite onto background image (preserves user's photo behind stream)
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let streamColor = neonColor * pulse * streamDensity * 0.5;
    let composite = bg * (1.0 - pulse * 0.7) + streamColor;

    let alpha = clamp(calculatePulseStreamAlpha(streamColor, pulse, u.zoom_params)
                      + dot(bg, vec3<f32>(0.299, 0.587, 0.114)) * 0.2 + 0.1, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(composite, alpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
