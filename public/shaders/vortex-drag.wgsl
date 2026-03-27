// ═══════════════════════════════════════════════════════════════════════════════
//  Vortex Drag with Alpha Physics
//  Scientific: Combined twist and pinch deformation with physical light properties
//  
//  ALPHA PHYSICS:
//  - Twist creates angular distortion affecting light paths
//  - Pinch creates radial compression/expansion changing opacity
//  - Combined effect simulates viscous fluid drag
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Calculate drag distortion magnitude combining twist and pinch
fn calculateDragDistortion(
    effectT: f32,
    twistStrength: f32,
    pinchStrength: f32
) -> vec2<f32> {
    // Twist distortion component (angular)
    let twistMag = abs(twistStrength) * effectT * effectT;
    
    // Pinch distortion component (radial)
    let pinchMag = abs(pinchStrength) * effectT;
    
    return vec2<f32>(twistMag, pinchMag);
}

// Calculate alpha for drag effect
// Combines rotational and compressional physics
fn calculateDragAlpha(
    baseAlpha: f32,
    twistDistortion: f32,
    pinchDistortion: f32,
    effectT: f32
) -> f32 {
    // Pinch in (zoom) = compression = higher density = more opaque
    // Pinch out (bulge) = expansion = lower density = more transparent
    let compressionFactor = 1.0 - pinchDistortion * 0.3;
    
    // Twist creates shear which reduces coherence (transparency)
    let shearFactor = 1.0 - twistDistortion * 0.2;
    
    // Edge falloff
    let edgeFade = effectT * 0.3 + 0.7;
    
    return clamp(baseAlpha * compressionFactor * shearFactor * edgeFade, 0.4, 1.0);
}

// Color adjustment for drag effects
fn applyDragColorShift(
    color: vec3<f32>,
    twistDistortion: f32,
    pinchDistortion: f32
) -> vec3<f32> {
    // Compression causes slight warming
    let compressionTint = vec3<f32>(1.05, 1.0, 0.95) * (1.0 + pinchDistortion * 0.1);
    
    // Shear causes subtle chromatic separation
    let shearTint = vec3<f32>(
        1.0 + twistDistortion * 0.05,
        1.0,
        1.0 - twistDistortion * 0.05
    );
    
    return color * compressionTint * shearTint;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let twistStrength = (u.zoom_params.x - 0.5) * 20.0; // -10 to +10
    let radius = mix(0.1, 0.8, u.zoom_params.y);
    let pinchStrength = (u.zoom_params.z - 0.5) * 2.0; // -1 to +1
    let hardness = mix(0.0, 0.95, u.zoom_params.w);

    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Vector from mouse to current pixel
    var dVec = uv - mousePos;
    dVec.x *= aspect;
    let dist = length(dVec);

    // Effect Strength with smoothstep falloff
    let effectT = 1.0 - smoothstep(radius * (1.0 - hardness), radius, dist);

    var finalUV = uv;
    var distortionComponents = vec2<f32>(0.0);

    if (effectT > 0.0) {
        // Calculate distortion components
        distortionComponents = calculateDragDistortion(effectT, twistStrength, pinchStrength);
        
        // Twist: Angle depends on distance from center
        let angle = twistStrength * effectT * effectT;
        let s = sin(angle);
        let c = cos(angle);

        // Rotate dVec
        var rotatedDVec = vec2(
            dVec.x * c - dVec.y * s,
            dVec.x * s + dVec.y * c
        );

        // Pinch
        // If pinch > 0 (zoom in), sample closer to center, multiply by < 1
        // If pinch < 0 (zoom out / bulge), sample further, multiply by > 1
        let pinchFactor = 1.0 - (pinchStrength * effectT);
        rotatedDVec = rotatedDVec * pinchFactor;

        // Restore aspect and UV
        rotatedDVec.x /= aspect;
        finalUV = mousePos + rotatedDVec;
    }

    // Sample with warped coordinates
    let warpedSample = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    
    // Calculate physical alpha
    let finalAlpha = calculateDragAlpha(
        warpedSample.a, 
        distortionComponents.x, 
        distortionComponents.y, 
        effectT
    );
    
    // Apply color shifts based on distortion
    let finalRGB = applyDragColorShift(warpedSample.rgb, distortionComponents.x, distortionComponents.y);

    // Output RGBA
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(finalRGB, finalAlpha));

    // Pass depth with distortion-based modification
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Pinch affects perceived depth (compression/expansion)
    let depthMod = 1.0 + distortionComponents.y * 0.1;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth * depthMod, 0.0, 0.0, 0.0));
}
