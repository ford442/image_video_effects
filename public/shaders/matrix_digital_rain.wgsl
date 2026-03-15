// ═══════════════════════════════════════════════════════════════════════════════
//  matrix_digital_rain.wgsl - Matrix Digital Rain with Decoding
//  
//  RGBA Focus: Alpha = character brightness/fade state
//  Techniques:
//    - Cascading character columns
//    - Character "decoding" from random to known
//    - Trail fade with alpha gradient
//    - Glow around bright characters
//    - Mouse creates disturbances
//  
//  Target: 4.6★ rating
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

// Hash functions
fn hash(f: f32) -> f32 {
    return fract(sin(f * 12.9898) * 43758.5453);
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Character pattern (simplified as dot matrix)
fn characterPattern(uv: vec2<f32>, charCode: f32, brightness: f32) -> f32 {
    // 5x7 character grid
    let grid = floor(uv * vec2<f32>(5.0, 7.0));
    let cellUV = fract(uv * vec2<f32>(5.0, 7.0));
    
    // Simple patterns based on charCode
    let pattern = hash(grid.x + grid.y * 5.0 + charCode * 100.0);
    let pixel = step(0.3, pattern);
    
    // Soft edge
    let edge = smoothstep(0.0, 0.2, cellUV.x) * smoothstep(1.0, 0.8, cellUV.x) *
               smoothstep(0.0, 0.2, cellUV.y) * smoothstep(1.0, 0.8, cellUV.y);
    
    return pixel * edge * brightness;
}

// Digital rain column
fn rainColumn(x: f32, y: f32, time: f32, speed: f32, audioPulse: f32) -> vec4<f32> {
    let columnSeed = hash(x * 123.45);
    let columnSpeed = speed * (0.5 + columnSeed);
    
    // Head position
    let headY = fract((time * columnSpeed) + columnSeed);
    
    // Distance from head
    let distFromHead = y - headY;
    if (distFromHead > 0.0) {
        distFromHead = distFromHead - 1.0; // Wrap around
    }
    
    // Character in column
    let charY = floor(y * 30.0);
    let charX = floor(x * 40.0);
    let charUV = vec2<f32>(fract(x * 40.0), fract(y * 30.0));
    
    // Decoding effect: characters near head are bright/clear
    let decodeDist = abs(distFromHead);
    let decoded = 1.0 - smoothstep(0.0, 0.3, decodeDist);
    
    // Character code changes over time
    let charCode = hash(charX + charY * 40.0 + floor(time * 10.0));
    
    // Brightness falls off behind head
    let trailBrightness = exp(decodeDist * 5.0) * (0.8 + audioPulse * 0.4);
    let headBrightness = smoothstep(0.05, 0.0, decodeDist);
    
    let brightness = max(trailBrightness, headBrightness * (1.0 + audioPulse));
    
    // Get character
    let charValue = characterPattern(charUV, charCode, brightness);
    
    // Colors
    let matrixGreen = vec3<f32>(0.0, 0.8, 0.2);
    let headWhite = vec3<f32>(0.9, 1.0, 0.9);
    
    let color = mix(matrixGreen, headWhite, headBrightness);
    
    // Alpha based on character and distance
    let alpha = charValue * brightness * (1.0 - smoothstep(0.5, 0.0, decodeDist) * 0.7);
    
    return vec4<f32>(color * charValue, alpha);
}

// Scanline effect
fn scanlines(uv: vec2<f32>, intensity: f32) -> f32 {
    return 1.0 - intensity * sin(uv.y * 200.0) * 0.5;
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
    let speed = 0.3 + u.zoom_params.x * 0.7; // 0.3-1.0
    let density = u.zoom_params.y; // 0-1
    let glowSize = u.zoom_params.z * 0.05; // 0-0.05
    let scanlineIntensity = u.zoom_params.w * 0.3; // 0-0.3
    
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Mouse disturbance
    let toMouse = length(uv - mousePos);
    let disturbance = smoothstep(0.2, 0.0, toMouse);
    
    // Get rain
    var rain = rainColumn(uv.x, uv.y, time, speed * (1.0 + audioPulse), audioPulse);
    
    // Apply disturbance
    rain.a *= 1.0 + disturbance * 2.0;
    rain.rgb += vec3<f32>(0.2) * disturbance;
    
    // Glow effect (blur approximation)
    if (glowSize > 0.001) {
        var glow = vec3<f32>(0.0);
        let samples = 8;
        for (var i: i32 = 0; i < samples; i = i + 1) {
            let angle = f32(i) * (2.0 * PI / f32(samples));
            let offset = vec2<f32>(cos(angle), sin(angle)) * glowSize;
            glow += rainColumn(uv.x + offset.x, uv.y + offset.y, time, speed, audioPulse).rgb;
        }
        glow /= f32(samples);
        rain.rgb += glow * 0.5;
    }
    
    // Scanlines
    let scan = scanlines(uv, scanlineIntensity);
    rain.rgb *= scan;
    
    // Bloom from bright areas
    let bloom = max(0.0, rain.a - 0.7) * vec3<f32>(0.5, 1.0, 0.5);
    rain.rgb += bloom;
    
    // Background (dark matrix)
    let bgColor = vec3<f32>(0.02, 0.05, 0.02);
    
    // Composite
    let finalRGB = mix(bgColor, rain.rgb, rain.a);
    let finalAlpha = rain.a;
    
    // Tone mapping
    finalRGB = finalRGB / (1.0 + finalRGB * 0.2);
    
    // Vignette (monitor edge)
    let vignette = 1.0 - length(uv - 0.5) * 0.4;
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB * vignette, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, finalAlpha));
}
