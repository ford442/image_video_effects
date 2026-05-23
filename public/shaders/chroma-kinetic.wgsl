// ═══════════════════════════════════════════════════════════════════
//  Chroma Kinetic
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Chunks From: chroma-kinetic (original)
//  Created: 2026-05-10
//  By: Phase A Upgrade Swarm
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
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=LumaInfluence, w=Rotation
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 0.001);

    // Params
    let bass = plasmaBuffer[0].x;
    let strength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.3);
    let radius = u.zoom_params.y;
    let luma_inf = u.zoom_params.z;
    let rotation = u.zoom_params.w * 6.28318; // 0-1 -> 0-2PI

    // Mouse Interaction
    var mousePos = u.zoom_config.yz;

    // Vector from Mouse to Pixel
    let diff = uv - mousePos;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);

    // Normalize direction
    var dir = vec2<f32>(0.0);
    if (dist > 0.001) {
        dir = normalize(diffAspect);
    }

    // Rotate the direction
    let c = cos(rotation);
    let s = sin(rotation);
    let rotDir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);

    // Convert back to UV space offset
    // X offset in UV should be scaled by 1/Aspect to represent same physical distance as Y
    let uvOffsetDir = vec2<f32>(rotDir.x / max(aspect, 0.001), rotDir.y);

    // Get Base Color & Luma
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Calculate Offset Amount
    // Falloff based on radius
    let falloff = smoothstep(max(radius, 0.001), 0.0, dist); // 1.0 at mouse, 0.0 at radius

    // Modulate by Luma
    // luma_inf controls how much brightness affects the shift
    let modFactor = max(0.0, 1.0 + (luma - 0.5) * luma_inf * 2.0);

    let finalOffset = uvOffsetDir * strength * falloff * modFactor;

    // Sample RGB Split
    let uvR = uv - finalOffset;
    let uvB = uv + finalOffset;

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = baseColor.g; // Center sample
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Alpha: kinetic dispersion weight — scatter intensity drives compositing blend
    let dispersion = length(finalOffset) / max(strength, 0.001);
    let alpha = clamp(falloff * modFactor * 0.6 + dispersion * 0.3 + 0.1, 0.0, 1.0);

    // Write Output
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Pass through history to keep loop alive
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(0.0));
}
