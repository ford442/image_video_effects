// ═══════════════════════════════════════════════════════════════════════════════
//  Navier-Stokes Fluid Displacement with Alpha Physics
//  Category: liquid-effects
//  Features: mouse-driven, multi-pass, depth-aware, fluid transparency
//
//  Implements simplified Navier-Stokes equations for incompressible flow:
//  - ∂v/∂t = -(v·∇)v - ∇p + ν∇²v + f
//  - ∇·v = 0 (incompressibility via pressure projection)
//
//  Velocity field stored in dataTextureA (RG channels)
//  Pressure field stored in dataTextureA (B channel)
//
//  ALPHA PHYSICS:
//  - Velocity magnitude maps to liquid thickness
//  - Beer-Lambert absorption based on flow density
//  - Fresnel reflection at flow boundaries
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // time, mouseX, mouseY, mouseDown
  zoom_params: vec4<f32>,         // viscosity, pressure_iterations, flow_speed, turbidity
  ripples: array<vec4<f32>, 50>,
};

// Constants
const DT: f32 = 0.016;              // Time step (60fps)
const DISSIPATION: f32 = 0.995;      // Velocity decay
const PRESSURE_ALPHA: f32 = 0.25;    // Jacobi relaxation factor

// Schlick's approximation for Fresnel reflection
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate fluid alpha based on flow properties
fn calculateFlowAlpha(
    flowMagnitude: f32,
    pressure: f32,
    turbidity: f32,
    viewDotNormal: f32
) -> f32 {
  // Fresnel: more reflective at glancing angles
  let F0 = 0.02;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  
  // Flow thickness based on velocity magnitude and pressure
  // High velocity = thicker liquid layer
  let flowThickness = flowMagnitude * 0.5 + pressure * 0.3 + 0.1;
  
  // Beer-Lambert absorption
  let effectiveDepth = flowThickness * (1.0 + turbidity * 3.0);
  let absorption = exp(-effectiveDepth * 1.5);
  
  // Base alpha: more transparent when flow is slow
  let baseAlpha = mix(0.4, 0.9, absorption);
  
  // Fresnel reduces transmission
  let alpha = baseAlpha * (1.0 - fresnel * 0.4);
  
  return clamp(alpha, 0.0, 1.0);
}

