// ═══════════════════════════════════════════════════════════════════════════════
//  distortion_gravitational_lens.wgsl - Einstein Ring Gravitational Lensing
//  
//  Agent: Algorithmist + Visualist
//  Techniques:
//    - Schwarzschild metric ray deflection
//    - Einstein ring formation
//    - Multiple mass points (galaxy cluster)
//    - Accretion disk visualization
//  
//  Target: 4.7★ rating
// ═══════════════════════════════════════════════════════════════════════════════

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

const PI: f32 = 3.14159265359;

// Mass structure for lensing
struct Mass {
    pos: vec2<f32>,
    mass: f32,
    radius: f32, // Schwarzschild radius proxy
};

// Gravitational deflection angle
// Simplified Schwarzschild deflection: alpha = 4GM/(c^2 * b)
// where b is impact parameter
fn deflectionAngle(rayPos: vec2<f32>, mass: Mass) -> vec2<f32> {
    let delta = rayPos - mass.pos;
    let dist2 = dot(delta, delta);
    let dist = sqrt(dist2);
    
    // Avoid singularity
    if (dist < mass.radius * 0.1) {
        return vec2<f32>(0.0);
    }
    
    // Deflection magnitude (simplified GR)
    let deflectionMagnitude = mass.mass * mass.radius / (dist + 0.001);
    
    // Direction is perpendicular to radius (toward mass)
    return -normalize(delta) * deflectionMagnitude;
}

// Accretion disk temperature coloring (blackbody)
fn accretionDiskColor(radius: f32, innerRadius: f32) -> vec3<f32> {
    // Temperature falls off as r^(-3/4) for thin disk
    let temp = pow(innerRadius / radius, 0.75);
    
    // Blackbody approximation
    var color: vec3<f32>;
    if (temp > 0.8) {
        color = vec3<f32>(1.0, 0.9, 0.8); // White-hot
    } else if (temp > 0.6) {
        color = vec3<f32>(1.0, 0.6, 0.3); // Orange
    } else if (temp > 0.4) {
        color = vec3<f32>(0.8, 0.2, 0.1); // Red
    } else {
        color = vec3<f32>(0.3, 0.05, 0.05); // Dark red
    }
    
    return color * temp * temp; // Intensity ~ T^2 (Stefan-Boltzmann-ish)
}

// Einstein ring calculation
fn einsteinRadius(mass: f32, distance: f32) -> f32 {
    return sqrt(mass) * distance * 0.1;
}

// Tone mapping
fn toneMap(x: vec3<f32>) -> vec3<f32> {
    return x / (1.0 + x * 0.5);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let lensStrength = 0.5 + u.zoom_params.x;         // 0.5-1.5
    let numMasses = i32(u.zoom_params.y * 4.0) + 1;   // 1-5
    let diskIntensity = u.zoom_params.z;              // 0-1
    let aberration = u.zoom_params.w * 0.05;          // 0-0.05 (chromatic)
    
    // Mouse position as primary mass
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Define masses
    var masses: array<Mass, 5>;
    masses[0] = Mass(mousePos, 2.0 + audioPulse * 2.0, 0.02 * lensStrength);
    
    // Additional orbiting masses
    for (var i: i32 = 1; i < 5; i = i + 1) {
        if (i < numMasses) {
            let fi = f32(i);
            let angle = time * 0.2 + fi * (2.0 * PI / f32(numMasses - 1));
            let radius = 0.2 + fi * 0.1;
            masses[i] = Mass(
                vec2<f32>(
                    mousePos.x + cos(angle) * radius,
                    mousePos.y + sin(angle) * radius
                ),
                0.5,
                0.01 * lensStrength
            );
        }
    }
    
    // Ray starting position (screen space)
    var rayPos = uv;
    
    // Accumulate deflections from all masses
    var totalDeflection = vec2<f32>(0.0);
    for (var i: i32 = 0; i < numMasses; i = i + 1) {
        totalDeflection += deflectionAngle(rayPos, masses[i]);
    }
    
    // Apply deflection to get source position
    let sourcePos = rayPos - totalDeflection * 0.5;
    
    // Chromatic aberration: different deflection per channel
    let deflectionR = totalDeflection * (1.0 + aberration);
    let deflectionB = totalDeflection * (1.0 - aberration);
    let sourcePosR = rayPos - deflectionR * 0.5;
    let sourcePosG = sourcePos;
    let sourcePosB = rayPos - deflectionB * 0.5;
    
    // Sample background with lensing
    var color = vec3<f32>(0.0);
    
    // Check if source positions are in bounds
    if (all(sourcePosR >= vec2<f32>(0.0)) && all(sourcePosR <= vec2<f32>(1.0))) {
        color.r = textureSampleLevel(readTexture, u_sampler, sourcePosR, 0.0).r;
    }
    if (all(sourcePosG >= vec2<f32>(0.0)) && all(sourcePosG <= vec2<f32>(1.0))) {
        color.g = textureSampleLevel(readTexture, u_sampler, sourcePosG, 0.0).g;
    }
    if (all(sourcePosB >= vec2<f32>(0.0)) && all(sourcePosB <= vec2<f32>(1.0))) {
        color.b = textureSampleLevel(readTexture, u_sampler, sourcePosB, 0.0).b;
    }
    
    // Add accretion disk around primary mass
    let toPrimary = uv - masses[0].pos;
    let distPrimary = length(toPrimary);
    let innerDisk = masses[0].radius * 3.0;
    let outerDisk = masses[0].radius * 15.0;
    
    if (distPrimary > innerDisk && distPrimary < outerDisk) {
        let diskTemp = accretionDiskColor(distPrimary, innerDisk);
        let diskPattern = sin(atan2(toPrimary.y, toPrimary.x) * 20.0 + time * 2.0);
        let diskGlow = smoothstep(outerDisk, innerDisk, distPrimary) * 
                       (0.7 + diskPattern * 0.3);
        
        color += diskTemp * diskGlow * diskIntensity * (1.0 + audioPulse * 2.0);
    }
    
    // Einstein ring highlight
    let einsteinR = einsteinRadius(masses[0].mass, length(toPrimary));
    let ringDist = abs(distPrimary - einsteinR);
    let ringGlow = smoothstep(0.02, 0.0, ringDist) * lensStrength;
    color += vec3<f32>(0.8, 0.9, 1.0) * ringGlow * 0.5;
    
    // Gravitational redshift near mass
    let redshift = smoothstep(masses[0].radius * 10.0, masses[0].radius, distPrimary);
    color.r += color.r * redshift * 0.3;
    color.b -= color.b * redshift * 0.2;
    
    // Tone mapping
    color = toneMap(color);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    color *= vignette;
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(length(totalDeflection), 0.0, 0.0, 1.0));
}
