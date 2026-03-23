// ═══════════════════════════════════════════════════════════════════
//  Audio Spirograph - Audio-reactive spirograph with harmonic resonance
//  Category: generative
//  Features: audio-reactive, procedural, epitrochoid curves
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

// Hash function
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Epitrochoid calculation (spirograph curve)
fn epitrochoid(t: f32, R: f32, r: f32, d: f32) -> vec2<f32> {
    let k = R / r;
    let x = (R + r) * cos(t) - d * cos((k + 1.0) * t);
    let y = (R + r) * sin(t) - d * sin((k + 1.0) * t);
    return vec2<f32>(x, y);
}

// Hypotrochoid calculation (inner spirograph)
fn hypotrochoid(t: f32, R: f32, r: f32, d: f32) -> vec2<f32> {
    let k = R / r;
    let x = (R - r) * cos(t) + d * cos((k - 1.0) * t);
    let y = (R - r) * sin(t) - d * sin((k - 1.0) * t);
    return vec2<f32>(x, y);
}

// Distance to line segment
fn distToSegment(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = uv - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// HSL to RGB
fn hsl2rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs(fract(h * 6.0) * 2.0 - 1.0));
    let m = l - c * 0.5;
    
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    
    if (h < 1.0/6.0) { r = c; g = x; }
    else if (h < 2.0/6.0) { r = x; g = c; }
    else if (h < 3.0/6.0) { g = c; b = x; }
    else if (h < 4.0/6.0) { g = x; b = c; }
    else if (h < 5.0/6.0) { r = x; b = c; }
    else { r = c; b = x; }
    
    return vec3<f32>(r + m, g + m, b + m);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / min(resolution.x, resolution.y);
    let t = u.config.x;
    
    // Parameters - safe randomization
    let baseFreq = mix(0.5, 3.0, u.zoom_params.x);
    let audioReactivity = u.zoom_params.y; // 0 to 1
    let trailLength = mix(0.3, 0.95, u.zoom_params.z);
    let lineThickness = mix(0.001, 0.01, u.zoom_params.w);
    
    // Audio input (from zoom_config.x)
    let audio = u.zoom_config.x;
    let audioMod = 1.0 + audio * audioReactivity * 2.0;
    
    // Background accumulation for trails
    let prevCol = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    
    // Multiple harmonics - musical ratios
    let ratios = array<f32, 5>(1.0, 3.0/2.0, 4.0/3.0, 5.0/4.0, 5.0/3.0);
    let harmonics = array<f32, 5>(1.0, 2.0, 3.0, 4.0, 5.0);
    
    var minDist = 1000.0;
    var curveColor = vec3<f32>(0.0);
    var totalIntensity = 0.0;
    
    // Generate multiple spirograph curves
    for (var i: i32 = 0; i < 5; i++) {
        let ratio = ratios[i];
        let harmonic = harmonics[i];
        
        // Spirograph parameters
        let R = 0.3 * (1.0 + f32(i) * 0.1);
        let r = R / (ratio * harmonic * baseFreq);
        let d = r * 0.8 * audioMod;
        
        // Animation speed varies by harmonic
        let speed = 0.5 + f32(i) * 0.1;
        let time = t * speed;
        
        // Calculate current point on curve
        let pos = epitrochoid(time, R, r, d);
        
        // Calculate previous point for line segment
        let prevPos = epitrochoid(time - 0.05, R, r, d);
        
        // Distance to this curve segment
        let dist = distToSegment(uv, pos, prevPos);
        
        // Color based on harmonic
        let hue = fract(f32(i) * 0.2 + t * 0.05);
        let sat = 0.7 + audio * 0.3;
        let light = 0.5 + audio * 0.3;
        let col = hsl2rgb(hue, sat, light);
        
        // Accumulate minimum distance with intensity
        let intensity = 1.0 / (1.0 + f32(i) * 0.5);
        if (dist < minDist) {
            minDist = dist;
            curveColor = col * intensity;
            totalIntensity = intensity;
        }
    }
    
    // Add secondary harmonics (hypotrochoids)
    for (var i: i32 = 0; i < 3; i++) {
        let ratio = ratios[i + 2];
        let R = 0.25 * audioMod;
        let r = R / ratio;
        let d = r * 0.6;
        
        let time = -t * (0.3 + f32(i) * 0.1);
        let pos = hypotrochoid(time, R, r, d);
        let prevPos = hypotrochoid(time - 0.03, R, r, d);
        
        let dist = distToSegment(uv, pos, prevPos);
        let hue = fract(0.5 + f32(i) * 0.15 - t * 0.03);
        let col = hsl2rgb(hue, 0.8, 0.6);
        
        if (dist < minDist) {
            minDist = dist;
            curveColor = col * 0.7;
            totalIntensity = 0.7;
        }
    }
    
    // Create glow effect
    let glow = smoothstep(lineThickness * 5.0, lineThickness, minDist);
    let core = smoothstep(lineThickness * 2.0, 0.0, minDist);
    
    // Final color
    var col = curveColor * glow + vec3<f32>(1.0) * core * 0.5;
    
    // Add trail accumulation
    col = col + prevCol * trailLength * 0.9;
    
    // Vignette
    let vignette = 1.0 - length(uv) * 0.8;
    col = col * vignette;
    
    // Store for feedback
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col * 0.95, 1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
