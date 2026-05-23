// ═══════════════════════════════════════════════════════════════════
//  Neon Pulse Stream
//  Category: image
//  Features: advanced-alpha, streaming-pulses, neon-effect, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-23
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let audioReactivity = 1.0 + bass * 0.5;

    let streamSpeed = u.zoom_params.x * 3.0 * (1.0 + mids * 0.3);
    let streamDensity = u.zoom_params.y * 10.0 + 3.0 + treble * 2.0;
    let lumaThreshold = u.zoom_params.z * 0.5;
    let softness = u.zoom_params.w * 0.2;

    let streamY = fract(uv.y * streamDensity - time * streamSpeed * audioReactivity);
    let dC = (streamY - 0.5) * 10.0;
    let pulse = exp(-dC * dC);

    let phase = time + uv.y * 3.0 + bass * 1.0;
    let neonColor = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));

    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let streamColor = neonColor * pulse * streamDensity * 0.5;
    let composite = bg * (1.0 - pulse * 0.7) + streamColor;

    let lumaAlpha = luminanceKeyAlpha(streamColor, lumaThreshold, softness);
    let alpha = clamp(lumaAlpha * pulse + dot(bg, vec3<f32>(0.299, 0.587, 0.114)) * 0.2 + 0.1, 0.0, 1.0);

    let finalColor = vec4<f32>(composite, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
