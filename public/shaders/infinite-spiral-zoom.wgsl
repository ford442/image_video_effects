// ═══════════════════════════════════════════════════════════════════════════════
//  Infinite Spiral Zoom with Alpha Physics
//  Scientific: Log-polar transformation with spiral warping and light transmission
//  
//  ALPHA PHYSICS:
//  - Log-polar transform creates radial distortion affecting opacity
//  - Spiral twist creates angular shear = scattered alpha
//  - Tiling/branching creates repetitive opacity patterns
//  - Zoom speed affects motion blur alpha
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
  zoom_params: vec4<f32>,  // x=ZoomSpeed, y=SpiralTwist, z=Branches, w=CenterOffset
  ripples: array<vec4<f32>, 50>,
};

// Calculate spiral distortion magnitude
fn calculateSpiralDistortion(
    r: f32,
    twist: f32,
    zoomSpeed: f32,
    branches: f32
) -> vec2<f32> {
    // Twist creates angular distortion
    let twistDistortion = abs(twist) * log(r + 1.0);
    
    // Zoom speed creates radial motion blur
    let zoomDistortion = abs(zoomSpeed) * 0.1;
    
    // Branching creates repetitive distortion
    let branchDistortion = branches * 0.05;
    
    return vec2<f32>(twistDistortion, zoomDistortion + branchDistortion);
}

// Calculate log-polar transform alpha
fn calculateLogPolarAlpha(
    baseAlpha: f32,
    distortionMag: vec2<f32>,
    r: f32,
    isNearSingularity: bool
) -> f32 {
    // Near singularity = extreme distortion = scattered light
    if (isNearSingularity) {
        return 0.3; // Very transparent near center
    }
    
    // Twist creates shear which reduces coherence
    let shearFactor = 1.0 - distortionMag.x * 0.1;
    
    // Zoom motion creates blur
    let motionBlur = 1.0 - distortionMag.y * 0.2;
    
    // Radial distance affects focus (log transform depth cue)
    let depthFactor = 1.0 / (1.0 + log(r + 1.0) * 0.1);
    
    return clamp(baseAlpha * shearFactor * motionBlur * depthFactor, 0.3, 1.0);
}

// Calculate tiling alpha pattern
fn calculateTilingAlpha(
    baseAlpha: f32,
    uv_mapped: vec2<f32>,
    branches: f32
) -> f32 {
    // Seam between tiles has slight transparency
    let seamX = smoothstep(0.0, 0.02, uv_mapped.x) * (1.0 - smoothstep(0.98, 1.0, uv_mapped.x));
    let seamY = smoothstep(0.0, 0.02, uv_mapped.y) * (1.0 - smoothstep(0.98, 1.0, uv_mapped.y));
    
    // More branches = more seams = slightly more scattered
    let seamFactor = 1.0 - (1.0 - seamX * seamY) * (branches / 6.0) * 0.1;
    
    return baseAlpha * seamFactor;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;

    // Normalize coordinates
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Mouse position
    var mouse = u.zoom_config.yz;

    // Parameters
    let zoom_speed = (u.zoom_params.x - 0.5) * 4.0;
    let twist = (u.zoom_params.y - 0.5) * 3.14159;
    let branches = floor(u.zoom_params.z * 5.0) + 1.0;
    let offset_val = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;

    // Vector from mouse to pixel
    var p = uv - mouse;
    p.x *= aspect;

    // Avoid singularity
    let r = length(p);
    if (r < 0.001) {
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 0.3));
        return;
    }

    let angle = atan2(p.y, p.x);

    // Calculate distortion magnitude
    let distortionMag = calculateSpiralDistortion(r, twist, zoom_speed, branches);

    // Log-Polar Transformation
    var u_coord = log(r);
    var v_coord = angle / 6.28318;

    // Apply twist (shear in log-polar space)
    v_coord += u_coord * twist * 0.2;

    // Apply zoom
    u_coord -= time * zoom_speed;

    // Scale for tiling
    let uv_mapped = vec2<f32>(u_coord, v_coord * branches);

    // Convert back to wrapping UVs
    var final_uv = fract(uv_mapped);

    // Add center offset distortion
    final_uv += vec2<f32>(offset_val * 0.1 * sin(v_coord * 10.0), 0.0);
    final_uv = fract(final_uv);

    // Sample texture
    let warpedSample = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);
    
    // Calculate alphas
    let logPolarAlpha = calculateLogPolarAlpha(warpedSample.a, distortionMag, r, r < 0.01);
    let finalAlpha = calculateTilingAlpha(logPolarAlpha, uv_mapped, branches);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(warpedSample.rgb, finalAlpha));

    // Preserve depth with distortion
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, final_uv, 0.0).r;
    // Spiral distortion affects depth perception
    let depthMod = 1.0 + distortionMag.x * 0.1 + distortionMag.y * 0.05;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d * depthMod, 0.0, 0.0, 0.0));
}
