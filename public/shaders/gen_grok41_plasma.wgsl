// ═══════════════════════════════════════════════════════════════════
//  Spherical Harmonics Plasma - 3D Gas Giant Atmosphere
//  Projects plasma patterns onto a rotating sphere using Y(l,m) basis
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural, animated, spherical-harmonics
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

const PI: f32 = 3.14159265359;
const TWO_PI: f32 = 6.28318530718;

// 3D Rotation Matrices
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

// Spherical Harmonics Y(l,m)
fn Y00(theta: f32, phi: f32) -> f32 { return 0.2820947918; }
fn Y10(theta: f32, phi: f32) -> f32 { return 0.4886025119 * cos(theta); }
fn Y1p1(theta: f32, phi: f32) -> f32 { return -0.4886025119 * sin(theta) * cos(phi); }
fn Y1n1(theta: f32, phi: f32) -> f32 { return -0.4886025119 * sin(theta) * sin(phi); }
fn Y20(theta: f32, phi: f32) -> f32 { return 0.3153915653 * (3.0 * cos(theta) * cos(theta) - 1.0); }
fn Y2p1(theta: f32, phi: f32) -> f32 { return -1.0219854764 * sin(theta) * cos(theta) * cos(phi); }
fn Y2n1(theta: f32, phi: f32) -> f32 { return -1.0219854764 * sin(theta) * cos(theta) * sin(phi); }
fn Y2p2(theta: f32, phi: f32) -> f32 { return 0.5462742153 * sin(theta) * sin(theta) * cos(2.0 * phi); }
fn Y2n2(theta: f32, phi: f32) -> f32 { return 0.5462742153 * sin(theta) * sin(theta) * sin(2.0 * phi); }
fn Y30(theta: f32, phi: f32) -> f32 {
    let ct = cos(theta);
    return 0.3731763326 * (5.0 * ct * ct * ct - 3.0 * ct);
}

