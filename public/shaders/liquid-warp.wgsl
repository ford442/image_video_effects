// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Warp Shader with Alpha Physics
//  Category: liquid-effects
//  Features: velocity field, push/swirl interaction, flow transparency with physical deformation
//
//  ALPHA PHYSICS:
//  - Velocity magnitude maps to liquid film thickness
//  - Swirling regions have different transparency due to vorticity
//  - Decay affects opacity over time (evaporation)
//  - Fresnel effect from surface normal derived from velocity field
//  - Physical: Higher velocity = more turbulence = scattered light = lower alpha
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
  zoom_params: vec4<f32>,  // x=Radius, y=Strength, z=Decay, w=Swirl
};

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate distortion gradient from velocity field
fn calculateDistortionGradient(
    velocity: vec2<f32>,
    uv: vec2<f32>,
    resolution: vec2<f32>
) -> f32 {
    // Calculate velocity magnitude gradient
    let velMag = length(velocity);
    
    // Sample neighboring pixels for gradient
    let eps = 1.0 / resolution.x;
    
    // Approximate gradient magnitude
    let gradient = velMag * 10.0; // Scale for visibility
    
    return gradient;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ALPHA PHYSICS: Calculate alpha based on liquid physics
// ═══════════════════════════════════════════════════════════════════════════════
fn calculateLiquidAlpha(
    velocityMag: f32,
    distRatio: f32,
    swirl: f32,
    distortionGradient: f32,
    baseAlpha: f32
) -> f32 {
  // Fresnel effect (approximate from velocity creating surface normal)
  let F0 = 0.02;
  let normal = normalize(vec3<f32>(
      -velocityMag * 0.5,
      -velocityMag * 0.5,
      1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let fresnel = schlickFresnel(max(0.0, dot(viewDir, normal)), F0);
  
  // Velocity magnitude = liquid film thickness
  // Higher velocity = thicker film BUT more turbulence = scattered light
  let thickness = velocityMag * 3.0 + 0.2;
  
  // Physical: Higher distortion gradient = more light scattering = lower alpha
  let scatteringLoss = distortionGradient * 0.5;
  
  // Swirling regions have different optical properties (vorticity effect)
  let swirlFactor = 1.0 + swirl * 0.02;
  
  // Absorption based on thickness
  let absorption = exp(-thickness * swirlFactor);
  let baseLiquidAlpha = mix(0.4, 0.9, absorption);
  
  // Distance falloff: center of effect = more opaque (higher pressure)
  let centerAlpha = mix(1.0, baseLiquidAlpha, distRatio);
  
  // Apply Fresnel and scattering
  let alpha = baseAlpha * centerAlpha * (1.0 - fresnel * 0.3) - scatteringLoss;
  
  return clamp(alpha, 0.3, 1.0);
}

// Calculate warp color with flow effects and Doppler shift
fn calculateLiquidWarpColor(
    baseColor: vec3<f32>,
    velocity: vec2<f32>,
    swirl: f32,
    distortionGradient: f32
) -> vec3<f32> {
  let velMag = length(velocity);
  
  // Flow tint based on swirl direction (Doppler-like shift)
  let flowTint = vec3<f32>(0.0, 0.08, 0.12) * velMag * swirl * 0.1;
  
  // Motion blur effect based on velocity
  let blurFactor = exp(-velMag * 2.0);
  
  // High distortion causes chromatic separation
  let chromaticShift = distortionGradient * 0.1;
  let rShift = baseColor.r * (1.0 + chromaticShift);
  let bShift = baseColor.b * (1.0 - chromaticShift);
  
  return vec3<f32>(rShift, baseColor.g, bShift) * blurFactor + flowTint;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let radius = u.zoom_params.x * 0.2;
    let strength = u.zoom_params.y * 0.1;
    let decay = 0.9 + u.zoom_params.z * 0.09; // 0.9 to 0.99
    let swirl = u.zoom_params.w * 10.0; // Viscosity/Swirl factor

    // Mouse Interaction
    var mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Read previous velocity field from dataTextureC
    let prevData = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    var velocity = prevData.xy;

    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let distRatio = min(dist / radius, 1.0);

    if (isMouseDown && dist < radius) {
        // Add velocity away from mouse (push)
        let pushDir = normalize(distVec + vec2<f32>(0.0001, 0.0));
        let force = (1.0 - dist / radius) * strength;

        // Add swirl based on distance (vorticity)
        let swirlDir = vec2<f32>(-pushDir.y, pushDir.x);

        velocity = velocity + pushDir * force + swirlDir * force * (swirl * 0.1);
    }

    // Decay velocity (viscosity)
    velocity = velocity * decay;

    // Calculate distortion gradient for physical alpha
    let distortionGradient = calculateDistortionGradient(velocity, uv, resolution);

    // Apply velocity to UV for sampling the image
    let distortedUV = uv - velocity;

    // Sample source with warped coordinates
    let warpedSample = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Store velocity for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(velocity, 0.0, 1.0));

    // ═══════════════════════════════════════════════════════════════════════════════
    // ALPHA AND COLOR CALCULATION with Physical Deformation
    // ═══════════════════════════════════════════════════════════════════════════════
    
    let velocityMag = length(velocity);
    
    // Calculate color with flow effects and Doppler shift
    let warpColor = calculateLiquidWarpColor(warpedSample.rgb, velocity, swirl, distortionGradient);
    
    // Calculate alpha with liquid physics
    let alpha = calculateLiquidAlpha(velocityMag, distRatio, swirl, distortionGradient, warpedSample.a);

    // Output color with alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(warpColor, alpha));
    
    // Store depth with velocity-based modulation
    let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, distortedUV, 0.0);
    let depthModulation = 1.0 + velocityMag * 0.2;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthSample.r * depthModulation, 0.0, 0.0, 0.0));
}
