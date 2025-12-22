@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,              // x=time, y=unused, z=resX, w=resY
  zoom_config: vec4<f32>,         // x=time, y=mouseX, z=mouseY, w=mouseDown/active
  zoom_params: vec4<f32>,         // Parameters 1-4
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    // x: Feedback Decay (0.0 - 0.99)
    // y: Zoom (0.9 - 1.1)
    // z: Rotation (-0.1 - 0.1)
    // w: Color Shift (0.0 - 1.0)

    let feedbackAmt = mix(0.5, 0.99, u.zoom_params.x);
    let zoomScale = mix(0.95, 1.05, u.zoom_params.y);
    let rotationAngle = (u.zoom_params.z - 0.5) * 0.4; // -0.2 to 0.2 radians
    let colorShift = u.zoom_params.w;

    // Mouse center logic
    // If mouse-driven is active, we use mouse pos as the center of zoom/rotation.
    // u.zoom_config.yz are normalized mouse coords (0-1).
    // If mouse is not engaged (or w is 0), default to center.
    // Note: Some shaders use w for click, others for active. We'll assume active/present.

    var center = vec2<f32>(0.5, 0.5);
    // Use mouse position if it's within valid range (simple check)
    // u.zoom_config.y/z are 0-1.
    // We can assume if u.zoom_config.w > 0.0 it is active, or just always use it if feature is enabled.
    // Let's use it if available.

    if (u.zoom_config.w > 0.0) {
        center = u.zoom_config.yz;
    }

    // Calculate sampling UV for feedback (Transform UV relative to center)
    var feedbackUV = uv - center;

    // Rotation Matrix
    let s = sin(rotationAngle);
    let c = cos(rotationAngle);

    // Apply Rotation
    feedbackUV = vec2<f32>(
        feedbackUV.x * c - feedbackUV.y * s,
        feedbackUV.x * s + feedbackUV.y * c
    );

    // Apply Scale (Inverse zoom to zoom in/out)
    // A scale < 1.0 zooms IN (texture gets larger)
    feedbackUV = feedbackUV * (1.0 / zoomScale);

    // Translate back
    feedbackUV = feedbackUV + center;

    // Sample Previous Frame (History)
    // We use dataTextureC (read-only history)
    var prevColor = textureSampleLevel(dataTextureC, u_sampler, feedbackUV, 0.0);

    // Color Shift Effect
    if (colorShift > 0.01) {
         let shift = colorShift * 0.1;
         // Subtle rotation of channels
         let r = prevColor.r;
         let g = prevColor.g;
         let b = prevColor.b;

         prevColor = vec4<f32>(
             mix(r, g, shift),
             mix(g, b, shift),
             mix(b, r, shift),
             prevColor.a
         );
    }

    // Sample Current Video Frame
    // Just simple sampling
    let currColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mix current frame with feedback
    // If feedbackUV is out of 0-1 bounds, textureSampleLevel usually clamps or repeats depending on sampler.
    // If we want a clean edge, we can check bounds.

    var finalColor = mix(currColor, prevColor, feedbackAmt);

    // Fade out edges if desired, or let them repeat/clamp.
    // Let's just clamp via logic if needed, but sampler default is usually Repeat or ClampToEdge.
    // Assuming standard behavior is fine.

    // Ensure alpha is 1.0
    finalColor.a = 1.0;

    // Output to screen
    textureStore(writeTexture, global_id.xy, finalColor);

    // Store to history buffer (dataTextureA) for next frame
    textureStore(dataTextureA, global_id.xy, finalColor);
}
