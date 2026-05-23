// ═══════════════════════════════════════════════════════════════════
//  Stipple Render
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Created: 2026-05-10
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

// Pseudo-random hash
fn hash21(p: vec2<f32>) -> f32 {
    return max(fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453), 0.001);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let texel = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001));
    let aspect = resolution.x / max(resolution.y, 0.001);

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let dotScale    = mix(1.0, 4.0, clamp(u.zoom_params.x * (1.0 + mids * 0.2), 0.0, 1.0));
    let contrast    = mix(0.5, 2.0, clamp(u.zoom_params.y * (1.0 + bass * 0.5), 0.0, 1.0));
    let mouseRadius = mix(0.1, 0.5, clamp(u.zoom_params.z * (1.0 + treble * 0.15), 0.0, 1.0));
    let detailMix   = u.zoom_params.w;

    // Mouse
    let mouse = u.zoom_config.yz;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let mouseFactor = smoothstep(mouseRadius, 0.0, dist);

    // Source Color
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Dynamic Density: Higher density near mouse
    let localScale = mix(max(resolution.y * 0.5, 0.001), max(resolution.y * 2.0, 0.001), mouseFactor * 0.8 + 0.2) * dotScale;
    let noise = hash21(floor(uv * localScale));

    // Adjust luma contrast
    let adjustedLuma = (luma - 0.5) * contrast + 0.5;
    let inkDensity = 1.0 - clamp(adjustedLuma, 0.0, 1.0);

    // Stipple Logic (branchless)
    let inkColor = vec3<f32>(0.05, 0.05, 0.1);
    let paperColor = vec3<f32>(1.0);
    let outColor = select(paperColor, inkColor, noise < inkDensity);

    // Mix with original color based on mouse
    let stippleAlpha = mix(0.15, 0.95, inkDensity);
    let stippleColor = vec4<f32>(outColor, stippleAlpha);
    let finalColor = mix(stippleColor, color, mouseFactor * detailMix);

    // Depth read and mandatory writes
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, texel, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
