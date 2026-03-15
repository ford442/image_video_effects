// ═══════════════════════════════════════════════════════════════
//  Fluid Vortex - Curl-based velocity field with vorticity confinement
//  Scientific: ω = ∇ × v, tangential velocity ∝ 1/r
//  Features: Multiple vortex centers, turbulent swirls, pressure gradients
//  
//  ALPHA PHYSICS:
//  - Vorticity magnitude affects light scattering
//  - Higher velocity = more turbulent mixing = reduced alpha
//  - Velocity gradients create transparency variations
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // zoomTime, mouseX, mouseY, unused
  zoom_params: vec4<f32>,         // x=vortexStrength, y=coreSize, z=rotationSpeed, w=turbulence
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// ═══════════════════════════════════════════════════════════════
// Hash functions for pseudo-random noise
// ═══════════════════════════════════════════════════════════════
fn hash2(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453;
    return fract(vec2<f32>(n, n * 1.618));
}

fn hash3(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
}

// Value noise for turbulence
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smoothstep
    
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    
    return mix(mix(a.x, b.x, f.x), mix(c.x, d.x, f.x), f.y);
}

// FBM (Fractal Brownian Motion) for organic turbulence
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * noise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    
    return value;
}

// ═══════════════════════════════════════════════════════════════
// Vortex Structure - Defines a single vortex center
// ═══════════════════════════════════════════════════════════════
struct Vortex {
    center: vec2<f32>,
    strength: f32,
    coreRadius: f32,
    rotationDir: f32,  // +1 or -1 for CW/CCW
};

// ═══════════════════════════════════════════════════════════════
// Calculate vorticity (curl) at a point from all vortices
// ω = ∇ × v (scalar in 2D)
// ═══════════════════════════════════════════════════════════════
fn calculateVorticity(uv: vec2<f32>, vortices: array<Vortex, 4>, time: f32) -> f32 {
    var vorticity = 0.0;
    
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let v = vortices[i];
        let toCenter = uv - v.center;
        let dist = length(toCenter);
        
        // Vorticity profile: concentrated in core, falls off as 1/r^2
        // Gaussian core with algebraic tail
        let core = exp(-dist * dist / (v.coreRadius * v.coreRadius));
        let tail = 1.0 / (1.0 + pow(dist / v.coreRadius, 2.0));
        
        // Time-varying vorticity for life-like motion
        let pulse = 1.0 + 0.1 * sin(time * 2.0 + f32(i));
        
        vorticity = vorticity + v.strength * v.rotationDir * (core + 0.3 * tail) * pulse;
    }
    
    return vorticity;
}

// ═══════════════════════════════════════════════════════════════
// Calculate velocity field from vorticity using Biot-Savart-like law
// In 2D: v(x) = Σ (Γ_i / 2πr) * tangent_direction
// Simplified: velocity ∝ strength * (perpendicular_to_r) / (r + core)
// ═══════════════════════════════════════════════════════════════
fn calculateVelocity(uv: vec2<f32>, vortices: array<Vortex, 4>, time: f32) -> vec2<f32> {
    var velocity = vec2<f32>(0.0, 0.0);
    
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let v = vortices[i];
        let toCenter = uv - v.center;
        let dist = length(toCenter);
        
        // Prevent singularity at center
        let softDist = max(dist, v.coreRadius * 0.1);
        
        // Tangential direction (perpendicular to radius)
        // In 2D: tangent = normalize((-y, x)) for CCW rotation
        let tangent = vec2<f32>(-toCenter.y, toCenter.x) / softDist;
        
        // Velocity magnitude: v ∝ strength / r with soft core
        // Vatistas model: v = strength * r / (core^2 + r^2)^(1/2)
        let speed = v.strength * softDist / sqrt(v.coreRadius * v.coreRadius + softDist * softDist);
        
        // Add rotation direction
        velocity = velocity + v.rotationDir * speed * tangent;
        
        // Add radial inflow (suction) for more realistic vortex
        let radialDir = -toCenter / softDist;
        let inflowStrength = 0.1 * v.strength * exp(-softDist / v.coreRadius);
        velocity = velocity + radialDir * inflowStrength;
    }
    
    return velocity;
}

