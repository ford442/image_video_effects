// ═══════════════════════════════════════════════════════════════════════════════
//  Infinite Zoom Lens with Alpha Physics
//  Scientific: Feedback-based zoom lens with physical light transmission
//  
//  ALPHA PHYSICS:
//  - Feedback accumulation affects opacity over time
//  - Zoom scale creates compression/expansion opacity changes
//  - Lens mask creates edge transparency falloff
//  - Rotation creates shear-based alpha variations
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ZoomStrength, y=Radius, z=FeedbackDecay, w=Rotation
  ripples: array<vec4<f32>, 50>,
};

// Calculate zoom lens distortion magnitude
fn calculateZoomDistortion(
    dist: f32,
    radius: f32,
    scale: f32,
    rotation: f32
) -> vec2<f32> {
    // Scale distortion
    let scaleDistortion = abs(scale - 1.0);
    
    // Rotation distortion (shear)
    let rotationDistortion = abs(rotation) * dist / radius;
    
    return vec2<f32>(scaleDistortion, rotationDistortion);
}

// Calculate feedback alpha
fn calculateFeedbackAlpha(
    videoAlpha: f32,
    feedbackAlpha: f32,
    decay: f32,
    lensMask: f32
) -> f32 {
    // Inside lens: mix video and feedback alphas
    let blendedAlpha = mix(videoAlpha, feedbackAlpha, decay);
    
    // Lens mask creates edge transparency
    let maskedAlpha = blendedAlpha * lensMask + videoAlpha * (1.0 - lensMask);
    
    // Decay causes gradual transparency loss
    let decayFactor = 0.9 + decay * 0.1;
    
    return clamp(maskedAlpha * decayFactor, 0.5, 1.0);
}

// Calculate zoom scale alpha effect
fn calculateZoomScaleAlpha(
    baseAlpha: f32,
    scale: f32,
    distortionMag: f32
) -> f32 {
    // Zoom in (scale < 1) = compression = more opaque
    // Zoom out (scale > 1) = expansion = more transparent
    let compressionFactor = 1.0 / scale;
    
    // Distortion causes scattering
    let scatteringLoss = distortionMag * 0.2;
    
    return clamp(baseAlpha * compressionFactor - scatteringLoss, 0.4, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Params
    let scale = 1.0 - (u.zoom_params.x - 0.5) * 0.2;
    let radius = u.zoom_params.y * 0.5 + 0.01;
    let decay = u.zoom_params.z;
    let rotation = (u.zoom_params.w - 0.5) * 0.5;

    var mouse = u.zoom_config.yz;

    // Distance from mouse
    let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

    // Calculate distortion magnitude
    let distortionMag = calculateZoomDistortion(dist, radius, scale, rotation);

    // Calculate Feedback UV with rotation and scale
    let offset = (uv - mouse);
    let cosR = cos(rotation);
    let sinR = sin(rotation);
    let rotated = vec2<f32>(
        offset.x * cosR - offset.y * sinR,
        offset.x * sinR + offset.y * cosR
    );
    let zoomUV = mouse + rotated * scale;

    // Sample History (Feedback)
    let feedbackSample = textureSampleLevel(dataTextureC, u_sampler, zoomUV, 0.0);

    // Sample Current Video
    let videoSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Create Lens Mask
    let lensMask = smoothstep(radius, radius * 0.8, dist);

    // Calculate alphas
    let feedbackAlpha = calculateFeedbackAlpha(
        videoSample.a,
        feedbackSample.a,
        decay,
        lensMask
    );
    
    let finalAlpha = calculateZoomScaleAlpha(feedbackAlpha, scale, distortionMag.x);

    // Mix Video and Feedback with alpha
    let feedbackMix = vec4<f32>(
        mix(videoSample.rgb, feedbackSample.rgb, decay),
        feedbackAlpha
    );

    let finalInside = feedbackMix;
    let finalColor = mix(videoSample, finalInside, lensMask);
    
    // Apply final alpha
    let outputColor = vec4<f32>(finalColor.rgb, finalAlpha * lensMask + videoSample.a * (1.0 - lensMask));

    // Write output
    textureStore(writeTexture, vec2<i32>(global_id.xy), outputColor);

    // Write history for next frame
    textureStore(dataTextureA, global_id.xy, outputColor);

    // Clear depth with distortion effect
    let depthUncertainty = distortionMag.x + distortionMag.y;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthUncertainty * 0.1, 0.0, 0.0, 0.0));
}
