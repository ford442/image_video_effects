// ═══════════════════════════════════════════════════════════════════
//  Gravitational Lensing
//  Category: distortion
//  Features: advanced-hybrid, schwarzschild-metric, geodesic-raytracing
//  Complexity: Very High
//  Chunks From: black-hole.wgsl, gen_grid
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Black hole light bending with Einstein ring
//  Background stars distorted around black hole, glowing accretion disk
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

const MAX_STEPS: i32 = 128;
const MAX_DIST: f32 = 50.0;
const DT: f32 = 0.05;

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ SCHWARZSCHILD METRIC ═══
fn schwarzschildFactor(r: f32, mass: f32) -> f32 {
    // Time dilation/length contraction factor: sqrt(1 - rs/r)
    let rs = 2.0 * mass; // Schwarzschild radius
    return sqrt(max(0.001, 1.0 - rs / max(r, rs * 1.01)));
}

// ═══ ACCRETION DISK ═══
fn renderAccretionDisk(rayPos: vec3<f32>, rayDir: vec3<f32>, blackHolePos: vec3<f32>, mass: f32) -> vec3<f32> {
    let rs = 2.0 * mass;
    let innerRadius = rs * 3.0;
    let outerRadius = rs * 15.0;
    
    // Intersect with disk plane (xy plane around black hole)
    let toCenter = blackHolePos - rayPos;
    let t = toCenter.y / rayDir.y;
    
    if (t > 0.0) {
        let hitPos = rayPos + rayDir * t;
        let distFromCenter = length(hitPos.xz - blackHolePos.xz);
        
        if (distFromCenter > innerRadius && distFromCenter < outerRadius) {
            // Temperature gradient (hotter closer to black hole)
            let temp = 1.0 - (distFromCenter - innerRadius) / (outerRadius - innerRadius);
            
            // Doppler beaming (approaching side is brighter/bluer)
            let orbitalVel = normalize(vec3<f32>(-(hitPos.z - blackHolePos.z), 0.0, hitPos.x - blackHolePos.x));
            let doppler = dot(rayDir, orbitalVel);
            let beaming = pow(1.0 + doppler, 3.0);
            
            // Disk color based on temperature
            var color = vec3<f32>(0.0);
            if (temp > 0.8) {
                color = vec3<f32>(1.0, 0.9, 0.7); // White hot
            } else if (temp > 0.5) {
                color = vec3<f32>(1.0, 0.5, 0.2); // Orange
            } else {
                color = vec3<f32>(0.8, 0.2, 0.1); // Red
            }
            
            // Apply beaming
            color = color * beaming * temp * temp;
            
            return color * smoothstep(outerRadius, innerRadius, distFromCenter);
        }
    }
    
    return vec3<f32>(0.0);
}

// ═══ GRAVITATIONAL REDSHIFT ═══
fn gravitationalRedshift(r: f32, mass: f32) -> vec3<f32> {
    let rs = 2.0 * mass;
    let factor = sqrt(max(0.001, 1.0 - rs / max(r, rs)));
    // Redshift: photons lose energy climbing out of gravity well
    let redshift = vec3<f32>(1.0, factor, factor * 0.8);
    return redshift;
}

// ═══ MAIN RAYTRACING ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = (vec2<f32>(global_id.xy) / resolution - 0.5) * 2.0;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let blackHoleMass = mix(1.0, 5.0, u.zoom_params.x);    // x: Black hole mass
    let diskBrightness = mix(0.5, 3.0, u.zoom_params.y);   // y: Accretion brightness
    let cameraOrbit = u.zoom_params.z * 6.28;              // z: Camera orbit
    let redshiftIntensity = u.zoom_params.w;               // w: Redshift intensity
    
    // Black hole position
    let blackHolePos = vec3<f32>(0.0, 0.0, 0.0);
    let rs = 2.0 * blackHoleMass; // Schwarzschild radius
    let eventHorizon = rs * 1.05;
    
    // Camera setup
    let camDist = 20.0;
    let camAngle = time * 0.1 * audioReactivity + cameraOrbit;
    let ro = vec3<f32>(cos(camAngle) * camDist, sin(camAngle * 0.3) * 5.0, sin(camAngle) * camDist);
    
    // Ray direction
    let forward = normalize(blackHolePos - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);
    let rd = normalize(forward + right * uv.x * aspect * 0.5 + up * uv.y * 0.5);
    
    // Raytrace through Schwarzschild metric
    var rayPos = ro;
    var rayDir = rd;
    var color = vec3<f32>(0.0);
    var depth = 1.0;
    
    for (var i = 0; i < MAX_STEPS; i++) {
        let toCenter = rayPos - blackHolePos;
        let r = length(toCenter);
        
        // Check for event horizon crossing
        if (r < eventHorizon) {
            color = vec3<f32>(0.0); // Black hole is black
            depth = 0.0;
            break;
        }
        
        // Check for escape (far enough from black hole)
        if (r > MAX_DIST) {
            // Sample background skybox (using input image as background)
            let bgUV = vec2<f32>(atan2(rayDir.z, rayDir.x) / 6.28 + 0.5, rayDir.y * 0.5 + 0.5);
            color = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb;
            
            // Apply gravitational redshift
            let redshift = gravitationalRedshift(r, blackHoleMass);
            color = color * mix(vec3<f32>(1.0), redshift, redshiftIntensity);
            
            depth = 0.5 + r / MAX_DIST * 0.5;
            break;
        }
        
        // Geodesic equation approximation
        // Ray bending: acceleration toward black hole
        let accel = -normalize(toCenter) * blackHoleMass / (r * r);
        
        // Update ray direction
        rayDir = normalize(rayDir + accel * DT);
        
        // Step forward
        rayPos += rayDir * DT * r * 0.5; // Adaptive step size
    }
    
    // Add accretion disk
    let diskColor = renderAccretionDisk(ro, rd, blackHolePos, blackHoleMass) * diskBrightness;
    
    // Check if ray hit disk before black hole
    color = color + diskColor;
    
    // Einstein ring glow
    let closestApproach = length(ro - blackHolePos);
    let einsteinRadius = sqrt(rs * closestApproach);
    let toCenter = length(uv);
    let ringGlow = smoothstep(0.5, 0.0, abs(toCenter - 0.3)) * 0.5;
    color += vec3<f32>(0.9, 0.8, 0.6) * ringGlow;
    
    let alpha = mix(0.9, 1.0, diskBrightness * 0.3);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
