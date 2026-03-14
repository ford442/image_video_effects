// ═══════════════════════════════════════════════════════════════
//  Spherical Harmonics Plasma - 3D Gas Giant Atmosphere
//  Projects plasma patterns onto a rotating sphere using Y(l,m) basis
//  functions for realistic planetary atmosphere visualization
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

// Constants
const PI: f32 = 3.14159265359;
const TWO_PI: f32 = 6.28318530718;

// ═══════════════════════════════════════════════════════════════
// 3D ROTATION MATRICES
// ═══════════════════════════════════════════════════════════════
fn rotateX(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

fn rotateY(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

fn rotateZ(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

// ═══════════════════════════════════════════════════════════════
// SPHERICAL HARMONICS Y(l,m)
// Y(l,m) are orthonormal basis functions on the sphere surface
// l = degree (0, 1, 2, 3...), m = order (-l to +l)
// ═══════════════════════════════════════════════════════════════

// Y(0,0) - constant term (monopole)
fn Y00(theta: f32, phi: f32) -> f32 {
    return 0.2820947918; // 1/sqrt(4π)
}

// Y(1,0) - z-oriented dipole
fn Y10(theta: f32, phi: f32) -> f32 {
    return 0.4886025119 * cos(theta); // sqrt(3/4π) * cos(θ)
}

// Y(1,1) - x-oriented dipole (real form)
fn Y1p1(theta: f32, phi: f32) -> f32 {
    return -0.4886025119 * sin(theta) * cos(phi); // -sqrt(3/4π) * sin(θ)cos(φ)
}

// Y(1,-1) - y-oriented dipole (real form)
fn Y1n1(theta: f32, phi: f32) -> f32 {
    return -0.4886025119 * sin(theta) * sin(phi); // -sqrt(3/4π) * sin(θ)sin(φ)
}

// Y(2,0) - quadrupole (z-oriented)
fn Y20(theta: f32, phi: f32) -> f32 {
    return 0.3153915653 * (3.0 * cos(theta) * cos(theta) - 1.0); // sqrt(5/16π) * (3cos²θ - 1)
}

// Y(2,1) - quadrupole
fn Y2p1(theta: f32, phi: f32) -> f32 {
    return -1.0219854764 * sin(theta) * cos(theta) * cos(phi); // -sqrt(15/4π) * sin(θ)cos(θ)cos(φ)
}

// Y(2,-1) - quadrupole
fn Y2n1(theta: f32, phi: f32) -> f32 {
    return -1.0219854764 * sin(theta) * cos(theta) * sin(phi); // -sqrt(15/4π) * sin(θ)cos(θ)sin(φ)
}

// Y(2,2) - quadrupole
fn Y2p2(theta: f32, phi: f32) -> f32 {
    return 0.5462742153 * sin(theta) * sin(theta) * cos(2.0 * phi); // sqrt(15/16π) * sin²θ * cos(2φ)
}

// Y(2,-2) - quadrupole
fn Y2n2(theta: f32, phi: f32) -> f32 {
    return 0.5462742153 * sin(theta) * sin(theta) * sin(2.0 * phi); // sqrt(15/16π) * sin²θ * sin(2φ)
}

// Y(3,0) - octupole
fn Y30(theta: f32, phi: f32) -> f32 {
    let ct = cos(theta);
    return 0.3731763326 * (5.0 * ct * ct * ct - 3.0 * ct); // sqrt(7/16π) * (5cos³θ - 3cosθ)
}

// ═══════════════════════════════════════════════════════════════
// COMBINED HARMONIC PATTERN
// ═══════════════════════════════════════════════════════════════
fn sphericalHarmonicsPattern(theta: f32, phi: f32, time: f32, coeffs: vec4<f32>) -> f32 {
    var pattern = 0.0;
    
    // l=0 (constant) - always on
    pattern += Y00(theta, phi) * 0.5;
    
    // l=1 (dipole terms) - controlled by zoom_params.x
    let l1_strength = coeffs.x;
    pattern += Y10(theta, phi) * sin(time * 0.5) * l1_strength;
    pattern += Y1p1(theta, phi) * cos(time * 0.3) * l1_strength * 0.7;
    pattern += Y1n1(theta, phi) * sin(time * 0.4) * l1_strength * 0.7;
    
    // l=2 (quadrupole terms) - controlled by zoom_params.y
    let l2_strength = coeffs.y;
    pattern += Y20(theta, phi) * cos(time * 0.6) * l2_strength;
    pattern += Y2p1(theta, phi) * sin(time * 0.45) * l2_strength * 0.8;
    pattern += Y2n1(theta, phi) * cos(time * 0.55) * l2_strength * 0.8;
    pattern += Y2p2(theta, phi) * sin(time * 0.35) * l2_strength * 0.6;
    pattern += Y2n2(theta, phi) * cos(time * 0.25) * l2_strength * 0.6;
    
    // l=3 (octupole) - controlled by zoom_params.z
    let l3_strength = coeffs.z;
    pattern += Y30(theta, phi) * sin(time * 0.7) * l3_strength * 0.5;
    
    return pattern;
}

// ═══════════════════════════════════════════════════════════════
// COLOR PALETTE - Gas Giant Atmosphere
// ═══════════════════════════════════════════════════════════════
fn gasGiantColor(value: f32, time: f32, hueShift: f32) -> vec3<f32> {
    // Normalize value to 0-1 range
    let v = value * 0.5 + 0.5;
    
    // Dynamic hue based on value and time
    let hue = fract(v * 0.3 + time * 0.05 + hueShift);
    
    // Jupiter-like palette: bands of brown, orange, cream, and red
    let color1 = vec3<f32>(0.8, 0.6, 0.4);  // Cream/tan
    let color2 = vec3<f32>(0.6, 0.4, 0.2);  // Brown
    let color3 = vec3<f32>(0.9, 0.5, 0.2);  // Orange
    let color4 = vec3<f32>(0.7, 0.3, 0.15); // Red-brown
    let color5 = vec3<f32>(0.85, 0.7, 0.5); // Light cream
    
    var color: vec3<f32>;
    if v < 0.2 {
        color = mix(color1, color2, v * 5.0);
    } else if v < 0.4 {
        color = mix(color2, color3, (v - 0.2) * 5.0);
    } else if v < 0.6 {
        color = mix(color3, color4, (v - 0.4) * 5.0);
    } else if v < 0.8 {
        color = mix(color4, color5, (v - 0.6) * 5.0);
    } else {
        color = mix(color5, color1, (v - 0.8) * 5.0);
    }
    
    // Add subtle color variation
    let variation = sin(v * 20.0 + time) * 0.1;
    color += variation;
    
    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════
// MAIN SHADER
// ═══════════════════════════════════════════════════════════════
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x * 0.15;
    
    // Pixel coordinates centered at origin
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / min(resolution.x, resolution.y);
    
    // Mouse interaction
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let mouseInfluence = u.zoom_config.w;
    
    // ═══════════════════════════════════════════════════════════
    // SPHERE RAY INTERSECTION
    // ═══════════════════════════════════════════════════════════
    let sphereRadius = 0.45;
    let sphereCenter = vec3<f32>(0.0, 0.0, 0.0);
    
    // Ray origin (camera position)
    var ro = vec3<f32>(0.0, 0.0, 1.8);
    
    // Ray direction
    let rd = normalize(vec3<f32>(uv.x, uv.y, -1.2));
    
    // Apply rotation based on time and mouse
    let rotTime = time * 0.5;
    let ro_rotated = rotateY(rotateX(ro, sin(time * 0.2) * 0.1), rotTime);
    
    // Mouse-based view rotation
    let viewRotY = mouse.x * 0.5 * mouseInfluence;
    let viewRotX = mouse.y * 0.3 * mouseInfluence;
    let ro_final = rotateY(rotateX(ro_rotated, viewRotX), viewRotY);
    let rd_final = rotateY(rotateX(rd, viewRotX), viewRotY);
    
    // Solve quadratic for ray-sphere intersection
    let oc = ro_final - sphereCenter;
    let a = dot(rd_final, rd_final);
    let b = 2.0 * dot(oc, rd_final);
    let c = dot(oc, oc) - sphereRadius * sphereRadius;
    let discriminant = b * b - 4.0 * a * c;
    
    var outputColor: vec3<f32>;
    var depth: f32 = 0.0;
    
    if discriminant > 0.0 {
        // Hit the sphere
        let t = (-b - sqrt(discriminant)) / (2.0 * a);
        let hitPoint = ro_final + rd_final * t;
        
        // Surface normal
        let normal = normalize(hitPoint - sphereCenter);
        
        // Convert to spherical coordinates
        let theta = acos(clamp(normal.y, -1.0, 1.0)); // polar angle from Y axis
        let phi = atan2(normal.z, normal.x); // azimuthal angle
        
        // ═══════════════════════════════════════════════════════
        // SPHERICAL HARMONICS PATTERN
        // ═══════════════════════════════════════════════════════
        // Get control coefficients from zoom_params
        // x = l=1 strength, y = l=2 strength, z = l=3 strength, w = hue shift
        let coeffs = u.zoom_params;
        
        var pattern = 0.0;
        
        // l=0 (constant) - base atmosphere
        pattern += Y00(theta, phi) * 0.4;
        
        // l=1 (dipole) - large bands
        let l1 = coeffs.x;
        pattern += Y10(theta, phi) * sin(time * 0.5 + phi * 2.0) * l1;
        pattern += Y1p1(theta, phi) * cos(time * 0.3) * l1 * 0.5;
        pattern += Y1n1(theta, phi) * sin(time * 0.4) * l1 * 0.5;
        
        // l=2 (quadrupole) - medium bands
        let l2 = coeffs.y;
        pattern += Y20(theta, phi) * cos(time * 0.6) * l2;
        pattern += Y2p1(theta, phi) * sin(time * 0.45 + theta) * l2 * 0.6;
        pattern += Y2n1(theta, phi) * cos(time * 0.55) * l2 * 0.6;
        pattern += Y2p2(theta, phi) * sin(time * 0.35 + phi * 3.0) * l2 * 0.4;
        pattern += Y2n2(theta, phi) * cos(time * 0.25) * l2 * 0.4;
        
        // l=3 (octupole) - fine detail
        let l3 = coeffs.z;
        pattern += Y30(theta, phi) * sin(time * 0.7 + phi) * l3 * 0.5;
        
        // Add turbulent detail using high-frequency modulation
        let turbulence = sin(theta * 15.0 + time) * sin(phi * 12.0 - time * 0.5) * 0.05;
        pattern += turbulence * (l1 + l2 + l3) * 0.3;
        
        // ═══════════════════════════════════════════════════════
        // LIGHTING
        // ═══════════════════════════════════════════════════════
        // Light position (sun-like, offset to create terminator)
        let lightDir = normalize(vec3<f32>(0.8, 0.3, 1.0));
        
        // Diffuse lighting
        let diff = max(dot(normal, lightDir), 0.0);
        
        // Ambient lighting (fill from opposite side)
        let ambient = 0.25;
        
        // Specular highlight (atmospheric scattering)
        let viewDir = -rd_final;
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(normal, halfDir), 0.0), 32.0) * 0.3;
        
        // Rim lighting (atmospheric glow at edges)
        let rim = pow(1.0 - abs(dot(normal, viewDir)), 3.0) * 0.4;
        
        // ═══════════════════════════════════════════════════════
        // COLOR APPLICATION
        // ═══════════════════════════════════════════════════════
        let baseColor = gasGiantColor(pattern, time, coeffs.w);
        
        // Apply lighting
        let litColor = baseColor * (diff * 0.7 + ambient) + vec3<f32>(spec);
        
        // Add atmospheric rim glow
        let atmosphereColor = vec3<f32>(0.6, 0.8, 1.0);
        outputColor = litColor + atmosphereColor * rim;
        
        // Store depth (normalized Z for depth buffer)
        let clipZ = hitPoint.z;
        depth = (clipZ + sphereRadius) / (sphereRadius * 2.0 + 1.8);
        
    } else {
        // Background - deep space
        let bgGradient = 1.0 - length(uv) * 0.5;
        outputColor = vec3<f32>(0.02, 0.03, 0.06) * bgGradient;
        
        // Subtle stars
        let starNoise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        if starNoise > 0.995 {
            outputColor += vec3<f32>(1.0) * (starNoise - 0.995) * 200.0;
        }
        
        depth = 1.0;
    }
    
    // Store final color
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(clamp(outputColor, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    
    // Store depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
