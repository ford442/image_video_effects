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
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame (A)
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
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

    // Params
    let brushSize = max(0.01, u.zoom_params.x * 0.2);
    let decay = u.zoom_params.y; // 0 = instant clear, 1 = forever
    let distortion = u.zoom_params.z;
    let freezeMode = step(0.5, u.zoom_params.w); // 0 = freeze (paint), 1 = unfreeze (erase)

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouseDown = u.zoom_config.w > 0.5;

    // Read current video/image
    let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Read previous canvas state
    var canvasState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Mouse Interaction
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    if (mouseDown && dist < brushSize) {
        let brushSoftness = smoothstep(brushSize, brushSize * 0.5, dist);

        if (freezeMode < 0.5) {
            // Freeze Mode: Paint current frame onto canvas
            // We store currentFrame in RGB, and Alpha = 1.0
            canvasState = mix(canvasState, vec4<f32>(currentFrame.rgb, 1.0), brushSoftness);
        } else {
            // Unfreeze Mode: Erase canvas (alpha -> 0)
            canvasState = mix(canvasState, vec4<f32>(canvasState.rgb, 0.0), brushSoftness);
        }
    }

    // Apply Decay (if not painting this pixel)
    // Decay reduces Alpha
    canvasState.a = canvasState.a * mix(0.9, 1.0, decay);

    // Store updated state to A for next frame
    textureStore(dataTextureA, global_id.xy, canvasState);

    // Final Composition
    // If alpha > threshold, show frozen frame. Else show current frame.
    // Use smooth transition
    let mixFactor = smoothstep(0.0, 1.0, canvasState.a);

    // Optional distortion at the edge of time
    var displayUV = uv;
    if (distortion > 0.0) {
        // Distort UVs where mixFactor is intermediate (the edge)
        let edge = 1.0 - abs(mixFactor * 2.0 - 1.0); // 0 at ends, 1 at center
        displayUV += vec2<f32>(sin(uv.y * 50.0), cos(uv.x * 50.0)) * distortion * 0.01 * edge;
    }

    // We need to sample current frame again if UV distorted, or just mix colors?
    // Let's mix colors.
    let displayCurrent = textureSampleLevel(readTexture, u_sampler, displayUV, 0.0);
    let displayFrozen = canvasState; // Canvas state stores the color

    let finalColor = mix(displayCurrent, displayFrozen, mixFactor);

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
