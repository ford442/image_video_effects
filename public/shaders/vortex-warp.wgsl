// ═══════════════════════════════════════════════════════════════════════════════
//  Vortex Warp with Alpha Physics
//  Scientific: Rotational deformation with physical light transmission
//  
//  ALPHA PHYSICS:
//  - Rotational displacement creates angular distortion gradients
//  - Twist parameter affects light path length through medium
//  - Spiral twist accumulates opacity changes
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Calculate rotational distortion magnitude
fn calculateRotationalDistortion(
    percent: f32,
    strength: f32,
    twist: f32,
    dist: f32
) -> f32 {
    // Base rotation distortion
    let rotationDistortion = abs(strength) * percent * percent;
    
    // Spiral adds cumulative distortion
    let spiralDistortion = abs(twist) * percent * dist;
    
    return rotationDistortion + spiralDistortion * 0.1;
}

// Physical alpha calculation for rotational warping
fn calculateRotationalAlpha(
    baseAlpha: f32,
    distortionMag: f32,
    percent: f32
) -> f32 {
    // Rotational motion creates centrifugal effects on opacity
    // Center = higher pressure = more opaque
    // Edge = lower pressure = more transparent
    let pressureAlpha = mix(0.9, 0.6, percent);
    
    // Distortion causes light scattering
    let scatteringLoss = distortionMag * 0.3;
    
    return clamp(baseAlpha * pressureAlpha - scatteringLoss, 0.4, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let strength = (u.zoom_params.x - 0.5) * 10.0; // Range -5.0 to 5.0
    let radius = u.zoom_params.y * 0.5 + 0.05;     // Range 0.05 to 0.55
    let twist = u.zoom_params.z * 10.0;            // Range 0.0 to 10.0

    var mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Center of effect is mouse position
    var center = mouse;

    // Vector from center to pixel, corrected for aspect
    let diff = uv - center;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);

    var finalUV = uv;
    var distortionMag = 0.0;
    var percent = 0.0;

    if (dist < radius) {
        // Calculate factor based on distance (1.0 at center, 0.0 at edge)
        percent = (radius - dist) / radius;

        // Non-linear falloff for smoother look
        let weight = percent * percent;

        // Calculate rotation angle
        let theta = weight * strength;

        // Apply twist: radius dependent rotation
        let spiralAngle = twist * weight * dist;

        let totalAngle = theta + spiralAngle;

        // Calculate distortion magnitude for alpha physics
        distortionMag = calculateRotationalDistortion(percent, strength, twist, dist);

        let s = sin(totalAngle);
        let c = cos(totalAngle);

        // Rotate the offset vector
        let squareDiff = vec2<f32>(diff.x * aspect, diff.y);
        let rotatedSquareDiff = vec2<f32>(
            squareDiff.x * c - squareDiff.y * s,
            squareDiff.x * s + squareDiff.y * c
        );

        // Convert back to UV space
        let rotatedDiff = vec2<f32>(rotatedSquareDiff.x / aspect, rotatedSquareDiff.y);

        finalUV = center + rotatedDiff;
    }

    // Sample texture at distorted coordinates
    let warpedSample = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    
    // Calculate physical alpha
    let finalAlpha = calculateRotationalAlpha(warpedSample.a, distortionMag, percent);

    // Output with RGBA
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(warpedSample.rgb, finalAlpha));

    // Pass through depth with rotational distortion effect
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Rotational effects create depth uncertainty proportional to distortion
    let depthMod = 1.0 + distortionMag * 0.05;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
