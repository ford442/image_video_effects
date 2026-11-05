// ═══════════════════════════════════════════════════════════════════
//  Fractal Boids Field
//  Category: simulation
//  Features: advanced-hybrid, boids, fractal-flow-field, gpu-particles
//  Complexity: High
//  Chunks From: boids.wgsl, gen_grid
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
//  Upgraded: 2026-11-01
//  Ideas: true trail persistence (boid layer in A, read as C); flow-bent trails (one extra flow sample bends the 9 trail dots into an arc)
//  A packing: boid layer - A.rgb = linear boid colour / trail memory, A.a = boid density (read as C .rgb); ACES display on writeTexture
// ═══════════════════════════════════════════════════════════════════
//  Flocking behavior on a fractal vector field
//  Swarms of particles flowing through organic fractal currents
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: fbm2 ═══
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ═══ DOMAIN WARP FBM ═══
fn domainWarpFBM(p: vec2<f32>, time: f32, audioReactivity: f32) -> vec2<f32> {
    let q = vec2<f32>(
        fbm2(p + vec2<f32>(0.0, time * 0.1 * audioReactivity), 4),
        fbm2(p + vec2<f32>(5.2, 1.3 + time * 0.1 * audioReactivity), 4)
    );
    let r = vec2<f32>(
        fbm2(p + 4.0 * q + vec2<f32>(1.7 - time * 0.15 * audioReactivity, 9.2), 4),
        fbm2(p + 4.0 * q + vec2<f32>(8.3 - time * 0.15 * audioReactivity, 2.8), 4)
    );
    return r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ FLOW FIELD SAMPLE ═══
fn sampleFlowField(uv: vec2<f32>, time: f32, flowStrength: f32, audioReactivity: f32) -> vec2<f32> {
    let warped = domainWarpFBM(uv * 5.0, time * 0.1 * audioReactivity, audioReactivity);
    let angle = warped.x * 6.28 * flowStrength;
    return vec2<f32>(cos(angle), sin(angle));
}

// ═══ BOID SIMULATION ═══
fn simulateBoids(uv: vec2<f32>, time: f32, boidCount: f32, flowStrength: f32, separationDist: f32, audioReactivity: f32) -> vec3<f32> {
    var boidColor = vec3<f32>(0.0);
    let hashUV = floor(uv * boidCount) / boidCount;
    let boidId = hash12(hashUV);
    
    // Simulated boid position (in grid cell)
    var boidPos = hashUV + vec2<f32>(
        sin(time * (1.0 + boidId * 2.0) + boidId * 10.0),
        cos(time * (1.0 + boidId * 1.5) + boidId * 10.0)
    ) * 0.5 / boidCount;
    
    // Get flow field at boid position
    let flow = sampleFlowField(boidPos, time, flowStrength, audioReactivity);
    
    // Boid rules (simplified for performance)
    var separation = vec2<f32>(0.0);
    var alignment = flow;
    var cohesion = vec2<f32>(0.0);
    
    // Sample neighbors (simplified grid-based)
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            if (x == 0 && y == 0) { continue; }
            let neighborUV = hashUV + vec2<f32>(f32(x), f32(y)) / boidCount;
            let neighborId = hash12(neighborUV);
            let neighborPos = neighborUV + vec2<f32>(
                sin(time * (1.0 + neighborId * 2.0) + neighborId * 10.0),
                cos(time * (1.0 + neighborId * 1.5) + neighborId * 10.0)
            ) * 0.5 / boidCount;
            
            let diff = boidPos - neighborPos;
            let dist = length(diff);
            
            if (dist < separationDist / boidCount && dist > 0.001) {
                separation += normalize(diff) / dist;
            }
            
            cohesion += neighborPos;
        }
    }
    
    cohesion = cohesion / 8.0 - boidPos;
    
    // Combine forces
    let velocity = normalize(separation * 1.5 + alignment * 1.0 + cohesion * 0.5 + flow * 2.0);
    
    // Trail rendering
    let toBoid = uv - boidPos;
    let distToBoid = length(toBoid);
    let trailWidth = 0.003;
    
    if (distToBoid < trailWidth * (1.0 + boidId)) {
        // Boid color based on velocity direction
        let hue = atan2(velocity.y, velocity.x) / 6.28 + 0.5;
        boidColor = vec3<f32>(
            0.5 + 0.5 * cos(hue * 6.28),
            0.5 + 0.5 * cos(hue * 6.28 + 2.09),
            0.5 + 0.5 * cos(hue * 6.28 + 4.18)
        );
    }
    
    // Trail behind boid
    let trailDir = -velocity;
    // Idea 2: flow-bent trails. The field one trail-length behind the head, minus the field
    // at the head, is how much the current is turning along the wake; the 9 dots follow a
    // quadratic arc of that turning instead of a straight line (bend <= ~0.03 uv at the tail).
    let flowBehind = sampleFlowField(boidPos + trailDir * 0.09, time, flowStrength, audioReactivity);
    let trailBend = (flowBehind - flow) * 0.015;
    for (var i = 1; i < 10; i++) {
        let tTrail = f32(i) / 9.0;
        let trailPos = boidPos + trailDir * f32(i) * 0.01 + trailBend * tTrail * tTrail;
        let distToTrail = length(uv - trailPos);
        let trailIntensity = 1.0 - f32(i) / 10.0;
        if (distToTrail < trailWidth * trailIntensity) {
            let trailColor = vec3<f32>(0.8, 0.9, 1.0) * trailIntensity * 0.5;
            boidColor = max(boidColor, trailColor);
        }
    }
    
    return boidColor;
}

