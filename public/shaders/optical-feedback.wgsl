// ═══════════════════════════════════════════════════════════════════════════════
//  Optical Feedback - Advanced Alpha with Accumulative
//  Category: feedback/temporal
//  Alpha Mode: Accumulative Alpha + Physical Transmittance
//  Features: advanced-alpha, optical-feedback, camera-feedback
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
  zoom_params: vec4<f32>,  // x=AccumulationRate, y=Zoom, z=Rotation, w=Brightness
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.08) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

// Mode 4: Volumetric Alpha
fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    // Mouse-driven feedback center for tactile zoom/rotate
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let accumulationRate = u.zoom_params.x;
    let zoom = u.zoom_params.y * 0.02 * (1.0 + bass * 0.5);    // bass pumps the zoom
    let rotation = u.zoom_params.z * 0.1 + mouseDown * 0.02 * sin(time * 4.0);
    let brightness = u.zoom_params.w * 2.0;
    
    let current = textureLoad(readTexture, coord, 0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Optical feedback transformation — center on mouse for camera-feedback feel
    let center = mix(vec2<f32>(0.5), mouse, 0.5);
    let centered = uv - center;
    let c = cos(rotation);
    let s = sin(rotation);
    let rotated = vec2<f32>(
        centered.x * c - centered.y * s,
        centered.x * s + centered.y * c
    );
    let scaled = rotated * (1.0 - zoom) + center;
    
    let feedbackSample = textureSampleLevel(dataTextureC, u_sampler, clamp(scaled, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    
    let feedbackColor = feedbackSample.rgb * brightness;
    let newAlpha = volumetricAlpha(length(feedbackColor), 1.0);
    
    let accumulated = accumulativeAlpha(
        feedbackColor,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    let finalResult = mix(accumulated, current, 0.1);
    
    textureStore(dataTextureA, coord, finalResult);
    textureStore(writeTexture, global_id.xy, finalResult);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