// Calculate flow color with absorption
fn calculateFlowColor(
    baseColor: vec3<f32>,
    velocity: vec2<f32>,
    pressure: f32,
    turbidity: f32
) -> vec3<f32> {
  let velMag = length(velocity);
  
  // Wavelength-dependent absorption (motion blur effect)
  let flowDepth = velMag * 0.3 + pressure * 0.2;
  let absorptionR = exp(-flowDepth * (1.0 + turbidity));
  let absorptionG = exp(-flowDepth * (0.9 + turbidity * 0.9));
  let absorptionB = exp(-flowDepth * (0.8 + turbidity * 0.8));
  
  // Add subtle flow tint (cyan/blue for liquid feel)
  let flowTint = vec3<f32>(0.0, 0.05, 0.1) * velMag * 2.0;
  
  return vec3<f32>(
      baseColor.r * absorptionR,
      baseColor.g * absorptionG + flowTint.g,
      baseColor.b * absorptionB + flowTint.b
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let texSize = vec2<i32>(i32(resolution.x), i32(resolution.y));
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    // Normalized coordinates
    let uv = vec2<f32>(global_id.xy) / resolution;
    let texel = 1.0 / resolution;

    // Parameters
    let viscosity = max(u.zoom_params.x * 0.01, 0.0001);        // Viscosity (0-1 → 0-0.01)
    let pressureIters = clamp(u.zoom_params.y * 20.0, 2.0, 20.0); // Iterations (2-20)
    let flowSpeed = u.zoom_params.z * 2.0;                       // Flow speed multiplier
    let turbidity = u.zoom_params.w;                            // Turbidity for alpha

    // Mouse interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let prevMouse = vec2<f32>(
        textureLoad(dataTextureC, vec2<i32>(0, 0), 0).b,
        textureLoad(dataTextureC, vec2<i32>(0, 0), 0).a
    );

    // ═════════════════════════════════════════════════════════════════════════
    // 1. READ PREVIOUS VELOCITY FIELD from dataTextureC
    // ═════════════════════════════════════════════════════════════════════════
    let centerVel = textureLoad(dataTextureC, coord, 0);
    var velocity = centerVel.rg * 2.0 - 1.0;  // Decode from [0,1] to [-1,1]
    var pressure = centerVel.b;

    // Neighbor sampling for derivatives
    let leftCoord = clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), texSize - 1);
    let rightCoord = clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), texSize - 1);
    let downCoord = clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), texSize - 1);
    let upCoord = clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), texSize - 1);

    let leftVel = textureLoad(dataTextureC, leftCoord, 0).rg * 2.0 - 1.0;
    let rightVel = textureLoad(dataTextureC, rightCoord, 0).rg * 2.0 - 1.0;
    let downVel = textureLoad(dataTextureC, downCoord, 0).rg * 2.0 - 1.0;
    let upVel = textureLoad(dataTextureC, upCoord, 0).rg * 2.0 - 1.0;

    // ═════════════════════════════════════════════════════════════════════════
    // 2. ADVECTION (Semi-Lagrangian)
    // Trace backward along velocity field and sample velocity at that point
    // v(x, t+dt) = v(x - dt * v(x), t)
    // ═════════════════════════════════════════════════════════════════════════
    let dt = DT * flowSpeed;
    let backPos = uv - velocity * dt;
    
    // Bilinear sample of velocity at back-traced position
    let sampleCoord = backPos * resolution;
    let fcoord = fract(sampleCoord);
    let icoord = vec2<i32>(floor(sampleCoord));
    
    let s00 = textureLoad(dataTextureC, clamp(icoord + vec2<i32>(0, 0), vec2<i32>(0), texSize - 1), 0).rg * 2.0 - 1.0;
    let s10 = textureLoad(dataTextureC, clamp(icoord + vec2<i32>(1, 0), vec2<i32>(0), texSize - 1), 0).rg * 2.0 - 1.0;
    let s01 = textureLoad(dataTextureC, clamp(icoord + vec2<i32>(0, 1), vec2<i32>(0), texSize - 1), 0).rg * 2.0 - 1.0;
    let s11 = textureLoad(dataTextureC, clamp(icoord + vec2<i32>(1, 1), vec2<i32>(0), texSize - 1), 0).rg * 2.0 - 1.0;
    
    velocity = mix(mix(s00, s10, fcoord.x), mix(s01, s11, fcoord.x), fcoord.y);

    // ═════════════════════════════════════════════════════════════════════════
    // 3. MOUSE INTERACTION - Inject velocity at mouse position
    // ═════════════════════════════════════════════════════════════════════════
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let mouseRadius = 0.15;
    
    if (dist < mouseRadius) {
        let mouseForce = smoothstep(mouseRadius, 0.0, dist);
        
        // Calculate mouse velocity for dragging effect
        var mouseDelta = mouse - prevMouse;
        // Handle wrap-around cases
        if (abs(mouseDelta.x) > 0.5) { mouseDelta.x = 0.0; }
        if (abs(mouseDelta.y) > 0.5) { mouseDelta.y = 0.0; }
        mouseDelta = mouseDelta * 30.0; // Scale to reasonable velocity
        
        if (mouseDown) {
            // Dragging creates strong directional flow
            velocity = velocity + mouseDelta * mouseForce * 2.0;
        } else {
            // Hover creates gentle outward flow
            let outward = normalize(distVec) * 0.5;
            velocity = velocity + outward * mouseForce * 0.3;
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 4. VISCOSITY (Laplacian smoothing)
    // ν∇²v - diffusion of velocity
    // ═════════════════════════════════════════════════════════════════════════
    let laplacian = leftVel + rightVel + upVel + downVel - 4.0 * velocity;
    velocity = velocity + laplacian * viscosity;

    // ═════════════════════════════════════════════════════════════════════════
    // 5. TURBULENCE INJECTION (procedural noise)
    // Add some swirling motion for visual interest
    // ═════════════════════════════════════════════════════════════════════════
    let time = u.config.x;
    let noisePos = uv * 3.0 + time * 0.1;
    let curlNoise = vec2<f32>(
        sin(noisePos.y * 6.28 + time) * cos(noisePos.x * 4.28),
        -cos(noisePos.x * 6.28 + time * 0.7) * sin(noisePos.y * 4.28)
    );
    velocity = velocity + curlNoise * turbidity * 0.002;

    // ═════════════════════════════════════════════════════════════════════════
    // 6. PRESSURE PROJECTION (Simplified)
    // Ensure divergence-free velocity field: ∇·v = 0
    // ═════════════════════════════════════════════════════════════════════════
    
    // Compute divergence: ∇·v = ∂u/∂x + ∂v/∂y
    let divergence = (rightVel.x - leftVel.x) * 0.5 + (upVel.y - downVel.y) * 0.5;
    
    // Jacobi iteration for pressure
    // ∇²p = ∇·v
    pressure = 0.0;
    let leftP = textureLoad(dataTextureC, leftCoord, 0).b;
    let rightP = textureLoad(dataTextureC, rightCoord, 0).b;
    let downP = textureLoad(dataTextureC, downCoord, 0).b;
    let upP = textureLoad(dataTextureC, upCoord, 0).b;
    pressure = (leftP + rightP + downP + upP - divergence) * PRESSURE_ALPHA;
    
    // Additional iterations for better incompressibility
    for (var i: i32 = 1; i < i32(pressureIters); i = i + 1) {
        let pLeft = textureLoad(dataTextureC, leftCoord, 0).b;
        let pRight = textureLoad(dataTextureC, rightCoord, 0).b;
        let pDown = textureLoad(dataTextureC, downCoord, 0).b;
        let pUp = textureLoad(dataTextureC, upCoord, 0).b;
        pressure = (pLeft + pRight + pDown + pUp - divergence) * PRESSURE_ALPHA;
    }

    // Subtract pressure gradient from velocity: v' = v - ∇p
    let pressureGrad = vec2<f32>(
        (rightP - leftP) * 0.5,
        (upP - downP) * 0.5
    );
    velocity = velocity - pressureGrad;

    // Apply dissipation for stability
    velocity = velocity * DISSIPATION;

    // Clamp velocity to prevent explosion
    velocity = clamp(velocity, vec2<f32>(-5.0), vec2<f32>(5.0));

    // ═════════════════════════════════════════════════════════════════════════
    // 7. STORE UPDATED VELOCITY/PRESSURE FIELD
    // ═════════════════════════════════════════════════════════════════════════
    let encodedVel = (velocity * 0.5 + 0.5);  // Encode to [0,1]
    textureStore(dataTextureA, coord, vec4<f32>(encodedVel, pressure, 1.0));

    // ═════════════════════════════════════════════════════════════════════════
    // 8. STORE MOUSE POSITION for next frame (at pixel 0,0)
    // ═════════════════════════════════════════════════════════════════════════
    if (coord.x == 0 && coord.y == 0) {
        textureStore(dataTextureA, coord, vec4<f32>(encodedVel, mouse.x, mouse.y));
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 9. APPLY VELOCITY TO DISTORT IMAGE with ALPHA PHYSICS
    // ═════════════════════════════════════════════════════════════════════════
    // Scale displacement for visual effect
    let displacementStrength = 0.02 + u.zoom_params.x * 0.03;
    let displacedUV = uv - velocity * displacementStrength;
    
    // Clamp UV to prevent sampling outside texture
    let clampedUV = clamp(displacedUV, vec2<f32>(0.001), vec2<f32>(0.999));
    
    // Sample color with slight chromatic aberration based on velocity magnitude
    let velMag = length(velocity);
    let chromaticOffset = velMag * 0.002 * u.zoom_params.z;
    
    let r = textureSampleLevel(readTexture, u_sampler, clampedUV + vec2<f32>(chromaticOffset, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clampedUV - vec2<f32>(chromaticOffset, 0.0), 0.0).b;
    let baseColor = vec3<f32>(r, g, b);

    // ═════════════════════════════════════════════════════════════════════════
    // 10. ALPHA CALCULATION based on flow physics
    // ═════════════════════════════════════════════════════════════════════════
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampedUV, 0.0).r;
    
    // Calculate approximate normal from velocity gradient
    let velNormal = normalize(vec3<f32>(-velocity.x, -velocity.y, 0.5));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let viewDotNormal = dot(viewDir, velNormal);
    
    // Calculate flow color with absorption
    let flowColor = calculateFlowColor(baseColor, velocity, pressure, turbidity);
    
    // Calculate alpha
    let alpha = calculateFlowAlpha(velMag, pressure, turbidity, viewDotNormal);

    // ═════════════════════════════════════════════════════════════════════════
    // OUTPUT with ALPHA
    // ═════════════════════════════════════════════════════════════════════════
    textureStore(writeTexture, coord, vec4<f32>(flowColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
