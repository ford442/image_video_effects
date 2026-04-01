// ═══════════════════════════════════════════════════════════════════
//  Boids Flocking with Alpha Scattering
//  Craig Reynolds' Boids (1986) with physical light simulation
//  Category: generative
//  Features: upgraded-rgba, depth-aware, particles, flocking, motion-trails
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
// ═══════════════════════════════════════════════════════════════════

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

// Generate boid position
fn getBoidPosition(id: u32, time: f32) -> vec2<f32> {
    let idf = f32(id);
    let seed = vec3<f32>(idf * 0.1, time * 0.01, idf * 0.01);
    let h = hash3(seed);
    return h.xy * 2.0 - 1.0;
}

// Generate boid velocity
fn getBoidVelocity(id: u32, time: f32) -> vec2<f32> {
    let idf = f32(id);
    let seed = vec3<f32>(idf * 0.2 + 100.0, time * 0.02, idf * 0.05);
    let h = hash3(seed);
    let angle = h.x * 6.28318530718;
    return vec2<f32>(cos(angle), sin(angle)) * (0.3 + h.y * 0.5);
}

// Get boid color
fn getBoidColor(id: u32, time: f32) -> vec3<f32> {
    let flockId = id / 30u;
    let flockCount = 6u;
    let hue = (f32(flockId % flockCount) / f32(flockCount)) + time * 0.05;
    
    let c = vec3<f32>(fract(hue) * 6.0, 1.0, 1.0);
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

// Soft particle alpha
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 2.0);
}

