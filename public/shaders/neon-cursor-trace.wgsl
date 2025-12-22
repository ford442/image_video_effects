// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let decaySpeed = 0.9 + (u.zoom_params.x * 0.095); // 0.9 to 0.995
    let traceWidth = 0.01 + (u.zoom_params.y * 0.1);
    let neonIntensity = 1.0 + (u.zoom_params.z * 4.0);
    let saturationBoost = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz; // Mouse X, Y

    // Sample previous frame (history)
    var history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Decay history
    history = history * decaySpeed;

    // Add new mouse trail
    let dist = distance(uv * vec2(aspect, 1.0), mousePos * vec2(aspect, 1.0));
    let brush = 1.0 - smoothstep(traceWidth * 0.5, traceWidth, dist);

    // Add to history (accumulate)
    // Use a neon color based on time for the brush
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

    // Sample input image
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Convert to grayscale for contrast
    let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    var finalColor = vec3<f32>(gray * 0.5); // Dim background

    // Add neon trail
    finalColor = finalColor + (history.rgb * neonIntensity * history.a);

    // Apply saturation boost to final result if needed
    if (saturationBoost > 0.0) {
        let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
        finalColor = mix(vec3<f32>(luma), finalColor, 1.0 + saturationBoost);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
