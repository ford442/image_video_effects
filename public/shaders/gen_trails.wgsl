// ═══════════════════════════════════════════════════════════════
//  Boids Flocking Algorithm - Swarm Intelligence Shader
//  Based on Craig Reynolds' Boids (1986)
//  
//  Scientific Rules:
//  1. Separation: Avoid crowding neighbors (short-range repulsion)
//  2. Alignment: Steer towards average heading of neighbors
//  3. Cohesion: Steer towards average position of neighbors
//  
//  Implementation: GPU-based particle system with emergent flocking
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,         // x=Separation, y=Alignment, z=Cohesion, w=MaxSpeed
  ripples: array<vec4<f32>, 50>,
};

// Pseudo-random number generation
fn hash2(p: vec2<f32>) -> vec2<f32> {
    let r = vec2<f32>(
        fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453),
        fract(sin(dot(p + 0.5, vec2<f32>(93.9898, 67.345))) * 23421.631)
    );
    return r;
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    let r = vec3<f32>(
        fract(sin(dot(p.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453),
        fract(sin(dot(p.yz + 0.5, vec2<f32>(93.9898, 67.345))) * 23421.631),
        fract(sin(dot(p.zx + 1.0, vec2<f32>(43.212, 12.123))) * 54235.231)
    );
    return r;
}

// Generate boid position from particle ID and time
fn getBoidPosition(id: u32, time: f32) -> vec2<f32> {
    let idf = f32(id);
    let seed = vec3<f32>(idf * 0.1, time * 0.01, idf * 0.01);
    let h = hash3(seed);
    return h.xy * 2.0 - 1.0; // Range: -1 to 1
}

// Generate boid velocity from particle ID and time
fn getBoidVelocity(id: u32, time: f32) -> vec2<f32> {
    let idf = f32(id);
    let seed = vec3<f32>(idf * 0.2 + 100.0, time * 0.02, idf * 0.05);
    let h = hash3(seed);
    let angle = h.x * 6.28318530718; // 0 to 2π
    return vec2<f32>(cos(angle), sin(angle)) * (0.3 + h.y * 0.5);
}

// Get boid color based on flock ID
fn getBoidColor(id: u32, time: f32) -> vec3<f32> {
    let flockId = id / 30u; // Groups of 30 boids
    let flockCount = 6u;
    let hue = (f32(flockId % flockCount) / f32(flockCount)) + time * 0.05;
    
    // HSV to RGB conversion
    let c = vec3<f32>(
        fract(hue) * 6.0,
        1.0,
        1.0
    );
    let i = vec3<i32>(vec3<f32>(c.x, c.x, c.x));
    let f = c.x - f32(i.x);
    let p = c.z * (1.0 - c.y);
    let q = c.z * (1.0 - f * c.y);
    let t = c.z * (1.0 - (1.0 - f) * c.y);
    
    if (i.x % 6 == 0) { return vec3<f32>(c.z, t, p); }
    if (i.x % 6 == 1) { return vec3<f32>(q, c.z, p); }
    if (i.x % 6 == 2) { return vec3<f32>(p, c.z, t); }
    if (i.x % 6 == 3) { return vec3<f32>(p, q, c.z); }
    if (i.x % 6 == 4) { return vec3<f32>(t, p, c.z); }
    return vec3<f32>(c.z, p, q);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let px = vec2<i32>(global_id.xy);
    let time = u.config.x;
    
    // Aspect ratio correction
    let aspect = resolution.x / resolution.y;
    var screenUV = uv * 2.0 - 1.0;
    screenUV.x *= aspect;
    
    // Mouse position (as attractor/goal)
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    mouse.x *= aspect;
    let mouseActive = length(u.zoom_config.yz) > 0.001;
    
    // Get boid weights from zoom_params
    let separationWeight = u.zoom_params.x * 2.0;      // Default: 1.0
    let alignmentWeight = u.zoom_params.y * 1.5;       // Default: 1.0
    let cohesionWeight = u.zoom_params.z * 1.0;        // Default: 1.0
    let maxSpeed = 0.5 + u.zoom_params.w * 1.5;        // Default: 1.0
    
    // Simulation parameters
    let neighborRadius = 0.25;
    let separationRadius = 0.08;
    let numBoids = 180u; // Total number of boids
    
    // Read history (trails)
    let history = textureLoad(dataTextureC, px, 0);
    
    // Accumulate color from all boids
    var finalColor = vec3<f32>(0.0);
    var totalInfluence = 0.0;
    
    // Process each boid
    for (var i: u32 = 0u; i < numBoids; i = i + 1u) {
        // Get boid state
        var boidPos = getBoidPosition(i, time);
        var boidVel = getBoidVelocity(i, time);
        let boidColor = getBoidColor(i, time);
        
        // === BOIDS FLOCKING RULES ===
        
        var separation = vec2<f32>(0.0);
        var alignment = vec2<f32>(0.0);
        var cohesion = vec2<f32>(0.0);
        var neighborCount: u32 = 0u;
        var separationCount: u32 = 0u;
        
        // Sample neighbors (simplified for GPU - use deterministic pseudo-neighbors)
        for (var j: u32 = 0u; j < numBoids; j = j + 1u) {
            if (i == j) { continue; }
            
            let neighborPos = getBoidPosition(j, time);
            let neighborVel = getBoidVelocity(j, time);
            
            let diff = boidPos - neighborPos;
            let dist = length(diff);
            
            // Separation: avoid close neighbors
            if (dist < separationRadius && dist > 0.001) {
                separation = separation + normalize(diff) / dist;
                separationCount = separationCount + 1u;
            }
            
            // Alignment & Cohesion: match neighbors within radius
            if (dist < neighborRadius) {
                alignment = alignment + neighborVel;
                cohesion = cohesion + neighborPos;
                neighborCount = neighborCount + 1u;
            }
        }
        
        // Apply rules if we have neighbors
        if (separationCount > 0u) {
            separation = separation / f32(separationCount);
        }
        
        if (neighborCount > 0u) {
            alignment = alignment / f32(neighborCount);
            cohesion = (cohesion / f32(neighborCount)) - boidPos;
        }
        
        // Normalize and weight the forces
        if (length(separation) > 0.0) {
            separation = normalize(separation) * separationWeight;
        }
        if (length(alignment) > 0.0) {
            alignment = normalize(alignment - boidVel) * alignmentWeight;
        }
        if (length(cohesion) > 0.0) {
            cohesion = normalize(cohesion) * cohesionWeight;
        }
        
        // Mouse attraction (when active)
        var mouseForce = vec2<f32>(0.0);
        if (mouseActive) {
            let toMouse = mouse - boidPos;
            let distToMouse = length(toMouse);
            if (distToMouse > 0.01) {
                mouseForce = normalize(toMouse) * 0.5;
            }
        }
        
        // Combine forces
        boidVel = boidVel + separation + alignment + cohesion + mouseForce;
        
        // Limit speed
        let speed = length(boidVel);
        if (speed > maxSpeed) {
            boidVel = normalize(boidVel) * maxSpeed;
        }
        
        // Update position
        boidPos = boidPos + boidVel * 0.016; // ~60fps delta
        
        // Wrap around screen edges
        if (boidPos.x > aspect) { boidPos.x = -aspect; }
        if (boidPos.x < -aspect) { boidPos.x = aspect; }
        if (boidPos.y > 1.0) { boidPos.y = -1.0; }
        if (boidPos.y < -1.0) { boidPos.y = 1.0; }
        
        // === RENDER BOID ===
        
        // Calculate distance from this pixel to boid
        let pixelToBoid = screenUV - boidPos;
        let dist = length(pixelToBoid);
        
        // Boid body (glowing particle)
        let boidSize = 0.015;
        let bodyIntensity = exp(-dist * dist / (boidSize * boidSize));
        
        // Trail (elongated in direction of velocity)
        let velNorm = normalize(boidVel);
        let trailDir = -velNorm;
        let trailLen = 0.15 * (speed / maxSpeed);
        let alongTrail = dot(pixelToBoid, trailDir);
        let perpTrail = length(pixelToBoid - trailDir * alongTrail);
        
        // Trail shape: ellipse along velocity
        var trailIntensity = 0.0;
        if (alongTrail > 0.0 && alongTrail < trailLen) {
            let t = alongTrail / trailLen;
            let trailWidth = boidSize * (1.0 - t * 0.8);
            trailIntensity = (1.0 - t * t) * exp(-perpTrail * perpTrail / (trailWidth * trailWidth));
        }
        
        // Wing shape (for visual variety)
        let perpVel = vec2<f32>(-velNorm.y, velNorm.x);
        let wingOffset = abs(dot(pixelToBoid, perpVel));
        let wingShape = 1.0 - smoothstep(0.0, boidSize * 2.0, wingOffset);
        let headDist = length(pixelToBoid - velNorm * boidSize * 0.5);
        let wingIntensity = wingShape * (1.0 - smoothstep(0.0, boidSize, headDist)) * 0.5;
        
        // Combine body + trail + wing
        let totalIntensity = bodyIntensity * 1.5 + trailIntensity * 0.7 + wingIntensity * 0.3;
        
        // Add to final color with boid's flock color
        finalColor = finalColor + boidColor * totalIntensity;
        totalInfluence = totalInfluence + totalIntensity;
    }
    
    // Tone down accumulated brightness
    finalColor = finalColor / (1.0 + totalInfluence * 0.3);
    
    // Add subtle background pulse
    let bgPulse = 0.05 + 0.02 * sin(time * 0.5);
    finalColor = finalColor + vec3<f32>(bgPulse * 0.1, bgPulse * 0.15, bgPulse * 0.2);
    
    // Blend with history (motion trails effect)
    let trailDecay = 0.92;
    var newColor = history.rgb * trailDecay + finalColor * 0.3;
    
    // Boost brightness when mouse is clicked (scatter effect)
    if (u.zoom_config.w > 0.5) {
        newColor = newColor * 1.3 + finalColor * 0.5;
    }
    
    // Output
    let output = vec4<f32>(clamp(newColor, vec3<f32>(0.0), vec3<f32>(2.0)), 1.0);
    
    // Write to output and history texture
    textureStore(writeTexture, px, output);
    textureStore(dataTextureA, global_id.xy, output);
}
