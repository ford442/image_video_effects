// ═══════════════════════════════════════════════════════════════════
//  Interactive Glitch Brush
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, audio-reactive
//  Complexity: Medium
//  Phase A Upgrade Swarm
//  Created: 2026-05-10
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
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

// Param1: Brush Size
// Param2: Intensity
// Param3: Block Scale
// Param4: Color Split

fn random(st: vec2<f32>) -> f32 {
    return fract(sin(dot(st.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    var mousePos = u.zoom_config.yz;

    let brushSize = max(u.zoom_params.x * 0.3 + 0.05, 0.001);
    let intensity = clamp(u.zoom_params.y, 0.0, 1.0);
    let blockScale = max(u.zoom_params.z * 50.0 + 5.0, 0.001);
    let colorSplit = clamp(u.zoom_params.w * 0.1, 0.0, 1.0);

    // Audio reactivity: bass drives glitch intensity
    let bass = plasmaBuffer[0].x;
    let audioIntensity = intensity * (1.0 + bass * 0.5);

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Brush Check
    if (mousePos.x >= 0.0) {
        let diff = mousePos - uv;
        let diffAspect = vec2<f32>(diff.x * aspect, diff.y);
        let dist = length(diffAspect);

        if (dist < brushSize) {
            // Apply glitch inside brush
            // Block noise
            let blockUV = floor(uv * blockScale) / blockScale;
            let noise = random(blockUV + vec2<f32>(time * 0.1));

            // Displacement
            var offset = vec2<f32>(0.0);
            if (noise > 0.5) {
                offset.x = (random(vec2<f32>(noise, time)) - 0.5) * audioIntensity * 0.2;
            }

            // Color Split with clamped UVs
            let sampleUV_r = clamp(uv + offset - vec2<f32>(colorSplit, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleUV_g = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleUV_b = clamp(uv + offset + vec2<f32>(colorSplit, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

            let r = textureSampleLevel(readTexture, u_sampler, sampleUV_r, 0.0).r;
            let g = textureSampleLevel(readTexture, u_sampler, sampleUV_g, 0.0).g;
            let b = textureSampleLevel(readTexture, u_sampler, sampleUV_b, 0.0).b;

            // Invert occasionally
            var glitchR = r;
            var glitchG = g;
            var glitchB = b;
            if (random(vec2<f32>(time, noise)) > 0.95) {
                 glitchR = 1.0 - r;
                 glitchG = 1.0 - g;
                 glitchB = 1.0 - b;
            }

            // Luminance-based alpha
            let alpha = clamp(0.299 * glitchR + 0.587 * glitchG + 0.114 * glitchB, 0.1, 1.0);
            color = vec4<f32>(glitchR, glitchG, glitchB, alpha);

            // Scanlines inside brush
            if (fract(uv.y * resolution.y * 0.5) < 0.5) {
                color = color * 0.8;
            }
        }
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
