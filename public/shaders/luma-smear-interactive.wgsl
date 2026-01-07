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
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Luma Smear Interactive
// Smears pixels based on their luminance and mouse interaction.
// High luminance pixels "stick" or smear in direction of movement (simulated).
// Mouse acts as a "Smear Eraser" or "Smear Booster".

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;

    // Params
    let smearDecay = 0.8 + u.zoom_params.x * 0.19; // 0.8 to 0.99
    let lumaThreshold = u.zoom_params.y;
    let colorShift = u.zoom_params.z;
    let mouseRadius = 0.05 + u.zoom_params.w * 0.2;

    // Read current video frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Read previous smeared frame from history (dataTextureC)
    // Note: dataTextureC contains the *output* of the previous frame.
    // Ideally we want the previous *smeared* result to accumulate.
    let prevSmear = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Calculate Smear
    var outputColor = current;

    // Logic: If current pixel is bright enough, it adds to the smear.
    // If it's dark, it might just show the background or existing smear.

    // We want a "trail" effect.
    // The previous frame's color persists if it was bright.

    var persistence = smearDecay;

    // If luma is high, we refresh the smear with current color
    // If luma is low, we let the old smear show through (decayed)

    if (luma > lumaThreshold) {
        // Bright pixel: update "trail" to current color
        // But also blend slightly with old to smooth
        outputColor = mix(prevSmear, current, 0.5);
    } else {
        // Dark pixel: show the decaying trail from previous frame
        outputColor = prevSmear * persistence;
    }

    // Apply color shift to the trail (make it rainbow-y over time)
    // Rotate Hue? Simple approximation: swap channels or shift
    if (colorShift > 0.0) {
        // Slight RGB rotation on the feedback loop
        let shifted = vec3<f32>(outputColor.g, outputColor.b, outputColor.r);
        outputColor = vec4<f32>(mix(outputColor.rgb, shifted, colorShift * 0.1), outputColor.a);
    }

    // Mouse Interaction
    if (mousePos.x >= 0.0) {
        let dVec = uv - mousePos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        if (dist < mouseRadius) {
            let influence = smoothstep(mouseRadius, mouseRadius * 0.5, dist);
            // Mouse clears the smear (wipes it clean to the current video)
            outputColor = mix(outputColor, current, influence);
        }
    }

    // Ensure alpha is 1.0 for display
    outputColor.a = 1.0;

    // Write to history (dataTextureA) for next frame
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outputColor);

    // Write to display
    textureStore(writeTexture, vec2<i32>(global_id.xy), outputColor);
}