// Color Palette - Gas Giant Atmosphere
fn gasGiantColor(value: f32, time: f32, hueShift: f32) -> vec3<f32> {
    let v = value * 0.5 + 0.5;
    let hue = fract(v * 0.3 + time * 0.05 + hueShift);
    
    let color1 = vec3<f32>(0.8, 0.6, 0.4);
    let color2 = vec3<f32>(0.6, 0.4, 0.2);
    let color3 = vec3<f32>(0.9, 0.5, 0.2);
    let color4 = vec3<f32>(0.7, 0.3, 0.15);
    let color5 = vec3<f32>(0.85, 0.7, 0.5);
    
    var color: vec3<f32>;
    if v < 0.2 { color = mix(color1, color2, v * 5.0); }
    else if v < 0.4 { color = mix(color2, color3, (v - 0.2) * 5.0); }
    else if v < 0.6 { color = mix(color3, color4, (v - 0.4) * 5.0); }
    else if v < 0.8 { color = mix(color4, color5, (v - 0.6) * 5.0); }
    else { color = mix(color5, color1, (v - 0.8) * 5.0); }
    
    let variation = sin(v * 20.0 + time) * 0.1;
    color += variation;
    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x * 0.15;
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / min(resolution.x, resolution.y);
    let coord = vec2<i32>(global_id.xy);
    
    // Mouse interaction
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let mouseInfluence = u.zoom_config.w;
    
    // Sphere parameters
    let sphereRadius = 0.45;
    let sphereCenter = vec3<f32>(0.0, 0.0, 0.0);
    var ro = vec3<f32>(0.0, 0.0, 1.8);
    let rd = normalize(vec3<f32>(uv.x, uv.y, -1.2));
    
    // Apply rotation
    let rotTime = time * 0.5;
    let ro_rotated = rotateY(rotateX(ro, sin(time * 0.2) * 0.1), rotTime);
    let viewRotY = mouse.x * 0.5 * mouseInfluence;
    let viewRotX = mouse.y * 0.3 * mouseInfluence;
    let ro_final = rotateY(rotateX(ro_rotated, viewRotX), viewRotY);
    let rd_final = rotateY(rotateX(rd, viewRotX), viewRotY);
    
    // Ray-sphere intersection
    let oc = ro_final - sphereCenter;
    let a = dot(rd_final, rd_final);
    let b = 2.0 * dot(oc, rd_final);
    let c = dot(oc, oc) - sphereRadius * sphereRadius;
    let discriminant = b * b - 4.0 * a * c;
    
    var outputColor: vec3<f32>;
    var depth: f32 = 0.0;
    var alpha: f32 = 1.0;
    
    if discriminant > 0.0 {
        let t = (-b - sqrt(discriminant)) / (2.0 * a);
        let hitPoint = ro_final + rd_final * t;
        let normal = normalize(hitPoint - sphereCenter);
        let theta = acos(clamp(normal.y, -1.0, 1.0));
        let phi = atan2(normal.z, normal.x);
        
        // Spherical harmonics pattern
        let coeffs = u.zoom_params;
        var pattern = 0.0;
        
        pattern += Y00(theta, phi) * 0.4;
        let l1 = coeffs.x;
        pattern += Y10(theta, phi) * sin(time * 0.5 + phi * 2.0) * l1;
        pattern += Y1p1(theta, phi) * cos(time * 0.3) * l1 * 0.5;
        pattern += Y1n1(theta, phi) * sin(time * 0.4) * l1 * 0.5;
        
        let l2 = coeffs.y;
        pattern += Y20(theta, phi) * cos(time * 0.6) * l2;
        pattern += Y2p1(theta, phi) * sin(time * 0.45 + theta) * l2 * 0.6;
        pattern += Y2n1(theta, phi) * cos(time * 0.55) * l2 * 0.6;
        pattern += Y2p2(theta, phi) * sin(time * 0.35 + phi * 3.0) * l2 * 0.4;
        pattern += Y2n2(theta, phi) * cos(time * 0.25) * l2 * 0.4;
        
        let l3 = coeffs.z;
        pattern += Y30(theta, phi) * sin(time * 0.7 + phi) * l3 * 0.5;
        
        let turbulence = sin(theta * 15.0 + time) * sin(phi * 12.0 - time * 0.5) * 0.05;
        pattern += turbulence * (l1 + l2 + l3) * 0.3;
        
        // Lighting
        let lightDir = normalize(vec3<f32>(0.8, 0.3, 1.0));
        let diff = max(dot(normal, lightDir), 0.0);
        let ambient = 0.25;
        let viewDir = -rd_final;
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(normal, halfDir), 0.0), 32.0) * 0.3;
        let rim = pow(1.0 - abs(dot(normal, viewDir)), 3.0) * 0.4;
        
        // Color application
        let baseColor = gasGiantColor(pattern, time, coeffs.w);
        let litColor = baseColor * (diff * 0.7 + ambient) + vec3<f32>(spec);
        let atmosphereColor = vec3<f32>(0.6, 0.8, 1.0);
        outputColor = litColor + atmosphereColor * rim;
        
        // Alpha based on rim for atmospheric fade
        let rimAlpha = pow(1.0 - abs(dot(normal, viewDir)), 2.0);
        alpha = mix(0.9, 1.0, rimAlpha * 0.5);
        
        let clipZ = hitPoint.z;
        depth = (clipZ + sphereRadius) / (sphereRadius * 2.0 + 1.8);
    } else {
        // Background
        let bgGradient = 1.0 - length(uv) * 0.5;
        outputColor = vec3<f32>(0.02, 0.03, 0.06) * bgGradient;
        let starNoise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        if starNoise > 0.995 {
            outputColor += vec3<f32>(1.0) * (starNoise - 0.995) * 200.0;
        }
        depth = 1.0;
        alpha = 1.0;
    }
    
    // Output RGBA
    textureStore(writeTexture, coord, vec4<f32>(clamp(outputColor, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
    
    // Output depth
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
