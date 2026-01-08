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

    // Mouse interaction
    let mouse = u.zoom_config.yz;
    // Params: Decay, Radius, EchoStrength, ColorShift
    let decayBase = u.zoom_params.x; // 0.0 - 1.0 (default e.g. 0.8)
    let mouseRadius = u.zoom_params.y; // 0.0 - 1.0
    let echoStr = u.zoom_params.z; // 0.0 - 1.0
    let colorShift = u.zoom_params.w; // 0.0 - 1.0

    // Read current video frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Read history (previous frame's accumulated trails)
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Calculate mouse influence
    let aspect = resolution.x / resolution.y;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    // Influence is 1.0 near mouse, 0.0 far away
    // Using smoothstep for soft edge
    let influence = 1.0 - smoothstep(0.0, max(0.01, mouseRadius), dist);

    // Determine effective decay
    // If echoStr is high, we want MORE history (slower decay).
    // Let's map decayBase to background decay.
    // Mouse proximity increases trail persistence (makes decay closer to 1.0)

    // Base mix: 0.1 means mostly new frame, 0.9 means mostly old frame.
    // We want trails to persist.

    let baseMix = decayBase; // e.g. 0.5
    let activeMix = 0.95 + (0.04 * echoStr); // very persistent near mouse

    // effectiveMix blends between base and active based on mouse influence
    let effectiveMix = mix(baseMix, activeMix, influence * echoStr);

    // Apply color shift to history before blending
    // Rotate RGB channels slightly based on colorShift
    var histColor = prev;
    if (colorShift > 0.01) {
        let shiftAmt = colorShift * 0.2; // Scaling
        let r = prev.r;
        let g = prev.g;
        let b = prev.b;
        // Simple hue rotation approx
        histColor = vec4<f32>(
            mix(r, g, shiftAmt),
            mix(g, b, shiftAmt),
            mix(b, r, shiftAmt),
            prev.a
        );
    }

    // Combine current and history
    // We want the current frame to always be visible "on top" but trails behind.
    // Standard feedback: new = mix(current, history, decay)
    // If decay is high (0.9), history dominates -> blur.
    // If decay is low (0.1), current dominates -> no trails.

    let result = mix(current, histColor, effectiveMix);

    // Always keep alpha 1.0
    let finalColor = vec4<f32>(result.rgb, 1.0);

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