// ═══════════════════════════════════════════════════════════════
// Vorticity confinement - applies force to preserve swirling motion
// Force = ε * (N × ω) where N = ∇|ω| / |∇|ω||
// ═══════════════════════════════════════════════════════════════
fn vorticityConfinement(
    uv: vec2<f32>, 
    vortices: array<Vortex, 4>, 
    time: f32,
    epsilon: f32
) -> vec2<f32> {
    let eps = 0.01;
    
    // Sample vorticity at neighbors
    let w_center = abs(calculateVorticity(uv, vortices, time));
    let w_xp = abs(calculateVorticity(uv + vec2<f32>(eps, 0.0), vortices, time));
    let w_xn = abs(calculateVorticity(uv - vec2<f32>(eps, 0.0), vortices, time));
    let w_yp = abs(calculateVorticity(uv + vec2<f32>(0.0, eps), vortices, time));
    let w_yn = abs(calculateVorticity(uv - vec2<f32>(0.0, eps), vortices, time));
    
    // Gradient of |vorticity|
    let gradW = vec2<f32>(w_xp - w_xn, w_yp - w_yn) / (2.0 * eps);
    let gradWMag = length(gradW) + 0.0001;
    
    // Normalized gradient
    let N = gradW / gradWMag;
    
    // Vorticity at center
    let w = calculateVorticity(uv, vortices, time);
    
    // Force perpendicular to both N and vorticity (in 2D: (Nx, Ny) × w)
    let force = epsilon * vec2<f32>(N.y * w, -N.x * w);
    
    return force;
}

// ═══════════════════════════════════════════════════════════════
// Calculate pressure gradient visualization
// Pressure is high where velocity converges, low where it diverges
// ═══════════════════════════════════════════════════════════════
fn calculatePressure(uv: vec2<f32>, velocity: vec2<f32>, eps: f32) -> f32 {
    // Approximate divergence: ∇ · v
    let div = (
        length(calculateVelocity(uv + vec2<f32>(eps, 0.0), getVortices(0.0), 0.0)) -
        length(calculateVelocity(uv - vec2<f32>(eps, 0.0), getVortices(0.0), 0.0))
    ) / (2.0 * eps);
    
    // Pressure inversely related to divergence
    return -div;
}

// Helper to get vortices array (needed for recursion in pressure calc)
fn getVortices(time: f32) -> array<Vortex, 4> {
    var vortices: array<Vortex, 4>;
    
    // Vortex 1: Primary, follows mouse loosely
    vortices[0] = Vortex(
        vec2<f32>(0.5 + 0.1 * sin(time * 0.3), 0.5 + 0.1 * cos(time * 0.4)),
        0.15,
        0.08,
        1.0
    );
    
    // Vortex 2: Secondary, orbits primary
    let orbitAngle = time * 0.5;
    vortices[1] = Vortex(
        vec2<f32>(0.5 + 0.25 * cos(orbitAngle), 0.5 + 0.25 * sin(orbitAngle)),
        0.1,
        0.06,
        -1.0
    );
    
    // Vortex 3: Counter-rotating, slower
    vortices[2] = Vortex(
        vec2<f32>(0.3 + 0.15 * sin(time * 0.2 + 1.0), 0.7 + 0.1 * cos(time * 0.25)),
        0.08,
        0.05,
        1.0
    );
    
    // Vortex 4: Small, fast, chaotic
    vortices[3] = Vortex(
        vec2<f32>(0.7 + 0.08 * sin(time * 0.8), 0.3 + 0.08 * cos(time * 0.7)),
        0.06,
        0.04,
        -1.0
    );
    
    return vortices;
}

// ═══════════════════════════════════════════════════════════════
// ALPHA PHYSICS: Calculate alpha based on distortion magnitude
// Higher distortion = more scattered light = lower alpha
// ═══════════════════════════════════════════════════════════════
fn calculateDistortionAlpha(
    velocity: vec2<f32>,
    vorticity: f32,
    vortexStrength: f32
) -> f32 {
    let velMag = length(velocity);
    
    // Distortion magnitude combines velocity and vorticity
    let distortionMag = velMag + abs(vorticity) * 0.1;
    
    // Higher distortion = more light scattering = reduced alpha
    // Base alpha from source preservation
    let baseAlpha = 1.0;
    
    // Scattering reduces opacity (physical: turbulent mixing)
    let scatteringLoss = distortionMag * 0.3 * vortexStrength;
    
    // Vorticity creates local transparency variations
    let vorticityAlpha = 1.0 - smoothstep(0.0, 0.5, abs(vorticity)) * 0.2;
    
    return clamp(baseAlpha * vorticityAlpha - scatteringLoss, 0.3, 1.0);
}

