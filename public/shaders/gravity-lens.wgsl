// ═══════════════════════════════════════════════════════════════════════════════
//  Gravity Lens - Schwarzschild & Kerr Metric Gravitational Lensing
//  Category: distortion
//  
//  Scientific Implementation:
//  - Schwarzschild metric for non-spinning black holes
//  - Einstein ring formation when source aligns with lens
//  - Kerr metric approximation for frame-dragging effects
//  - Ray-tracing approach for realistic light bending
//
//  Parameters (zoom_params):
//    x: Mass (GM/c²) - Controls lensing strength
//    y: Einstein radius scale - Adjusts the Einstein ring size
//    z: Spin (0-1) - Kerr angular momentum parameter (frame dragging)
//    w: Accretion disk brightness
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic
  zoom_params: vec4<f32>,  // x=Mass, y=EinsteinScale, z=Spin, w=DiskBrightness
  ripples: array<vec4<f32>, 50>,
};

// Constants for physics calculations
const PI: f32 = 3.14159265359;
const SCHWARZSCHILD_FACTOR: f32 = 4.0; // 4GM/c² factor in deflection formula

// Texture sampling with bilinear interpolation for smoother results
fn sampleSmooth(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
}

// Schwarzschild lens equation: calculates deflection angle
// α = 4GM/(c² * b) where b is the impact parameter
// Returns the deflection angle in radians
fn schwarzschildDeflection(r: f32, mass: f32) -> f32 {
    // r is the distance from the lens center (impact parameter)
    // Avoid division by zero with small epsilon
    let safeR = max(r, 0.0001);
    return SCHWARZSCHILD_FACTOR * mass / safeR;
}

// Calculate Einstein radius: θ_E = √(4GM/c² * D_ls/(D_l*D_s))
// For our shader, we simplify with the mass parameter controlling this
fn einsteinRadius(mass: f32, scale: f32) -> f32 {
    return sqrt(mass * scale * 0.5);
}

// Kerr metric frame dragging effect (simplified)
// Adds azimuthal displacement based on spin parameter
fn kerrFrameDragging(
    pos: vec2<f32>,
    massCenter: vec2<f32>,
    spin: f32,
    r: f32
) -> vec2<f32> {
    if (spin < 0.001) {
        return vec2<f32>(0.0);
    }
    
    // Calculate angle from center
    let angle = atan2(pos.y - massCenter.y, pos.x - massCenter.x);
    
    // Frame dragging strength falls off as 1/r³ (simplified Kerr)
    // Innermost stable circular orbit (ISCO) effect
    let iscoRadius = 6.0 * mass * (1.0 + spin * 0.5); // Approximate ISCO
    let safeR = max(r, iscoRadius * 0.1);
    
    // Azimuthal shift proportional to spin and 1/r²
    let dragStrength = spin * 0.02 / (safeR * safeR + 0.001);
    let dragAngle = angle + dragStrength;
    
    // Convert back to offset
    let offsetR = dragStrength * r;
    return vec2<f32>(
        -offsetR * sin(angle),
        offsetR * cos(angle)
    );
}

// Ray tracing approach: trace ray backward from observer through lens
// Returns the UV coordinate in the source plane
fn traceRaySchwarzschild(
    observerUV: vec2<f32>,
    massCenter: vec2<f32>,
    mass: f32,
    aspect: f32
) -> vec2<f32> {
    // Convert to physical coordinates (account for aspect ratio)
    let obsPhys = vec2<f32>(
        (observerUV.x - massCenter.x) * aspect,
        observerUV.y - massCenter.y
    );
    
    // Distance from lens center (impact parameter)
    let r = length(obsPhys);
    let safeR = max(r, 0.0001);
    
    // Schwarzschild deflection angle
    let deflection = schwarzschildDeflection(safeR, mass);
    
    // The ray arrives at the observer from angle θ + α (deflection)
    // We need to find where it originated: θ_source = θ_observed - α
    let angle = atan2(obsPhys.y, obsPhys.x);
    let sourceAngle = angle - deflection;
    
    // The source is at the same distance r but different angle
    let sourcePhys = vec2<f32>(
        safeR * cos(sourceAngle),
        safeR * sin(sourceAngle)
    );
    
    // Convert back to UV space
    return vec2<f32>(
        massCenter.x + sourcePhys.x / aspect,
        massCenter.y + sourcePhys.y
    );
}

