// ═══════════════════════════════════════════════════════════════════
//  audio_geometric_pulse
//  Category: audio-reactive
//  Features: upgraded-rgba, depth-aware
//  Upgraded: 2026-03-22
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

// Rotate point
fn rotate(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// SDF: Circle
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// SDF: Box
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

// SDF: Equilateral triangle
fn sdTriangle(p: vec2<f32>, r: f32) -> f32 {
    let k = sqrt(3.0);
    let p2 = vec2<f32>(abs(p.x) - r, p.y + r / k);
    if (p2.x + k * abs(p2.y) > 0.0) {
        return length(vec2<f32>(p2.x - clamp(p2.x, -k * p2.y, k * p2.y), p2.y)) - r;
    }
    return -length(p2) - r;
}

// SDF: Hexagon
fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    let px = abs(p);
    return max(dot(px.xy, k.xy), px.y) - r;
}

// Pulse wave
fn pulseWave(uv: vec2<f32>, time: f32, speed: f32, freq: f32) -> f32 {
    let d = length(uv);
    return sin(d * freq - time * speed) * exp(-d * 2.0);
}

// Custom mod function for floating-point numbers
fn mod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

// Kaleidoscope repeat
fn kaleidoscope(uv: vec2<f32>, segments: i32) -> vec2<f32> {
    let angle = atan2(uv.y, uv.x);
    let r = length(uv);
    let segAngle = 2.0 * PI / f32(segments);
    let a = mod(angle, segAngle);
    if (a > segAngle / 2.0) {
        return vec2<f32>(cos(segAngle - a) * r, sin(segAngle - a) * r);
    }
    return vec2<f32>(cos(a) * r, sin(a) * r);
}

// Neon glow
fn neonGlow(dist: f32, thickness: f32, intensity: f32) -> f32 {
    return smoothstep(thickness, 0.0, dist) * intensity;
}

// Audio band color
fn audioColor(band: f32, audioPulse: f32) -> vec3<f32> {
    let hue = band * 0.8 + audioPulse * 0.2;
    return vec3<f32>(
        sin(hue * 6.28) * 0.5 + 0.5,
        sin(hue * 6.28 + 2.09) * 0.5 + 0.5,
        sin(hue * 6.28 + 4.19) * 0.5 + 0.5
    );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let symmetry = i32(3.0 + u.zoom_params.x * 9.0);    // 3-12 segments
    let shapeMorph = u.zoom_params.y;                    // 0-1 shape blend
    let pulseSpeed = 1.0 + u.zoom_params.z * 4.0;        // 1-5
    let complexity = u.zoom_params.w;                    // 0-1
    
    // Audio input
    let audioPulse = u.zoom_config.w;
    let mousePos = (u.zoom_config.yz - 0.5) * 2.0;
    
    // Kaleidoscope UV
    let kUV = kaleidoscope(uv - mousePos * 0.3, symmetry);
    
    // Multiple concentric shapes
    var color = vec3<f32>(0.0);
    let numShapes = i32(3.0 + complexity * 5.0);
    
    for (var i: i32 = 0; i < numShapes; i = i + 1) {
        let fi = f32(i);
        let t = time * 0.5 + fi * 0.5;
        
        // Pulsing radius
        let baseRadius = 0.1 + fi * 0.08;
        let pulse = sin(time * pulseSpeed + fi) * 0.02 * (1.0 + audioPulse);
        let radius = baseRadius + pulse;
        
        // Rotation
        let rotAngle = t * (0.2 + audioPulse * 0.5);
        let rotatedUV = rotate(kUV, rotAngle);
        
        // Shape morphing
        let d1 = sdCircle(rotatedUV, radius);
        let d2 = sdHexagon(rotatedUV, radius * 0.9);
        let d3 = sdTriangle(rotatedUV, radius * 1.1);
        
        // Morph between shapes
        var dist = mix(d1, d2, sin(shapeMorph * PI + fi * 0.5) * 0.5 + 0.5);
        dist = mix(dist, d3, cos(shapeMorph * PI * 2.0 + fi * 0.3) * 0.5 + 0.5);
        
        // Neon glow
        let thickness = 0.003 + audioPulse * 0.005;
        let intensity = 1.0 + audioPulse * 2.0;
        let glow = neonGlow(dist, thickness, intensity);
        
        // Color based on ring and audio
        let band = fi / f32(numShapes);
        let shapeColor = audioColor(band, audioPulse);
        
        // Add to accumulator
        color += shapeColor * glow * (1.0 - fi * 0.1);
        
        // Inner fill for some shapes
        if (i % 2 == 0) {
            let fill = smoothstep(0.0, thickness * 3.0, -dist) * 0.2;
            color += shapeColor * fill;
        }
    }
    
    // Central pulse burst
    let centerPulse = pulseWave(uv, time, pulseSpeed * 2.0, 20.0 + audioPulse * 30.0);
    color += vec3<f32>(1.0, 0.8, 0.6) * max(centerPulse, 0.0) * (0.5 + audioPulse);
    
    // Frequency band rings (visualization)
    let bands = 5;
    for (var b: i32 = 0; b < bands; b = b + 1) {
        let fb = f32(b);
        let bandRadius = 0.15 + fb * 0.06;
        let bandDist = abs(length(uv) - bandRadius);
        let bandGlow = smoothstep(0.01 + audioPulse * 0.02, 0.0, bandDist);
        let bandColor = audioColor(fb / f32(bands), audioPulse * 0.5);
        color += bandColor * bandGlow * (0.3 + audioPulse);
    }
    
    // Tone mapping
    color = color / (1.0 + color);
    
    // Vignette
    let vignette = 1.0 - length(uvFull - 0.5) * 0.4;
    color *= vignette;
    
    // Sample depth for alpha calculation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvFull, 0.0).r;
    
    // Calculate luminance-based alpha
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, luma);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);
    
    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(length(color), 0.0, 0.0, finalAlpha));
    
    // Store for feedback
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
