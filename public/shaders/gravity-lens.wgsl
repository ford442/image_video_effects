// ═══════════════════════════════════════════════════════════════════════════════
//  Gravity Lens - Schwarzschild & Kerr Metric Gravitational Lensing with Alpha Physics
//  Category: distortion
//  
//  Scientific Implementation:
//  - Schwarzschild metric for non-spinning black holes
//  - Einstein ring formation when source aligns with lens
//  - Kerr metric approximation for frame-dragging effects
//  - Ray-tracing approach for realistic light bending
//  
//  ALPHA PHYSICS:
//  - Gravitational redshift affects light intensity
//  - Stronger lensing = more light path deviation = scattered alpha
//  - Event horizon = total absorption (alpha = 1.0, but black)
//  - Accretion disk emission affects local opacity
//  - Doppler beaming from rotating disk affects per-pixel alpha
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
const SCHWARZSCHILD_FACTOR: f32 = 4.0;

// Texture sampling with bilinear interpolation
fn sampleSmooth(uv: vec2<f32>) -> vec4<f32> {
    return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
}

// Schwarzschild lens equation: calculates deflection angle
fn schwarzschildDeflection(r: f32, mass: f32) -> f32 {
    let safeR = max(r, 0.0001);
    return SCHWARZSCHILD_FACTOR * mass / safeR;
}

// Calculate Einstein radius
fn einsteinRadius(mass: f32, scale: f32) -> f32 {
    return sqrt(mass * scale * 0.5);
}

// Kerr metric frame dragging effect
fn kerrFrameDragging(
    pos: vec2<f32>,
    massCenter: vec2<f32>,
    spin: f32,
    r: f32
) -> vec2<f32> {
    if (spin < 0.001) {
        return vec2<f32>(0.0);
    }
    
    let angle = atan2(pos.y - massCenter.y, pos.x - massCenter.x);
    let iscoRadius = 6.0 * mass * (1.0 + spin * 0.5);
    let safeR = max(r, iscoRadius * 0.1);
    
    let dragStrength = spin * 0.02 / (safeR * safeR + 0.001);
    
    let offsetR = dragStrength * r;
    return vec2<f32>(
        -offsetR * sin(angle),
        offsetR * cos(angle)
    );
}

// Ray tracing approach: trace ray backward from observer through lens
fn traceRaySchwarzschild(
    observerUV: vec2<f32>,
    massCenter: vec2<f32>,
    mass: f32,
    aspect: f32
) -> vec2<f32> {
    let obsPhys = vec2<f32>(
        (observerUV.x - massCenter.x) * aspect,
        observerUV.y - massCenter.y
    );
    
    let r = length(obsPhys);
    let safeR = max(r, 0.0001);
    
    let deflection = schwarzschildDeflection(safeR, mass);
    
    let angle = atan2(obsPhys.y, obsPhys.x);
    let sourceAngle = angle - deflection;
    
    let sourcePhys = vec2<f32>(
        safeR * cos(sourceAngle),
        safeR * sin(sourceAngle)
    );
    
    return vec2<f32>(
        massCenter.x + sourcePhys.x / aspect,
        massCenter.y + sourcePhys.y
    );
}

// Einstein ring detection and enhancement
fn einsteinRingIntensity(
    uv: vec2<f32>,
    massCenter: vec2<f32>,
    mass: f32,
    scale: f32,
    aspect: f32
) -> f32 {
    let thetaE = einsteinRadius(mass, scale);
    let dVec = vec2<f32>((uv.x - massCenter.x) * aspect, uv.y - massCenter.y);
    let r = length(dVec);
    
    let ringWidth = thetaE * 0.15;
    let distFromRing = abs(r - thetaE);
    
    if (distFromRing < ringWidth * 2.0) {
        return exp(-distFromRing * distFromRing / (ringWidth * ringWidth)) * 0.5;
    }
    return 0.0;
}

// Photon ring intensity
fn photonRingIntensity(
    uv: vec2<f32>,
    massCenter: vec2<f32>,
    mass: f32,
    aspect: f32
) -> f32 {
    let photonSphereRadius = 3.0 * mass;
    let dVec = vec2<f32>((uv.x - massCenter.x) * aspect, uv.y - massCenter.y);
    let r = length(dVec);
    
    let ringWidth = mass * 0.05;
    let distFromRing = abs(r - photonSphereRadius * 0.001);
    
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
) -> vec4<f32> {
    let dVec = vec2<f32>((uv.x - massCenter.x) * aspect, uv.y - massCenter.y);
    let r = length(dVec);
    
    let iscoInner = mass * (6.0 - spin * 4.0);
    let iscoOuter = mass * 20.0;
    
    let innerEdge = iscoInner * 0.001;
    let outerEdge = iscoOuter * 0.001;
    
    if (r < innerEdge || r > outerEdge) {
        return vec4<f32>(0.0);
    }
    
    let t = (r - innerEdge) / (outerEdge - innerEdge);
    let temp = pow(1.0 - t * 0.8, 2.0);
    
    let angle = atan2(dVec.y, dVec.x);
    let doppler = 1.0 + spin * 0.3 * sin(angle + time * 0.5);
    
    let hotColor = vec3<f32>(1.0, 0.9, 0.8);
    let coolColor = vec3<f32>(1.0, 0.4, 0.1);
    let diskColor = mix(coolColor, hotColor, temp);
    
    let intensity = temp * temp * temp * temp * brightness * doppler;
    let edgeFade = smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.8, 1.0, t));
    
    // Return RGBA with disk alpha
    let diskAlpha = intensity * edgeFade;
    return vec4<f32>(diskColor * intensity * edgeFade * 3.0, diskAlpha);
}