// ═══ MAIN ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ═══ AUDIO REACTIVITY ═══
    // HEAD read u.zoom_config.x here, which is engine TIME, not audio: the flow-field time
    // term (time * audioReactivity) therefore ran away roughly as time^2. Audio now comes from
    // plasmaBuffer and rides the flow strength (a multiplicative time scale would make the
    // field jump whenever the level changed); audioReactivity stays 1.0, HEAD's value at t = 0.
    let audioOverall = clamp((bass + mids + treble) * 0.3333333, 0.0, 2.0);
    let audioReactivity = 1.0;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let boidCount = mix(10.0, 50.0, u.zoom_params.x);      // x: Boid count (simulated)
    let flowStrength = mix(0.5, 3.0, u.zoom_params.y) * (1.0 + audioOverall * 0.2);      // y: Flow field strength
    let trailPersist = u.zoom_params.z;                      // z: Trail persistence
    let separation = mix(0.02, 0.1, u.zoom_params.w);       // w: Separation distance
    
    // Base image
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Calculate boid field
    let boidColor = simulateBoids(uv, time, boidCount, flowStrength, separation, audioReactivity);
    
    // Idea 1: true trail persistence. The boid layer is kept in A and read back as exact C;
    // the Trail Persistence slider sets the evaporation rate (0.78 .. 0.96), so a moving boid
    // leaves a lingering trail that also covers the cell-boundary clipping of the head.
    let histSize = vec2<i32>(textureDimensions(dataTextureC));
    let prevLayer = textureLoad(dataTextureC, clamp(id, vec2<i32>(0), histSize - vec2<i32>(1)), 0);
    let evaporate = mix(0.78, 0.96, trailPersist);
    let layerRgb = max(boidColor, prevLayer.rgb * evaporate);
    let layerDensity = max(clamp(length(boidColor), 0.0, 1.0), prevLayer.a * evaporate);
    textureStore(dataTextureA, id, vec4<f32>(layerRgb, layerDensity));

    // Blend with background
    color = mix(color, layerRgb, length(layerRgb) * (0.5 + trailPersist * 0.5));
    
    // Add flow field visualization
    let flow = sampleFlowField(uv, time, flowStrength * 0.5, audioReactivity);
    let flowMag = length(flow);
    color += vec3<f32>(flowMag * 0.1, flowMag * 0.05, flowMag * 0.15) * flowStrength;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.75, 1.0, clamp(length(layerRgb), 0.0, 1.0));
    
    
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let aspect = u.config.z / max(u.config.w, 1.0);
    let screenUV = vec2<f32>(id) / vec2<f32>(u.config.z, u.config.w);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((screenUV - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(screenUV - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let finalRGB = vec4<f32>(color, alpha).rgb + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, id, vec4<f32>(acesToneMap(max(finalRGB, vec3<f32>(0.0))), vec4<f32>(color, alpha).a));
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