// ═══════════════════════════════════════════════════════════════
// Main compute shader
// ═══════════════════════════════════════════════════════════════
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Read parameters
    let vortexStrength = u.zoom_params.x;      // 0.0 to 1.0
    let coreSizeParam = u.zoom_params.y;       // 0.0 to 1.0
    let rotationSpeed = u.zoom_params.z;       // 0.0 to 1.0
    let turbulence = u.zoom_params.w;          // 0.0 to 1.0
    
    // ═══════════════════════════════════════════════════════════
    // Setup vortex centers with animated motion
    // ═══════════════════════════════════════════════════════════
    var vortices: array<Vortex, 4>;
    
    // Scale parameters
    let strengthScale = mix(0.05, 0.3, vortexStrength);
    let coreScale = mix(0.03, 0.15, coreSizeParam);
    let speedScale = mix(0.2, 1.5, rotationSpeed);
    let turbAmount = turbulence * 0.02;
    
    // Vortex 1: Primary central vortex
    let t1 = time * speedScale;
    vortices[0] = Vortex(
        vec2<f32>(
            0.5 + 0.1 * sin(t1 * 0.3),
            0.5 + 0.1 * cos(t1 * 0.4)
        ),
        strengthScale,
        coreScale,
        1.0
    );
    
    // Vortex 2: Orbiting secondary vortex
    let orbitAngle = t1 * 0.5;
    vortices[1] = Vortex(
        vec2<f32>(
            0.5 + 0.25 * cos(orbitAngle),
            0.5 + 0.25 * sin(orbitAngle)
        ),
        strengthScale * 0.7,
        coreScale * 0.8,
        -1.0
    );
    
    // Vortex 3: Counter-rotating, moves in figure-8
    vortices[2] = Vortex(
        vec2<f32>(
            0.3 + 0.15 * sin(t1 * 0.2 + 1.0),
            0.7 + 0.1 * cos(t1 * 0.25)
        ),
        strengthScale * 0.5,
        coreScale * 0.6,
        1.0
    );
    
    // Vortex 4: Small, fast vortex
    vortices[3] = Vortex(
        vec2<f32>(
            0.7 + 0.08 * sin(t1 * 0.8),
            0.3 + 0.08 * cos(t1 * 0.7)
        ),
        strengthScale * 0.4,
        coreScale * 0.5,
        -1.0
    );
    
    // ═══════════════════════════════════════════════════════════
    // Calculate fluid dynamics
    // ═══════════════════════════════════════════════════════════
    
    // Base velocity from vortices
    var velocity = calculateVelocity(uv, vortices, time);
    
    // Add vorticity confinement to preserve swirling
    let confinementForce = vorticityConfinement(uv, vortices, time, 0.02 * vortexStrength);
    velocity = velocity + confinementForce;
    
    // Add turbulent noise
    let turbUV = uv * 3.0 + time * 0.1;
    let turbulenceNoise = vec2<f32>(
        fbm(turbUV + vec2<f32>(0.0, time * 0.05), 3),
        fbm(turbUV + vec2<f32>(100.0, time * 0.05), 3)
    ) - 0.5;
    velocity = velocity + turbulenceNoise * turbAmount;
    
    // Calculate vorticity for visualization and alpha
    let vorticity = calculateVorticity(uv, vortices, time);
    
    // ═══════════════════════════════════════════════════════════
    // Distort UV by velocity field
    // The displacement accumulates the velocity effect
    // ═══════════════════════════════════════════════════════════
    
    // Scale velocity for UV displacement
    let displacementScale = mix(0.02, 0.15, vortexStrength);
    let displacedUV = uv + velocity * displacementScale;
    
    // Add swirling effect based on local vorticity
    let swirlStrength = vorticity * 0.01 * vortexStrength;
    let toCenter = uv - vec2<f32>(0.5);
    let swirlRot = vec2<f32>(
        -toCenter.y * swirlStrength,
        toCenter.x * swirlStrength
    );
    let finalUV = displacedUV + swirlRot;
    
    // ═══════════════════════════════════════════════════════════
    // Sample texture with distorted coordinates
    // ═══════════════════════════════════════════════════════════
    var warpedColor = textureSampleLevel(readTexture, u_sampler, fract(finalUV), 0.0);
    
    // ═══════════════════════════════════════════════════════════
    // Add visual feedback for fluid properties
    // ═══════════════════════════════════════════════════════════
    
    // Velocity magnitude visualization (subtle)
    let velMag = length(velocity);
    let velocityGlow = smoothstep(0.0, 0.5, velMag) * 0.1 * vortexStrength;
    
    // Vorticity-based color shift (shows rotation direction)
    let vorticityColor = vec3<f32>(
        1.0 + sign(vorticity) * 0.1,  // Red for CW
        1.0,                          // Green neutral
        1.0 - sign(vorticity) * 0.1   // Blue for CCW
    );
    var finalRGB = warpedColor.rgb * mix(vec3<f32>(1.0), vorticityColor, velMag * 0.3);
    
    // Add subtle velocity-based brightness
    finalRGB = finalRGB * (1.0 + velocityGlow);
    
    // ═══════════════════════════════════════════════════════════
    // ALPHA CALCULATION with Physical Deformation
    // ═══════════════════════════════════════════════════════════
    let finalAlpha = calculateDistortionAlpha(velocity, vorticity, vortexStrength) * warpedColor.a;
    
    // ═══════════════════════════════════════════════════════════
    // Output
    // ═══════════════════════════════════════════════════════════
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, finalAlpha));
    
    // Pass through depth with velocity-based distortion
    let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, fract(finalUV), 0.0);
    // Add slight depth variation based on vorticity for depth-aware effects
    let depthModulation = 1.0 + velMag * 0.1 * vortexStrength;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthSample.r * depthModulation, 0.0, 0.0, 0.0));
}