// Exponential transmittance
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// HDR tone mapping
fn toneMap(hdr: vec3<f32>) -> vec3<f32> {
    return hdr / (1.0 + hdr);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let px = vec2<i32>(global_id.xy);
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    
    let aspect = resolution.x / resolution.y;
    var screenUV = uv * 2.0 - 1.0;
    screenUV.x *= aspect;
    
    // Mouse position
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    mouse.x *= aspect;
    let mouseActive = length(u.zoom_config.yz) > 0.001;
    
    // Parameters
    let separationWeight = u.zoom_params.x * 2.0;
    let alignmentWeight = u.zoom_params.y * 1.5;
    let cohesionWeight = u.zoom_params.z * 1.0;
    let maxSpeed = 0.5 + u.zoom_params.w * 1.5;
    
    let neighborRadius = 0.25;
    let separationRadius = 0.08;
    let numBoids = 180u;
    
    let particle_radius = 0.015;
    let particle_opacity = 0.7;
    
    // Read history
    let history = textureLoad(dataTextureC, px, 0);
    
    // Accumulate
    var accumulated_color = vec3<f32>(0.0);
    var accumulated_density: f32 = 0.0;
    var total_energy: f32 = 0.0;
    
    // Process each boid
    for (var i: u32 = 0u; i < numBoids; i = i + 1u) {
        var boidPos = getBoidPosition(i, time);
        var boidVel = getBoidVelocity(i, time);
        let boidColor = getBoidColor(i, time);
        
        // Boids rules
        var separation = vec2<f32>(0.0);
        var alignment = vec2<f32>(0.0);
        var cohesion = vec2<f32>(0.0);
        var neighborCount: u32 = 0u;
        var separationCount: u32 = 0u;
        
        for (var j: u32 = 0u; j < numBoids; j = j + 1u) {
            if (i == j) { continue; }
            let neighborPos = getBoidPosition(j, time);
            let neighborVel = getBoidVelocity(j, time);
            let diff = boidPos - neighborPos;
            let dist = length(diff);
            
            if (dist < separationRadius && dist > 0.001) {
                separation = separation + normalize(diff) / dist;
                separationCount = separationCount + 1u;
            }
            if (dist < neighborRadius) {
                alignment = alignment + neighborVel;
                cohesion = cohesion + neighborPos;
                neighborCount = neighborCount + 1u;
            }
        }
        
        if (separationCount > 0u) { separation = separation / f32(separationCount); }
        if (neighborCount > 0u) {
            alignment = alignment / f32(neighborCount);
            cohesion = (cohesion / f32(neighborCount)) - boidPos;
        }
        
        if (length(separation) > 0.0) { separation = normalize(separation) * separationWeight; }
        if (length(alignment) > 0.0) { alignment = normalize(alignment - boidVel) * alignmentWeight; }
        if (length(cohesion) > 0.0) { cohesion = normalize(cohesion) * cohesionWeight; }
        
        var mouseForce = vec2<f32>(0.0);
        if (mouseActive) {
            let toMouse = mouse - boidPos;
            let distToMouse = length(toMouse);
            if (distToMouse > 0.01) { mouseForce = normalize(toMouse) * 0.5; }
        }
        
        boidVel = boidVel + separation + alignment + cohesion + mouseForce;
        let speed = length(boidVel);
        if (speed > maxSpeed) { boidVel = normalize(boidVel) * maxSpeed; }
        boidPos = boidPos + boidVel * 0.016;
        
        // Wrap around
        if (boidPos.x > aspect) { boidPos.x = -aspect; }
        if (boidPos.x < -aspect) { boidPos.x = aspect; }
        if (boidPos.y > 1.0) { boidPos.y = -1.0; }
        if (boidPos.y < -1.0) { boidPos.y = 1.0; }
        
        // Render boid
        let pixelToBoid = screenUV - boidPos;
        let dist = length(pixelToBoid);
        let current_speed = length(boidVel);
        
        // Body
        let body_alpha = softParticleAlpha(dist, particle_radius);
        
        // Trail
        let velNorm = normalize(boidVel);
        let trailDir = -velNorm;
        let trailLen = 0.15 * (current_speed / maxSpeed);
        let alongTrail = dot(pixelToBoid, trailDir);
        let perpTrail = length(pixelToBoid - trailDir * alongTrail);
        
        var trail_alpha: f32 = 0.0;
        if (alongTrail > 0.0 && alongTrail < trailLen) {
            let t = alongTrail / trailLen;
            let trailWidth = particle_radius * (1.0 - t * 0.8);
            trail_alpha = (1.0 - t * t) * softParticleAlpha(perpTrail, trailWidth);
        }
        
        // Wing shape
        let perpVel = vec2<f32>(-velNorm.y, velNorm.x);
        let wingOffset = abs(dot(pixelToBoid, perpVel));
        let wingShape = 1.0 - smoothstep(0.0, particle_radius * 2.0, wingOffset);
        let headDist = length(pixelToBoid - velNorm * particle_radius * 0.5);
        let wing_alpha = wingShape * (1.0 - smoothstep(0.0, particle_radius, headDist)) * 0.5;
        
        let total_alpha = body_alpha * 1.5 + trail_alpha * 0.7 + wing_alpha * 0.3;
        let emission = 1.0 + current_speed * 2.0;
        let hdr_color = boidColor * emission;
        
        accumulated_color += hdr_color * total_alpha * particle_opacity;
        accumulated_density += total_alpha * particle_opacity;
        total_energy += total_alpha * emission;
    }
    
    // Tone mapping
    accumulated_color = toneMap(accumulated_color * 0.5);
    
    // Cumulative alpha
    let trans = transmittance(accumulated_density * 0.3);
    let final_alpha = 1.0 - trans;
    let energy_boost = min(total_energy * 0.01, 0.3);
    let final_alpha_boosted = min(final_alpha + energy_boost, 1.0);
    
    // Blend with history
    let trailDecay = 0.92;
    let history_contrib = history.rgb * trailDecay;
    let new_color = history_contrib + accumulated_color * 0.3;
    
    if (u.zoom_config.w > 0.5) { accumulated_color = accumulated_color * 1.3; }
    
    let output_color = mix(history_contrib, accumulated_color, final_alpha_boosted);
    let output = vec4<f32>(clamp(output_color, vec3<f32>(0.0), vec3<f32>(3.0)), final_alpha_boosted);
    
    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Opacity control for blending with input
    let opacity = 0.85;
    
    // Blend boids with input layer
    let finalColor = mix(inputColor.rgb, output_color, final_alpha_boosted * opacity);
    let finalAlpha = max(inputColor.a, final_alpha_boosted * opacity);
    let finalOutput = vec4<f32>(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(3.0)), finalAlpha);
    
    // Output RGBA with depth pass-through
    textureStore(writeTexture, coord, finalOutput);
    textureStore(writeDepthTexture, coord, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalOutput);
}
