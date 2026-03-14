// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Warp Shader with Alpha Physics
//  Category: liquid-effects
//  Features: velocity field, push/swirl interaction, flow transparency
//
//  ALPHA PHYSICS:
//  - Velocity magnitude maps to liquid film thickness
//  - Swirling regions have different transparency
//  - Decay affects opacity over time
// ═══════════════════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,  // x=Radius, y=Strength, z=Decay, w=Swirl
};

// Schlick's approximation for Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate warp alpha based on velocity field
fn calculateWarpAlpha(
    velocityMag: f32,
    distRatio: f32,
    swirl: f32
) -> f32 {
  // Fresnel effect (approximate from velocity)
  let F0 = 0.02;
  let normal = normalize(vec3<f32>(
      -velocityMag * 0.5,
      -velocityMag * 0.5,
      1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let fresnel = schlickFresnel(max(0.0, dot(viewDir, normal)), F0);
  
  // Velocity magnitude = liquid film thickness
  // Higher velocity = thicker film
  let thickness = velocityMag * 3.0 + 0.2;
  
  // Swirling regions have different optical properties
  let swirlFactor = 1.0 + swirl * 0.2;
  
  // Absorption
  let absorption = exp(-thickness * swirlFactor);
  let baseAlpha = mix(0.4, 0.8, absorption);
  
  // Distance falloff: center of effect = more opaque
  let centerAlpha = mix(1.0, baseAlpha, distRatio);
  
  let alpha = centerAlpha * (1.0 - fresnel * 0.3);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate warp color with flow effects
fn calculateWarpColor(
    baseColor: vec3<f32>,
    velocity: vec2<f32>,
    swirl: f32
) -> vec3<f32> {
  let velMag = length(velocity);
  
  // Flow tint based on swirl direction
  let flowTint = vec3<f32>(0.0, 0.08, 0.12) * velMag * swirl;
  
  // Motion blur effect
  let blurFactor = exp(-velMag * 2.0);
  
  return baseColor * blurFactor + flowTint;
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

    // Read previous velocity field from dataTextureC (stores offset X, offset Y, 0, 0)
    let prevData = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    var velocity = prevData.xy;

    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let distRatio = min(dist / radius, 1.0);

    if (isMouseDown && dist < radius) {
        // Add velocity away from mouse (push)
        let pushDir = normalize(distVec + vec2<f32>(0.0001, 0.0)); // Avoid NaN
        let force = (1.0 - dist / radius) * strength;

        // Add some swirl based on distance
        let swirlDir = vec2<f32>(-pushDir.y, pushDir.x);

        velocity = velocity + pushDir * force + swirlDir * force * (swirl * 0.1);
    }

    // Decay velocity
    velocity = velocity * decay;

    // Apply velocity to UV for sampling the image
    let distortedUV = uv - velocity;

    let baseColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;

    // Store velocity for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(velocity, 0.0, 1.0));

    // ═══════════════════════════════════════════════════════════════════════════════
    // ALPHA CALCULATION
    // ═══════════════════════════════════════════════════════════════════════════════
    
    let velocityMag = length(velocity);
    
    // Calculate color with flow effects
    let warpColor = calculateWarpColor(baseColor, velocity, swirl);
    
    // Calculate alpha
    let alpha = calculateWarpAlpha(velocityMag, distRatio, swirl);

    // Output color with alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(warpColor, alpha));
}
