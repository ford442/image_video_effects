// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Params
    let trailDecay = u.zoom_params.x; // 0.0 to 1.0 (Higher = longer trail)
    let brushSize = u.zoom_params.y;  // Radius
    let shiftSpeed = u.zoom_params.z; // Hue shift speed
    let intensity = u.zoom_params.w;  // Mix intensity

    // Check mouse distance
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    let inBrush = smoothstep(brushSize, brushSize * 0.8, dist); // 1.0 inside, 0.0 outside

    // Get current video frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Get history (previous output)
    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Create the "paint" color
    // We can invert the current color, or shift its hue
    let hue = fract(time * shiftSpeed);
    let shiftColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
    );

    // If under mouse, add to the trail
    // We mix the current video with the shift color
    let paint = mix(current.rgb, shiftColor, 0.5); // Blend with shift color

    // If inside brush, current pixel value becomes 'paint'. Else it's 'history'.
    // But we also want the underlying video to show through.

    // Logic:
    // 1. New History = Old History * Decay.
    // 2. If mouse is here, add Paint to History.

    let historyDecayed = history.rgb * (0.9 + 0.09 * trailDecay); // Never fully 1.0 or it saturates

    var newHistory = historyDecayed;
    if (inBrush > 0.01) {
        newHistory = mix(newHistory, shiftColor * 2.0, inBrush * intensity); // Add brightness
    }

    // Clamp
    newHistory = clamp(newHistory, vec3<f32>(0.0), vec3<f32>(2.0)); // Allow some bloom

    // Final composite: Video + History
    // Use history as an additive overlay or difference?
    // Let's do additive (screen-like)
    let finalColor = current.rgb + newHistory * 0.5;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newHistory, 1.0)); // Store ONLY the trail in history
}
