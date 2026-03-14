// ═══════════════════════════════════════════════════════════════════════════════
//  Navier-Stokes Fluid Displacement
//  Category: liquid-effects
//  Features: mouse-driven, multi-pass, depth-aware
//
//  Implements simplified Navier-Stokes equations for incompressible flow:
//  - ∂v/∂t = -(v·∇)v - ∇p + ν∇²v + f
//  - ∇·v = 0 (incompressibility via pressure projection)
//
//  Velocity field stored in dataTextureA (RG channels)
//  Pressure field stored in dataTextureA (B channel)
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
  zoom_params: vec4<f32>,         // viscosity, pressure_iterations, flow_speed, turbulence
  ripples: array<vec4<f32>, 50>,
};

// Constants
const DT: f32 = 0.016;              // Time step (60fps)
const DISSIPATION: f32 = 0.995;      // Velocity decay
const PRESSURE_ALPHA: f32 = 0.25;    // Jacobi relaxation factor

@compute @workgroup_size(8, 8, 1)
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
    let turbulence = u.zoom_params.w;                            // Turbulence injection

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
    velocity = velocity + curlNoise * turbulence * 0.002;

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
    // 9. APPLY VELOCITY TO DISTORT IMAGE
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

    // ═════════════════════════════════════════════════════════════════════════
    // 10. DEPTH HANDLING
    // ═════════════════════════════════════════════════════════════════════════
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampedUV, 0.0).r;

    // ═════════════════════════════════════════════════════════════════════════
    // OUTPUT
    // ═════════════════════════════════════════════════════════════════════════
    textureStore(writeTexture, coord, vec4<f32>(r, g, b, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