// Gravitational redshift calculation
fn gravitationalRedshift(uv: vec2<f32>, mass: f32, massCenter: vec2<f32>, aspect: f32) -> f32 {
    let dVec = vec2<f32>((uv.x - massCenter.x) * aspect, uv.y - massCenter.y);
    let r = length(dVec);
    return 1.0 / sqrt(1.0 - mass / (r * 1000.0 + mass));
}

// ═══════════════════════════════════════════════════════════════════════════════
// ALPHA PHYSICS: Gravitational lensing alpha calculation
// ═══════════════════════════════════════════════════════════════════════════════

fn calculateGravitationalAlpha(
    baseAlpha: f32,
    dist: f32,
    horizonRadius: f32,
    mass: f32,
    redshift: f32
) -> f32 {
    // Inside event horizon = total absorption
    if (dist < horizonRadius) {
        return 1.0;
    }
    
    // Gravitational redshift reduces intensity (affects perceived alpha)
    let redshiftFactor = 1.0 / redshift;
    
    // Strong lensing creates light scattering
    let lensingStrength = mass / (dist + 0.01);
    let scatteringLoss = lensingStrength * 0.3;
    
    // Time dilation factor affects accumulation
    let timeDilation = sqrt(1.0 - horizonRadius / max(dist, horizonRadius * 1.01));
    
    return clamp(baseAlpha * redshiftFactor * timeDilation - scatteringLoss, 0.3, 1.0);
}

// Calculate magnification factor for alpha
fn calculateMagnificationAlpha(
    mass: f32,
    dist: f32
) -> f32 {
    let magnification = 1.0 + mass / (dist + 0.01);
    // Higher magnification = brighter = effectively higher alpha
    return min(magnification, 2.0);
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
    let mass = max(u.zoom_params.x * 0.3, 0.001);
    let einsteinScale = u.zoom_params.y;
    let spin = clamp(u.zoom_params.z, 0.0, 0.99);
    let diskBrightness = u.zoom_params.w;
    
    // Lens center
    let hasMouse = u.zoom_config.y >= 0.0 && u.zoom_config.z >= 0.0;
    var lensCenter = select(vec2<f32>(0.5, 0.5), u.zoom_config.yz, hasMouse);
    
    // Schwarzschild radius
    let rs = 2.0 * mass;
    let horizonRadius = rs * 0.001;
    
    // Distance from lens center
    let dVec = vec2<f32>((uv.x - lensCenter.x) * aspect, uv.y - lensCenter.y);
    let dist = length(dVec);
    
    var color = vec3<f32>(0.0);
    var alpha = 1.0;
    
    // Event horizon
    if (dist < horizonRadius) {
        color = vec3<f32>(0.0);
        alpha = 1.0;
    } else {
        // Ray trace backward
        let sourceUV = traceRaySchwarzschild(uv, lensCenter, mass, aspect);
        
        // Apply Kerr frame dragging
        let kerrOffset = kerrFrameDragging(uv, lensCenter, spin, dist);
        let finalUV = sourceUV + kerrOffset;
        
        // Gravitational redshift
        let redshift = gravitationalRedshift(uv, mass, lensCenter, aspect);
        
        // Sample with chromatic aberration
        let dispersionR = 1.0;
        let dispersionG = 0.98;
        let dispersionB = 0.96;
        
        let uvR = lensCenter + (finalUV - lensCenter) * dispersionR;
        let uvG = lensCenter + (finalUV - lensCenter) * dispersionG;
        let uvB = lensCenter + (finalUV - lensCenter) * dispersionB;
        
        let sampleR = sampleSmooth(uvR);
        let sampleG = sampleSmooth(uvG);
        let sampleB = sampleSmooth(uvB);
        
        color = vec3<f32>(sampleR.r, sampleG.g, sampleB.b);
        
        // Calculate base alpha from samples
        let baseAlpha = (sampleR.a + sampleG.a + sampleB.a) / 3.0;
        
        // Apply gravitational alpha physics
        alpha = calculateGravitationalAlpha(baseAlpha, dist, horizonRadius, mass, redshift);
        
        // Apply gravitational redshift to color
        let redshiftFactor = smoothstep(horizonRadius * 3.0, horizonRadius, dist);
        color.r = mix(color.r, color.r * 1.1, redshiftFactor);
        color.b = mix(color.b, color.b * 0.9, redshiftFactor);
        
        // Einstein ring enhancement
        let ringBoost = einsteinRingIntensity(uv, lensCenter, mass, einsteinScale, aspect);
        color = color * (1.0 + ringBoost);
        
        // Photon ring
        if (mass > 0.05) {
            let photonBoost = photonRingIntensity(uv, lensCenter, mass, aspect);
            let photonColor = vec3<f32>(1.0, 0.95, 0.8) * photonBoost * mass * 10.0;
            color = color + photonColor;
        }
        
        // Accretion disk
        if (diskBrightness > 0.0) {
            let disk = accretionDisk(uv, lensCenter, mass, spin, diskBrightness, aspect, time);
            color = color + disk.rgb;
            // Disk adds to alpha
            alpha = min(alpha + disk.a, 1.0);
        }
        
        // Magnification affects alpha
        let magAlpha = calculateMagnificationAlpha(mass, dist);
        alpha = alpha * magAlpha;
    }
    
    // Output RGBA
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(10.0)), alpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