// Einstein ring detection and enhancement
// Returns intensity boost for the ring region
fn einsteinRingIntensity(
    uv: vec2<f32>,
    massCenter: vec2<f32>,
    mass: f32,
    scale: f32,
    aspect: f32
) -> f32 {
    // Calculate Einstein radius
    let thetaE = einsteinRadius(mass, scale);
    
    // Physical distance from center
    let dVec = vec2<f32>((uv.x - massCenter.x) * aspect, uv.y - massCenter.y);
    let r = length(dVec);
    
    // Ring forms at Einstein radius when source is directly behind lens
    let ringWidth = thetaE * 0.15;
    let distFromRing = abs(r - thetaE);
    
    // Gaussian intensity profile for the ring
    if (distFromRing < ringWidth * 2.0) {
        return exp(-distFromRing * distFromRing / (ringWidth * ringWidth)) * 0.5;
    }
    return 0.0;
}

// Generate photon ring (light orbiting the black hole)
// This creates a thin bright ring just outside the photon sphere
fn photonRingIntensity(
    uv: vec2<f32>,
    massCenter: vec2<f32>,
    mass: f32,
    aspect: f32
) -> f32 {
    // Photon sphere radius = 3GM/c² (for Schwarzschild)
    let photonSphereRadius = 3.0 * mass;
    
    let dVec = vec2<f32>((uv.x - massCenter.x) * aspect, uv.y - massCenter.y);
    let r = length(dVec);
    
    // Very thin ring with sharp falloff
    let ringWidth = mass * 0.05;
    let distFromRing = abs(r - photonSphereRadius * 0.001); // Scale for UV space
    
    if (distFromRing < ringWidth) {
        let t = distFromRing / ringWidth;
        return exp(-t * t * 8.0) * 2.0;
    }
    return 0.0;
}

// Accretion disk visualization
fn accretionDisk(
    uv: vec2<f32>,
    massCenter: vec2<f32>,
    mass: f32,
    spin: f32,
    brightness: f32,
    aspect: f32,
    time: f32
) -> vec3<f32> {
    let dVec = vec2<f32>((uv.x - massCenter.x) * aspect, uv.y - massCenter.y);
    let r = length(dVec);
    
    // Inner edge of accretion disk (ISCO - Innermost Stable Circular Orbit)
    // For Schwarzschild: 6M, for Kerr prograde: 1M (extremal)
    let iscoInner = mass * (6.0 - spin * 4.0); 
    let iscoOuter = mass * 20.0;
    
    // Scale to UV space
    let innerEdge = iscoInner * 0.001;
    let outerEdge = iscoOuter * 0.001;
    
    if (r < innerEdge || r > outerEdge) {
        return vec3<f32>(0.0);
    }
    
    // Distance from inner edge
    let t = (r - innerEdge) / (outerEdge - innerEdge);
    
    // Temperature profile: T ~ r^(-3/4) for standard disk
    let temp = pow(1.0 - t * 0.8, 2.0);
    
    // Doppler beaming effect (brighter on approaching side)
    let angle = atan2(dVec.y, dVec.x);
    let doppler = 1.0 + spin * 0.3 * sin(angle + time * 0.5);
    
    // Color based on temperature (blackbody approximation)
    // Hotter = bluer/whiter, Coolter = redder
    let hotColor = vec3<f32>(1.0, 0.9, 0.8);
    let coolColor = vec3<f32>(1.0, 0.4, 0.1);
    let diskColor = mix(coolColor, hotColor, temp);
    
    // Intensity falloff
    let intensity = temp * temp * temp * temp * brightness * doppler;
    
    // Edge falloff
    let edgeFade = smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.8, 1.0, t));
    
    return diskColor * intensity * edgeFade * 3.0;
}

