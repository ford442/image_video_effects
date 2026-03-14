// ═══════════════════════════════════════════════════════════════
//  Lorenz Strange Attractor - Chaotic particle system visualization
//  Category: generative
//  Features: procedural, mathematical-art, particles
//  Scientific: Lorenz system - classic chaotic attractor
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,         // x=sigma, y=rho, z=beta, w=particleCount
  ripples: array<vec4<f32>, 50>,
};

// Hash function for pseudo-random numbers
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

// Lorenz system derivative
fn lorenzDerivative(pos: vec3<f32>, sigma: f32, rho: f32, beta: f32) -> vec3<f32> {
    let dx = sigma * (pos.y - pos.x);
    let dy = pos.x * (rho - pos.z) - pos.y;
    let dz = pos.x * pos.y - beta * pos.z;
    return vec3<f32>(dx, dy, dz);
}

// 4th order Runge-Kutta integration step
fn rk4Step(pos: vec3<f32>, dt: f32, sigma: f32, rho: f32, beta: f32) -> vec3<f32> {
    let k1 = lorenzDerivative(pos, sigma, rho, beta);
    let k2 = lorenzDerivative(pos + k1 * dt * 0.5, sigma, rho, beta);
    let k3 = lorenzDerivative(pos + k2 * dt * 0.5, sigma, rho, beta);
    let k4 = lorenzDerivative(pos + k3 * dt, sigma, rho, beta);
    return pos + (k1 + 2.0 * k2 + 2.0 * k3 + k4) * dt / 6.0;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Aspect ratio correction
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;
    
    // Lorenz parameters from sliders (with defaults)
    let sigma = mix(5.0, 20.0, u.zoom_params.x);  // σ: Prandtl number
    let rho = mix(10.0, 45.0, u.zoom_params.y);   // ρ: Rayleigh number
    let beta = mix(1.0, 5.0, u.zoom_params.z);    // β: geometric factor
    let particleCount = i32(mix(500.0, 3000.0, u.zoom_params.w));
    
    // Background - deep space
    var color = vec3<f32>(0.02, 0.02, 0.04);
    
    // View parameters
    let rotSpeed = time * 0.15;
    let camDist = 35.0;
    
    // Camera rotation matrix
    let cosY = cos(rotSpeed);
    let sinY = sin(rotSpeed);
    let cosX = cos(0.3);
    let sinX = sin(0.3);
    
    // Accumulate particle trails
    var accumColor = vec3<f32>(0.0);
    var maxDepth = 0.0;
    
    // Number of particle streams seeded differently
    let streamCount = 8;
    let stepsPerStream = 400;
    
    for (var s = 0; s < streamCount; s = s + 1) {
        // Seed each stream with different initial conditions
        let seed = hash3(vec3<f32>(f32(s) * 12.34, time * 0.1, 0.0));
        var pos = vec3<f32>(
            seed.x * 2.0 - 1.0,
            seed.y * 2.0 - 1.0,
            25.0 + seed.z * 10.0
        );
        
        // Small time offset for each stream creates flowing effect
        let timeOffset = f32(s) * 0.5 + time * 0.2;
        
        // Pre-warm the simulation to get into attractor
        var warmup = 0;
        var tempPos = pos;
        while (warmup < 500) {
            tempPos = rk4Step(tempPos, 0.005, sigma, rho, beta);
            warmup = warmup + 1;
        }
        pos = tempPos;
        
        // Generate trail points
        var prevScreenPos = vec2<f32>(-1000.0);
        var prevVel = 0.0;
        
        for (var i = 0; i < stepsPerStream; i = i + 1) {
            // Store position before stepping
            let currentPos = pos;
            
            // Step the Lorenz system
            pos = rk4Step(pos, 0.008, sigma, rho, beta);
            
            // Calculate velocity for coloring
            let vel = length(pos - currentPos);
            let avgVel = (vel + prevVel) * 0.5;
            prevVel = vel;
            
            // 3D rotation to camera space
            // Rotate around Y axis
            var rotated = vec3<f32>(
                currentPos.x * cosY - currentPos.z * sinY,
                currentPos.y,
                currentPos.x * sinY + currentPos.z * cosY
            );
            
            // Rotate around X axis (tilt)
            rotated = vec3<f32>(
                rotated.x,
                rotated.y * cosX - rotated.z * sinX,
                rotated.y * sinX + rotated.z * cosX
            );
            
            // Perspective projection
            let z = rotated.z + camDist;
            if (z > 0.1) {
                let scale = 15.0 / z;
                let screenPos = vec2<f32>(
                    rotated.x * scale * 0.0015,
                    rotated.y * scale * 0.0015
                );
                
                // Distance from current pixel to particle
                let dist = length(p - screenPos);
                
                // Depth-based size and opacity
                let depth = 1.0 - (z / 60.0); // 0 = far, 1 = near
                maxDepth = max(maxDepth, depth);
                
                // Particle size varies with depth and velocity
                let particleSize = (0.003 + avgVel * 0.5) * (0.5 + depth * 0.5);
                
                // Glow contribution
                let glow = particleSize / (dist * dist + 0.0001);
                
                // Color based on velocity and position in attractor
                // High velocity = warmer colors (red/orange)
                // Low velocity = cooler colors (blue/purple)
                let speedNorm = clamp(avgVel * 50.0, 0.0, 1.0);
                let hue = f32(s) * 0.125 + speedNorm * 0.3 + time * 0.05;
                
                // HSV to RGB conversion
                let h = fract(hue) * 6.0;
                let c = 1.0;
                let x = c * (1.0 - abs(f32(h % 2.0) - 1.0));
                var rgb = vec3<f32>(0.0);
                if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
                else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
                else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
                else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
                else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
                else { rgb = vec3<f32>(c, 0.0, x); }
                
                // Fade based on trail position
                let trailFade = 1.0 - f32(i) / f32(stepsPerStream);
                
                // Accumulate with additive blending
                accumColor += rgb * glow * trailFade * depth * 0.3;
                
                // Connect points with line for smoother trails
                if (prevScreenPos.x > -100.0) {
                    let lineDist = abs(dist - length(p - prevScreenPos));
                    let lineGlow = 0.0005 / (lineDist * lineDist + 0.00001);
                    accumColor += rgb * lineGlow * trailFade * depth * 0.1;
                }
                
                prevScreenPos = screenPos;
            }
        }
    }
    
    // Add "butterfly wing" highlights - two main lobes of attractor
    // This creates a more defined structure
    let wingGlow1 = 0.002 / (length(p - vec2<f32>(-0.15, 0.05)) + 0.03);
    let wingGlow2 = 0.002 / (length(p - vec2<f32>(0.15, -0.05)) + 0.03);
    accumColor += vec3<f32>(0.8, 0.3, 0.9) * wingGlow1 * 0.2;
    accumColor += vec3<f32>(0.3, 0.7, 0.9) * wingGlow2 * 0.2;
    
    // Tone mapping and color grading
    color = color + accumColor;
    
    // Soft contrast enhancement
    color = color / (1.0 + color * 0.5);
    
    // Subtle vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    color *= vignette;
    
    // Output final color
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    
    // Output depth for potential post-processing
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(maxDepth, 0.0, 0.0, 0.0));
}
