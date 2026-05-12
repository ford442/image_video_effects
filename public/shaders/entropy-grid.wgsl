// ═══════════════════════════════════════════════════════════════════
//  Entropy Grid
//  Category: image
//  Features: mouse-driven, audio-reactive, audio-driven
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Phase A Upgrade Agent
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

// Hash function for randomness
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    var uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    // Correct UV aspect ratio for distance calculations
    let aspect = u.config.z / max(u.config.w, 1.0);
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    var mouse = u.zoom_config.yz;
    let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = distance(uv_corrected, mouse_corrected);

    // Parameters
    let gridSize = mix(10.0, 100.0, u.zoom_params.x);
    let chaos = u.zoom_params.y;
    let radius = max(u.zoom_params.z, 0.001);
    let invert = u.zoom_params.w > 0.5;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let reactiveChaos = clamp(chaos * (1.0 + bass * 0.5), 0.0, 1.0);

    // Calculate Grid ID
    let gridUV = floor(uv * gridSize);

    // Random offset for this grid cell
    let randX = hash(gridUV);
    let randY = hash(gridUV + vec2<f32>(1.0, 1.0));
    let randomOffset = (vec2<f32>(randX, randY) - 0.5) * reactiveChaos * 0.5;

    // Calculate influence
    var influence = smoothstep(radius, radius * 0.5, dist);

    if (invert) {
        influence = 1.0 - influence;
    }

    let finalOffset = randomOffset * influence;

    let sampleUV = uv + finalOffset;

    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Meaningful alpha based on effect intensity and luminance
    let effectIntensity = influence * reactiveChaos;
    let luminance = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(color.a, clamp(luminance * 0.3 + 0.7, 0.5, 1.0), effectIntensity);
    let finalColor = vec4<f32>(color.rgb, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
