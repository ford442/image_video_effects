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

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ZoomStrength, y=Radius, z=FeedbackDecay, w=Rotation
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
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Params
    // Let's map slider 0..1 to 0.9..1.1 scale
    let scale = 1.0 - (u.zoom_params.x - 0.5) * 0.2;

    let radius = u.zoom_params.y * 0.5 + 0.01;
    let decay = u.zoom_params.z; // 0..1
    let rotation = (u.zoom_params.w - 0.5) * 0.5; // Rotation in radians

    let mouse = u.zoom_config.yz;

    // Distance from mouse
    let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

    // Calculate Feedback UV
    // Rotate and Scale around Mouse
    let offset = (uv - mouse);
    let cosR = cos(rotation);
    let sinR = sin(rotation);
    let rotated = vec2<f32>(
        offset.x * cosR - offset.y * sinR,
        offset.x * sinR + offset.y * cosR
    );
    let zoomUV = mouse + rotated * scale;

    // Sample History (Feedback)
    // We need to use non_filtering_sampler or u_sampler? u_sampler for smooth feedback.
    let feedbackColor = textureSampleLevel(dataTextureC, u_sampler, zoomUV, 0.0);

    // Sample Current Video
    let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Create Mask for the Lens
    let lensMask = smoothstep(radius, radius * 0.8, dist); // 1 inside, 0 outside

    // Mix Video and Feedback
    // Inside lens: Mix(Video, Feedback, alpha)
    // We want the feedback to persist.
    // NewFrame = Video * (1-decay) + Feedback * decay?
    // Or just pure feedback inside?
    // Let's add video to feedback to keep it alive.

    let feedbackMix = mix(videoColor, feedbackColor, decay);

    let finalInside = feedbackMix;

    // Outside: Just video
    let finalColor = mix(videoColor, finalInside, lensMask);

    // Write output
    textureStore(writeTexture, global_id.xy, finalColor);

    // Write history for next frame
    textureStore(dataTextureA, global_id.xy, finalColor);

    // Clear depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
