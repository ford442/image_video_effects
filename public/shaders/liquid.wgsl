// ═══════════════════════════════════════════════════════════════════════════════
//  Surface Tension Liquid Shader with Alpha Physics
//  Category: liquid-effects
//  Features: capillary waves, Laplace pressure, fluid transparency, Beer-Lambert
//
//  SCIENTIFIC BASIS:
//  - Capillary waves: short wavelength ripples from surface tension
//  - Laplace pressure: Δp = γκ where γ = surface tension, κ = mean curvature
//  - Beer-Lambert law: I = I₀ exp(-εcd) for light attenuation in fluids
//  - Fresnel equations: reflection coefficient at fluid boundaries
//  - Schlick's approximation: R(θ) = R₀ + (1-R₀)(1-cos θ)⁵
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // unused, mouseX, mouseY, unused
  zoom_params: vec4<f32>,         // surfaceTension, gravityScale, damping, turbidity
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// Sample height field from dataTextureC (persistent storage)
fn sampleHeight(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
}

// Sample height with boundary handling (clamp to edge = zero height at boundaries)
fn sampleHeightClamped(uv: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
  let clampedUV = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
  return sampleHeight(clampedUV);
}

// Calculate Laplacian (∇²h) using 5-point stencil
fn laplacian(uv: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
  let center = sampleHeightClamped(uv, pixelSize);
  let left   = sampleHeightClamped(uv - vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let right  = sampleHeightClamped(uv + vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let bottom = sampleHeightClamped(uv - vec2<f32>(0.0, pixelSize.y), pixelSize);
  let top    = sampleHeightClamped(uv + vec2<f32>(0.0, pixelSize.y), pixelSize);
  
  return (left + right + bottom + top - 4.0 * center);
}

// Calculate biharmonic operator (∇⁴h = ∇²(∇²h)) for surface tension term
fn biharmonic(uv: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
  let centerLap = laplacian(uv, pixelSize);
  let leftLap   = laplacian(uv - vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let rightLap  = laplacian(uv + vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let bottomLap = laplacian(uv - vec2<f32>(0.0, pixelSize.y), pixelSize);
  let topLap    = laplacian(uv + vec2<f32>(0.0, pixelSize.y), pixelSize);
  
  return (leftLap + rightLap + bottomLap + topLap - 4.0 * centerLap);
}

// Calculate surface normal from height gradient
fn calculateNormal(uv: vec2<f32>, pixelSize: vec2<f32>, heightScale: f32) -> vec3<f32> {
  let left   = sampleHeightClamped(uv - vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let right  = sampleHeightClamped(uv + vec2<f32>(pixelSize.x, 0.0), pixelSize);
  let bottom = sampleHeightClamped(uv - vec2<f32>(0.0, pixelSize.y), pixelSize);
  let top    = sampleHeightClamped(uv + vec2<f32>(0.0, pixelSize.y), pixelSize);
  
  let dx = (right - left) * heightScale;
  let dy = (top - bottom) * heightScale;
  
  return normalize(vec3<f32>(-dx, -dy, 2.0));
}

// Capillary wave phase velocity for given wavelength
// v = sqrt((γk)/ρ + g/k) where k = 2π/λ
fn capillaryWaveSpeed(wavelength: f32, surfaceTension: f32, gravity: f32, density: f32) -> f32 {
  let k = 6.28318530718 / wavelength;  // 2π/λ
  let tensionTerm = (surfaceTension * k) / density;
  let gravityTerm = gravity / k;
  return sqrt(tensionTerm + gravityTerm);
}

// Meniscus (boundary) effect - height elevation near walls
fn meniscusEffect(uv: vec2<f32>, depth: f32, surfaceTension: f32) -> f32 {
  // Only near boundaries (where depth transitions)
  let boundaryWidth = 0.02;
  let distToSurface = 1.0 - depth;
  
  if (distToSurface < boundaryWidth && depth > 0.5) {
    let t = distToSurface / boundaryWidth;
    // Capillary rise profile: exponential decay from wall
    let meniscusHeight = 0.05 * surfaceTension * exp(-t * 8.0);
    return meniscusHeight;
  }
  return 0.0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// FLUID TRANSPARENCY PHYSICS
// ═══════════════════════════════════════════════════════════════════════════════

// Schlick's approximation for Fresnel reflection
// R(θ) = R₀ + (1-R₀)(1-cos θ)⁵
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate fluid alpha based on physics:
// - Beer-Lambert law for absorption
// - Fresnel reflection at boundaries
// - Depth-based thickness
fn calculateFluidAlpha(
    baseColor: vec3<f32>,
    liquidThickness: f32,
    viewDotNormal: f32,
    turbidity: f32,
    isBackground: f32
) -> f32 {
  // Fresnel: more reflective at glancing angles = less transparent
  // Water F0 ≈ 0.02, but for artistic control we scale it
  let F0 = 0.02;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  
  // Beer-Lambert law: absorption increases with thickness and turbidity
  // Shallow liquid = more transparent (alpha ~ 0.3-0.6)
  // Deep liquid = more opaque (alpha ~ 0.8-1.0)
  let effectiveDepth = liquidThickness * (1.0 + turbidity * 2.0);
  
  // Absorption coefficient varies by wavelength (simplified)
  // Water absorbs red light more than blue
  let absorption = exp(-effectiveDepth * 2.0);
  
  // Combine: alpha is reduced by Fresnel reflection and absorption
  // Background areas (no liquid) should be fully transparent
  let baseAlpha = mix(0.3, 0.95, absorption * isBackground);
  
  // Fresnel reduces transmission (increases effective opacity from reflection)
  let alpha = baseAlpha * (1.0 - fresnel * 0.5);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate liquid color with wavelength-dependent absorption
fn calculateLiquidColor(
    baseColor: vec3<f32>,
    liquidThickness: f32,
    turbidity: f32,
    height: f32
) -> vec3<f32> {
  // Beer-Lambert: different wavelengths absorbed differently
  // Water: more red absorbed (slight blue tint)
  // Viscous fluids: more scattering (whitish)
  let absorptionR = exp(-liquidThickness * (1.0 + turbidity));
  let absorptionG = exp(-liquidThickness * (0.8 + turbidity * 0.9));
  let absorptionB = exp(-liquidThickness * (0.6 + turbidity * 0.8));
  
  // Add subtle color tint based on liquid height
  let heightTint = vec3<f32>(0.0, 0.1, 0.15) * height * 0.5;
  
  return vec3<f32>(
      baseColor.r * absorptionR,
      baseColor.g * absorptionG + heightTint.g,
      baseColor.b * absorptionB + heightTint.b
  );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let pixelSize = vec2<f32>(1.0) / resolution;
  
  // Get depth for depth-aware effects
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // PARAMETERS (from zoom_params)
  // ═══════════════════════════════════════════════════════════════════════════════
  let surfaceTension = u.zoom_params.x * 0.5 + 0.1;  // γ: 0.1 to 0.6
  let gravityScale = u.zoom_params.y * 2.0 + 0.5;    // g: 0.5 to 2.5
  let damping = u.zoom_params.z * 0.15 + 0.02;       // damping: 0.02 to 0.17
  let turbidity = u.zoom_params.w;                    // turbidity: 0.0 to 1.0
  
  // Physical constants (normalized)
  let density = 1.0;  // ρ (water = 1)
  let dt = 0.016;     // Time step (60fps)
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // READ PERSISTENT HEIGHT FIELD
  // ═══════════════════════════════════════════════════════════════════════════════
  // dataTextureC stores: (h_prev, h_curr, velocity, age)
  let persistentData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let h_prev = persistentData.r;  // Height at t-1
  let h_curr = persistentData.g;  // Height at t
  let velocity = persistentData.b; // ∂h/∂t
  let age = persistentData.a;      // Time since perturbation
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // CAPILLARY WAVE PHYSICS
  // Wave equation with surface tension: ∂²h/∂t² = (γ/ρ)∇⁴h - g∇²h - damping*∂h/∂t
  // ═══════════════════════════════════════════════════════════════════════════════
  var newHeight = h_curr;
  var newVelocity = velocity;
  
  // Only simulate on background (water surface)
  if (backgroundFactor > 0.01) {
    // Calculate spatial derivatives
    let lapH = laplacian(uv, pixelSize);
    let biLapH = biharmonic(uv, pixelSize);
    
    // Capillary wave acceleration (dispersive term): (γ/ρ)∇⁴h
    let capillaryAcceleration = (surfaceTension / density) * biLapH * 0.001;
    
    // Gravity wave acceleration: -g∇²h
    let gravityAcceleration = -gravityScale * lapH * 0.1;
    
    // Total acceleration
    let acceleration = capillaryAcceleration + gravityAcceleration - damping * velocity;
    
    // Semi-implicit Euler integration
    newVelocity = velocity + acceleration * dt;
    newHeight = h_curr + newVelocity * dt;
    
    // Add meniscus effect at boundaries
    newHeight += meniscusEffect(uv, depth, surfaceTension) * 0.1;
    
    // Soft clamp to prevent explosion
    newHeight = clamp(newHeight, -0.5, 0.5);
    newVelocity = clamp(newVelocity, -1.0, 1.0);
  }
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // RIPPLE SOURCES (Mouse-driven + Ambient)
  // ═══════════════════════════════════════════════════════════════════════════════
  var sourceHeight = 0.0;
  var sourceVelocity = 0.0;
  
  // --- Mouse-driven Ripples with Capillary Dispersion ---
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    
    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let directionVec = uv - rippleData.xy;
      let dist = length(directionVec);
      
      if (dist > 0.0001) {
        // Depth factor affects ripple propagation
        let rippleOriginDepth = 1.0 - textureSampleLevel(
          readDepthTexture, non_filtering_sampler, rippleData.xy, 0.0
        ).r;
        
        // Capillary wave speed varies with wavelength (dispersion)
        // Short waves (capillary) move faster than long waves (gravity)
        let wavelengthBase = 0.1;  // Base wavelength
        let capillarySpeed = capillaryWaveSpeed(
          wavelengthBase * (0.5 + rippleOriginDepth * 0.5),
          surfaceTension,
          gravityScale,
          density
        );
        
        // Dispersion: different frequencies propagate at different speeds
        let waveNumber = 20.0;  // Spatial frequency
        let phase = dist * waveNumber - timeSinceClick * capillarySpeed * 3.0;
        
        // Wave packet envelope (spreads and decays)
        let packetWidth = 0.3 + timeSinceClick * 0.1;
        let envelope = exp(-(dist * dist) / (packetWidth * packetWidth));
        
        // Time attenuation
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 2.5);
        
        // Capillary wave amplitude (stronger for short wavelengths)
        let capillaryAmp = 0.5 * 0.02 * mix(0.3, 1.0, rippleOriginDepth);
        
        sourceHeight += sin(phase) * envelope * attenuation * capillaryAmp;
        sourceVelocity += cos(phase) * envelope * attenuation * capillaryAmp * capillarySpeed;
      }
    }
  }
  
  // --- Ambient Capillary Waves (Background Micro-ripples) ---
  var ambientHeight = 0.0;
  if (backgroundFactor > 0.0) {
    let time = currentTime * 0.5;
    let ambientFreq = 25.0;  // Higher freq = capillary waves
    
    // Multiple interfering wave trains for realistic look
    let wave1 = sin(uv.x * ambientFreq + time * 2.0);
    let wave2 = sin(uv.y * ambientFreq * 1.3 + time * 1.7);
    let wave3 = sin((uv.x + uv.y) * ambientFreq * 0.7 + time * 2.3);
    let wave4 = sin(length(uv - vec2<f32>(0.5)) * ambientFreq * 1.5 - time * 3.0);
    
    // Interference pattern
    ambientHeight = (wave1 + wave2 * 0.5 + wave3 * 0.3 + wave4 * 0.2) * 0.003;
    ambientHeight *= surfaceTension * backgroundFactor;  // Scale by surface tension
  }
  
  // Apply sources to height field
  newHeight += sourceHeight + ambientHeight;
  newVelocity += sourceVelocity;
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // STORE UPDATED HEIGHT FIELD FOR NEXT FRAME
  // ═══════════════════════════════════════════════════════════════════════════════
  let newAge = age + dt;
  let heightOutput = vec4<f32>(h_curr, newHeight, newVelocity, newAge);
  textureStore(dataTextureA, global_id.xy, heightOutput);
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // VISUAL OUTPUT: Refraction from Surface Gradient with Alpha Physics
  // ═══════════════════════════════════════════════════════════════════════════════
  
  // Calculate surface normal from height field for lighting/refraction
  let normal = calculateNormal(uv, pixelSize, 0.5 * surfaceTension);
  
  // Refraction displacement based on surface slope (Snell's law approximation)
  let refractionStrength = 0.02 * surfaceTension;
  let refractDisplacement = normal.xy * refractionStrength * backgroundFactor;
  
  // Total displacement combines refraction and explicit waves
  let totalDisplacement = refractDisplacement + vec2<f32>(newHeight * 0.01);
  
  // Sample color with displacement
  let colorUV = uv + totalDisplacement;
  let baseColor = textureSampleLevel(readTexture, u_sampler, colorUV, 0.0).rgb;
  
  // Add specular highlight from surface curvature (Laplace pressure visualization)
  let curvature = laplacian(uv, pixelSize);
  let laplacePressure = abs(curvature) * surfaceTension * 2.0;
  let specular = pow(max(0.0, normal.z), 20.0) * laplacePressure * 0.3;
  
  // ═══════════════════════════════════════════════════════════════════════════════
  // ALPHA CHANNEL CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════════
  
  // Liquid thickness derived from wave height (absolute value represents volume)
  let liquidThickness = abs(newHeight) * 2.0 + 0.1;
  
  // View direction (assuming looking down Z axis)
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);
  
  // Calculate liquid color with wavelength-dependent absorption
  let liquidColor = calculateLiquidColor(baseColor, liquidThickness, turbidity, newHeight);
  
  // Calculate alpha based on physics
  let alpha = calculateFluidAlpha(liquidColor, liquidThickness, viewDotNormal, turbidity, backgroundFactor);
  
  // Add specular to final color
  let finalColor = liquidColor + vec3<f32>(specular);
  
  // Store RGBA with calculated alpha
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  
  // Update depth texture
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
