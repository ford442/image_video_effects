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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown/Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(shift);
    return vec3<f32>(color * cosAngle + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cosAngle));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    // x: Zoom (0.0 - 1.0) -> mapped to 0.8 - 1.2
    // y: Rotation (0.0 - 1.0) -> mapped to -0.1 to 0.1 radians
    // z: Decay (0.0 - 1.0) -> mapped to 0.5 - 0.99
    // w: Hue Shift (0.0 - 1.0) -> mapped to 0.0 - 6.28

    let zoomParam = mix(0.9, 1.1, u.zoom_params.x);
    let rotParam = (u.zoom_params.y - 0.5) * 0.2;
    let decay = mix(0.8, 0.99, u.zoom_params.z);
    let shift = u.zoom_params.w * 6.28;

    let center = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Current Input
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Feedback UV Calculation
    var feedbackUV = uv - center;
    feedbackUV.x = feedbackUV.x * aspect; // Correct for aspect ratio for rotation/scale

    // Scale
    feedbackUV = feedbackUV * (1.0 / zoomParam);

    // Rotate
    let c = cos(rotParam);
    let s = sin(rotParam);
    feedbackUV = vec2<f32>(
        feedbackUV.x * c - feedbackUV.y * s,
        feedbackUV.x * s + feedbackUV.y * c
    );

    feedbackUV.x = feedbackUV.x / aspect; // Restore aspect
    feedbackUV = feedbackUV + center;

    // Sample Previous Frame (Persistence)
    // Note: dataTextureC contains the previous frame's dataTextureA content.
    var prev = textureSampleLevel(dataTextureC, u_sampler, feedbackUV, 0.0);

    // Apply Hue Shift to feedback
    var prevColor = prev.rgb;
    if (shift > 0.01) {
        prevColor = hueShift(prevColor, shift);
    }

    // Mix Logic
    // Traditional feedback adds or screens.
    // Let's do max() to keep bright trails, or mix() for smoother tails.
    // Mix current video with previous trails.

    // If the feedbackUV is out of bounds, fade it out
    if (feedbackUV.x < 0.0 || feedbackUV.x > 1.0 || feedbackUV.y < 0.0 || feedbackUV.y > 1.0) {
        prevColor = vec3<f32>(0.0);
    }

    let feedback = vec4<f32>(prevColor * decay, prev.a);

    // Combine:
    // We want the current video to be "on top", but transparency?
    // Usually video is opaque.
    // So we assume "Current" is the source.
    // Feedback is the "Echo".
    // result = max(current, feedback) looks like light painting.
    // result = mix(current, feedback, 0.5) looks like ghosting.

    // Let's try max for a "light echo" effect.
    let finalColor = max(current, feedback);

    // Write Output
    textureStore(writeTexture, global_id.xy, finalColor);

    // Save to Persistence Buffer
    textureStore(dataTextureA, global_id.xy, finalColor);

    // Pass Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