// Chromatic aberration due to gravitational redshift (artistic)
fn gravitationalRedshift(uv: vec2<f32>, mass: f32, massCenter: vec2<f32>, aspect: f32) -> f32 {
    let dVec = vec2<f32>((uv.x - massCenter.x) * aspect, uv.y - massCenter.y);
    let r = length(dVec);
    // Redshift increases closer to the mass
    return 1.0 / sqrt(1.0 - mass / (r * 1000.0 + mass));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    
    // Parameters
    let mass = max(u.zoom_params.x * 0.3, 0.001); // GM/c², scaled for UV space
    let einsteinScale = u.zoom_params.y; // Einstein radius scaling
    let spin = clamp(u.zoom_params.z, 0.0, 0.99); // Kerr spin parameter
    let diskBrightness = u.zoom_params.w;
    
    // Lens center (mouse position or center of screen)
    let hasMouse = u.zoom_config.y >= 0.0 && u.zoom_config.z >= 0.0;
    var lensCenter = select(vec2<f32>(0.5, 0.5), u.zoom_config.yz, hasMouse);
    
    // Schwarzschild radius (event horizon)
    let rs = 2.0 * mass; // Schwarzschild radius
    let horizonRadius = rs * 0.001; // Scale to UV space
    
    // Distance from lens center (physical)
    let dVec = vec2<f32>((uv.x - lensCenter.x) * aspect, uv.y - lensCenter.y);
    let dist = length(dVec);
    
    var color = vec3<f32>(0.0);
    var alpha = 1.0;
    
    // Event horizon (black hole itself)
    if (dist < horizonRadius) {
        color = vec3<f32>(0.0);
        alpha = 1.0;
    } else {
        // Ray trace backward to find source position
        let sourceUV = traceRaySchwarzschild(uv, lensCenter, mass, aspect);
        
        // Apply Kerr frame dragging
        let kerrOffset = kerrFrameDragging(uv, lensCenter, spin, dist);
        let finalUV = sourceUV + kerrOffset;
        
        // Gravitational redshift factor
        let redshift = gravitationalRedshift(uv, mass, lensCenter, aspect);
        
        // Sample with chromatic aberration (gravitational dispersion)
        // Different "colors" experience slightly different effective mass
        let dispersionR = 1.0;
        let dispersionG = 0.98;
        let dispersionB = 0.96;
        
        let uvR = lensCenter + (finalUV - lensCenter) * dispersionR;
        let uvG = lensCenter + (finalUV - lensCenter) * dispersionG;
        let uvB = lensCenter + (finalUV - lensCenter) * dispersionB;
        
        let r = sampleSmooth(uvR).r;
        let g = sampleSmooth(uvG).g;
        let b = sampleSmooth(uvB).b;
        
        color = vec3<f32>(r, g, b);
        
        // Apply subtle gravitational redshift near the horizon
        let redshiftFactor = smoothstep(horizonRadius * 3.0, horizonRadius, dist);
        color.r = mix(color.r, color.r * 1.1, redshiftFactor); // Redder near horizon
        color.b = mix(color.b, color.b * 0.9, redshiftFactor); // Less blue near horizon
        
        // Einstein ring enhancement
        let ringBoost = einsteinRingIntensity(uv, lensCenter, mass, einsteinScale, aspect);
        color = color * (1.0 + ringBoost);
        
        // Photon ring (for high mass values)
        if (mass > 0.05) {
            let photonBoost = photonRingIntensity(uv, lensCenter, mass, aspect);
            let photonColor = vec3<f32>(1.0, 0.95, 0.8) * photonBoost * mass * 10.0;
            color = color + photonColor;
        }
        
        // Accretion disk
        if (diskBrightness > 0.0) {
            let diskColor = accretionDisk(uv, lensCenter, mass, spin, diskBrightness, aspect, time);
            color = color + diskColor;
        }
        
        // Intensity boost near the lens (magnification)
        let magnification = 1.0 + mass / (dist + 0.01);
        color = color * min(magnification, 2.0);
    }
    
    // Output
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(10.0)), alpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
