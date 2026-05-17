// ═══════════════════════════════════════════════════════════════════
//  Cyber Lattice
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Shader Upgrade Swarm — Phase A
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
  zoom_params: vec4<f32>,  // x=GridScale, y=DistortStrength, z=GlowIntensity, w=Radius
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;

    let bass = plasmaBuffer[0].x;
    var mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let gridScale = 10.0 + u.zoom_params.x * 50.0;
    let distortStrength = u.zoom_params.y * (1.0 + bass * 0.3);
    let glowIntensity = u.zoom_params.z * 2.0;
    let radius = u.zoom_params.w * 0.5;

    let aspect = resolution.x / max(resolution.y, 0.0001);
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    let distortion = smoothstep(radius, 0.0, dist) * distortStrength * sin(u.config.x * 5.0);
    let gridUV = uv + (uv - mousePos) * distortion;

    let gridX = abs(fract(gridUV.x * gridScale) - 0.5);
    let gridY = abs(fract(gridUV.y * gridScale) - 0.5);
    let gridLine = min(gridX, gridY);

    let thickness = 0.05;
    let mouseInfluence = smoothstep(radius, 0.0, dist);
    let currentThickness = thickness + mouseInfluence * 0.1;

    let gridMask = 1.0 - smoothstep(currentThickness, currentThickness + 0.05, gridLine);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var glowColor = select(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), mouseDown > 0.5);

    let totalGlow = glowIntensity * (0.5 + 0.5 * mouseInfluence);
    let finalColor = mix(baseColor.rgb, glowColor, gridMask * totalGlow);

    // Alpha encodes glow contribution: grid lines and mouse proximity boost weight
    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.4 + gridMask * 0.4 + mouseInfluence * 0.15 + luma * 0.05, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(finalColor, alpha));
}
