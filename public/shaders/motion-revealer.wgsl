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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let brushSize = u.zoom_params.x;     // 0.01 to 0.5
    let fadeSpeed = u.zoom_params.y;     // 0.0 to 0.2 (per frame)
    let softness = u.zoom_params.z;      // 0.0 to 1.0
    let opacity = u.zoom_params.w;       // 0.0 to 1.0

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w; // 1.0 if mouse is down

    let aspect = resolution.x / resolution.y;
    let aspectCorrection = vec2<f32>(aspect, 1.0);

    // Calculate distance to mouse
    let diff = (uv - mousePos) * aspectCorrection;
    let dist = length(diff);

    // Brush mask (circle with softness)
    // Map brushSize from param 0..1 to actual radius 0.01..0.4
    let radius = 0.01 + brushSize * 0.4;
    // Softness determines the gradient edge
    let edgeWidth = softness * radius;
    let brush = 1.0 - smoothstep(radius - max(edgeWidth, 0.001), radius, dist);

    // Read previous frame from history (dataTextureC)
    let historyColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Read current live video frame
    let liveColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Determine new color for the persistence buffer
    // Start with history faded slightly
    // Map fade param to a decay factor close to 1.0
    // fadeSpeed 0.0 -> decay 1.0 (no fade)
    // fadeSpeed 1.0 -> decay 0.9 (fast fade)
    let decay = 1.0 - (fadeSpeed * 0.1);
    var newHistoryColor = historyColor * decay;

    // If mouse is moving/painting (or just proximity if we want hover effect)
    // Let's make it always active on hover, but maybe stronger on click?
    // The prompt implies "mouse responsive", usually just movement is enough.
    // Let's use `brush` value (0.0 to 1.0) to mix in the live video.

    // Mix live video into history based on brush strength and opacity
    let mixFactor = brush * opacity;
    // We want to add/overwrite the history with the live pixel if brush is there
    newHistoryColor = mix(newHistoryColor, liveColor, mixFactor);

    // Store in history buffer (A) for next frame
    textureStore(dataTextureA, global_id.xy, newHistoryColor);

    // Store in display texture
    // We display the history buffer contents
    textureStore(writeTexture, global_id.xy, newHistoryColor);

    // Clear depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
