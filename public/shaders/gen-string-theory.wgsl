// ═══════════════════════════════════════════════════════════════════
//  String Theory - Vibrating string visualizations with harmonics
//  Category: generative
//  Features: procedural, wave equation, interference patterns
//  Created: 2026-03-22
//  By: Agent 4A
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

// Wave equation solution: y = A * sin(kx - wt) + A * sin(kx + wt) = 2A * sin(kx) * cos(wt)
fn standingWave(x: f32, t: f32, freq: f32, amplitude: f32, damping: f32) -> f32 {
    let k = freq * 6.28318; // wave number
    let w = freq * 3.14159; // angular frequency
    return 2.0 * amplitude * sin(k * x) * cos(w * t) * damping;
}

// Traveling wave component
fn travelingWave(x: f32, t: f32, freq: f32, amplitude: f32, speed: f32) -> f32 {
    let k = freq * 6.28318;
    let w = k * speed;
    return amplitude * sin(k * x - w * t);
}

// Harmonic series
fn harmonicWave(x: f32, t: f32, fundamental: f32, harmonic: i32, amplitude: f32) -> f32 {
    let n = f32(harmonic);
    return standingWave(x, t, fundamental * n, amplitude / n, 1.0);
}

// Interference pattern
fn interference(x: f32, t: f32, f1: f32, f2: f32, a1: f32, a2: f32) -> f32 {
    let w1 = sin(x * f1 * 6.28318 - t * f1);
    let w2 = sin(x * f2 * 6.28318 - t * f2);
    return a1 * w1 + a2 * w2;
}

// Color for each harmonic
fn harmonicColor(n: i32, t: f32) -> vec3<f32> {
    let hue = fract(f32(n) * 0.15 + t * 0.05);
    let sat = 0.8;
    let light = 0.6;
    
    let c = (1.0 - abs(2.0 * light - 1.0)) * sat;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = light - c * 0.5;
    
    var r = 0.0; var g = 0.0; var b = 0.0;
    if (hue < 1.0/6.0) { r = c; g = x; }
    else if (hue < 2.0/6.0) { r = x; g = c; }
    else if (hue < 3.0/6.0) { g = c; b = x; }
    else if (hue < 4.0/6.0) { g = x; b = c; }
    else if (hue < 5.0/6.0) { r = x; b = c; }
    else { r = c; b = x; }
    
    return vec3<f32>(r + m, g + m, b + m);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let fundamental = mix(0.5, 3.0, u.zoom_params.x);
    let harmonicRichness = i32(mix(1.0, 10.0, u.zoom_params.y));
    let damping = mix(0.8, 0.99, u.zoom_params.z);
    let excitement = u.zoom_params.w; // pluck strength
    
    // Audio reactivity from zoom_config.x
    let audio = u.zoom_config.x;
    let audioMod = 1.0 + audio * excitement;
    
    let aspect = resolution.x / resolution.y;
    var p = uv;
    p.x = p.x * aspect;
    
    var col = vec3<f32>(0.0);
    var totalIntensity = 0.0;
    
    // Multiple strings at different angles
    let numStrings = 5;
    for (var s: i32 = 0; s < numStrings; s++) {
        let angle = f32(s) * 0.314 + t * 0.02; // slight rotation over time
        let cosA = cos(angle);
        let sinA = sin(angle);
        
        // String center position
        let stringCenter = vec2<f32>(aspect * 0.5, 0.5 + f32(s - 2) * 0.15);
        
        // Transform to string-local coordinates
        let local = p - stringCenter;
        let stringX = local.x * cosA + local.y * sinA;
        let stringY = -local.x * sinA + local.y * cosA;
        
        // Skip if outside string length
        if (abs(stringX) < 1.5) {
            // Map to 0-1 along string
            let x = (stringX + 1.5) / 3.0;
            
            // Calculate wave with harmonics
            var y = 0.0;
            var stringCol = vec3<f32>(0.0);
            
            for (var h: i32 = 1; h <= harmonicRichness; h++) {
                let harmAmp = 0.1 * audioMod / f32(h);
                let damp = pow(damping, f32(h));
                y += harmonicWave(x, t, fundamental, h, harmAmp * damp);
                
                // Color contribution
                let hCol = harmonicColor(h, t);
                stringCol += hCol * (1.0 / f32(h));
            }
            
            // Add traveling wave component for pluck
            if (excitement > 0.1) {
                y += travelingWave(x, t, fundamental * 2.0, 0.05 * excitement, 2.0);
            }
            
            // Distance from string
            let dist = abs(stringY - y);
            let thickness = 0.003 + 0.002 * excitement;
            let intensity = smoothstep(thickness * 3.0, 0.0, dist);
            let core = smoothstep(thickness, 0.0, dist);
            
            // Glow effect
            let glow = exp(-dist * 50.0) * 0.3;
            
            // Combine
            col += stringCol * (intensity + glow) + vec3<f32>(1.0) * core * 0.5;
            totalIntensity += intensity;
            
            // Moiré interference pattern
            let moire = sin(dist * 200.0 + t * 2.0) * 0.5 + 0.5;
            col += stringCol * moire * intensity * 0.2;
        }
    }
    
    // Interference between all strings
    let interference = sin(p.x * 20.0 + t) * sin(p.y * 20.0 + t * 1.3);
    col += vec3<f32>(0.5, 0.3, 0.7) * interference * 0.05 * audioMod;
    
    // Energy visualization (glow based on intensity)
    let energyGlow = exp(-totalIntensity * 2.0) * audioMod;
    col += vec3<f32>(0.8, 0.6, 0.3) * energyGlow * 0.3;
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.6;
    col *= vignette;
    
    // Store feedback
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    col = col + prev * 0.3;
    
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col * 0.8, 1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
