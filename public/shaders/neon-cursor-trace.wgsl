// ═══════════════════════════════════════════════════════════════
//  Neon Cursor Trace - Mouse Trail with Alpha Emission
//  Category: lighting-effects
//  Physics: Persistent cursor trail with emissive decay
//  Alpha: Core trail = 0.3, Glow = 0.0 (additive)
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

    // Parameters
    // x: decaySpeed, y: traceWidth, z: neonIntensity, w: occlusionBalance
    let decaySpeed = 0.9 + (u.zoom_params.x * 0.095);
    let traceWidth = 0.01 + (u.zoom_params.y * 0.1);
    let neonIntensity = 1.0 + (u.zoom_params.z * 4.0);
    let occlusionBalance = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    var mousePos = u.zoom_config.yz;

    // Sample previous frame (history)
    var history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Decay history
    history = history * decaySpeed;

    // Add new mouse trail
    let dist = distance(uv * vec2(aspect, 1.0), mousePos * vec2(aspect, 1.0));
    let brush = 1.0 - smoothstep(traceWidth * 0.5, traceWidth, dist);

    // Add to history (accumulate)
    let t = u.config.x;
    let brushColor = vec3<f32>(
        0.5 + 0.5 * sin(t),
        0.5 + 0.5 * sin(t + 2.09),
        0.5 + 0.5 * sin(t + 4.18)
    );

    if (dist < traceWidth) {
        history = history + vec4<f32>(brushColor * brush, brush);
    }

    // Clamp history
    history = clamp(history, vec4<f32>(0.0), vec4<f32>(2.0));

    // Write updated history
    textureStore(dataTextureA, global_id.xy, history);

    // Emission calculation from trail
    let emission = history.rgb * neonIntensity * 2.0;

    // Calculate alpha based on emission intensity
    let glowIntensity = length(emission) * history.a;
    let finalAlpha = calculateEmissiveAlpha(glowIntensity, occlusionBalance);

    // Output with emission alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
