// ═══════════════════════════════════════════════════════════════════
//  aurora_borealis
//  Category: atmospheric
//  Features: upgraded-rgba, depth-aware, ribbon-alpha
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

// Hash
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    return fract((q.x + q.y) * q.z);
}

// Curl noise
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    
    let n = hash3(vec3<f32>(p, time * 0.1));
    let nx = hash3(vec3<f32>(p + vec2<f32>(eps, 0.0), time * 0.1));
    let ny = hash3(vec3<f32>(p + vec2<f32>(0.0, eps), time * 0.1));
    
    return vec2<f32>(ny - n, n - nx) / eps;
}

// Aurora ribbon curve
fn auroraRibbon(x: f32, t: f32, ribbonId: f32) -> vec2<f32> {
    // Base wave
    let freq1 = 1.0 + ribbonId * 0.5;
    let freq2 = 2.0 + ribbonId * 0.3;
    
    let y1 = sin(x * freq1 * PI * 2.0 + t * 0.3) * 0.15;
    let y2 = sin(x * freq2 * PI * 2.0 + t * 0.5 + ribbonId) * 0.1;
    
    return vec2<f32>(x, 0.5 + y1 + y2);
}

// Aurora color based on altitude and intensity
fn auroraColor(height: f32, intensity: f32) -> vec3<f32> {
    // Realistic aurora colors:
    // Low altitude: green (oxygen)
    // High altitude: red (oxygen)
    // Rare: blue/purple (nitrogen)
    
    let green = vec3<f32>(0.2, 0.9, 0.4);
    let red = vec3<f32>(0.9, 0.3, 0.2);
    let purple = vec3<f32>(0.6, 0.2, 0.8);
    
    var color: vec3<f32>;
    if (height < 0.3) {
        color = green;
    } else if (height < 0.6) {
        color = mix(green, red, (height - 0.3) / 0.3);
    } else {
        color = mix(red, purple, (height - 0.6) / 0.4);
    }
    
    return color * intensity;
}

// Starfield
fn stars(uv: vec2<f32>, time: f32) -> vec3<f32> {
    let starUV = uv * 100.0;
    let starHash = hash2(floor(starUV));
    let star = step(0.99, starHash);
    
    // Twinkle
    let twinkle = sin(time * 3.0 + starHash * 10.0) * 0.5 + 0.5;
    
    return vec3<f32>(star * twinkle);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let numRibbons = i32(3.0 + u.zoom_params.x * 5.0); // 3-8 ribbons
    let flowSpeed = 0.2 + u.zoom_params.y * 0.5; // 0.2-0.7
    let ribbonWidth = 0.02 + u.zoom_params.z * 0.05; // 0.02-0.07
    let glowIntensity = 0.5 + u.zoom_params.w; // 0.5-1.5
    
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Night sky background
    let nightSky = vec3<f32>(0.02, 0.03, 0.08);
    
    // Add stars
    let starField = stars(uv, time);
    var accumRGB = nightSky + starField * 0.5;
    var accumAlpha = 0.0;
    
    // Mouse attraction
    let mouseInfluence = smoothstep(0.5, 0.0, length(uv - mousePos));
    
    // Draw aurora ribbons
    for (var i: i32 = 0; i < numRibbons; i = i + 1) {
        let fi = f32(i);
        
        // Get ribbon position
        let ribbonBase = auroraRibbon(uv.x, time * flowSpeed, fi);
        
        // Apply curl noise for turbulence
        let curl = curlNoise(vec2<f32>(uv.x * 2.0, time * 0.2), time);
        var ribbonPos = ribbonBase + curl * 0.1 * (1.0 + audioPulse);
        
        // Mouse attraction
        let toMouse = mousePos - ribbonPos;
        ribbonPos += toMouse * mouseInfluence * 0.2;
        
        // Distance to ribbon
        let dist = abs(uv.y - ribbonPos.y);
        
        // Ribbon shape with falloff
        let ribbonShape = smoothstep(ribbonWidth * (1.0 + fi * 0.3), 0.0, dist);
        
        // Intensity variation along ribbon
        let intensity = (sin(uv.x * 10.0 + fi + time) * 0.5 + 0.5) * 
                        (1.0 + audioPulse * sin(time * 5.0 + fi));
        
        // Aurora color
        let height = (uv.y - 0.3) / 0.4; // Normalize to typical aurora height
        let color = auroraColor(height, intensity * glowIntensity);
        
        // Glow around ribbon
        let glow = smoothstep(ribbonWidth * 3.0, ribbonWidth, dist) * glowIntensity * 0.5;
        
        // Combine
        let contribution = color * (ribbonShape + glow);
        let alpha = ribbonShape * 0.8 + glow * 0.3;
        
        // Additive blending
        accumRGB += contribution * (1.0 - accumAlpha);
        accumAlpha = min(accumAlpha + alpha, 1.0);
    }
    
    // Horizontal curtain effect
    let curtain = sin(uv.y * 50.0 + time * 0.3) * 0.5 + 0.5;
    accumRGB *= 0.8 + curtain * 0.2;
    
    // Tone mapping
    accumRGB = accumRGB / (1.0 + accumRGB * 0.3);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    
    textureStore(writeTexture, coord, vec4<f32>(accumRGB * vignette, accumAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(accumAlpha, 0.0, 0.0, 1.0));
    
    textureStore(dataTextureA, coord, vec4<f32>(accumRGB, accumAlpha));
}
