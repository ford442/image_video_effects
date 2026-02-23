// ═══════════════════════════════════════════════════════════════
//  RGB Glitch Displacement - Digital glitch effect with RGB channel displacement
//  Category: retro-glitch
//  Features: mouse-driven
//  Author: Kimi
// ═══════════════════════════════════════════════════════════════

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

// Hash functions
fn hash1(p: f32) -> f32 {
    return fract(sin(p * 127.1) * 43758.5453);
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

// Noise
fn noise1d(p: f32) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let f_smooth = f * f * (3.0 - 2.0 * f);
    return mix(hash1(i), hash1(i + 1.0), f_smooth);
}

// Block glitch pattern
fn blockGlitch(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    let blockSize = 0.02 + intensity * 0.03;
    let blockUV = floor(uv / blockSize) * blockSize;
    
    let h = hash3(vec3<f32>(blockUV, floor(time * 10.0)));
    
    var offset = vec2<f32>(0.0);
    if (h > 0.85) {
        offset.x = (hash1(h) - 0.5) * intensity * 0.3;
    }
    if (h > 0.92) {
        offset.y = (hash1(h + 1.0) - 0.5) * intensity * 0.1;
    }
    
    return offset;
}

// Scanline glitch
fn scanlineGlitch(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let scanlineY = floor(uv.y * 50.0) / 50.0;
    let h = hash2(vec2<f32>(scanlineY, floor(time * 15.0)));
    
    if (h > 0.95) {
        return (hash1(h) - 0.5) * intensity * 0.5;
    }
    return 0.0;
}

// Digital noise
fn digitalNoise(uv: vec2<f32>, time: f32) -> f32 {
    return hash3(vec3<f32>(uv * 200.0, time * 60.0));
}

// RGB shift based on mouse distance
fn rgbShift(uv: vec2<f32>, mouse: vec2<f32>, amount: f32) -> vec3<f32> {
    let toMouse = uv - mouse;
    let dist = length(toMouse);
    let angle = atan2(toMouse.y, toMouse.x);
    
    let shiftDir = vec2<f32>(cos(angle + 1.0), sin(angle + 1.0));
    let shiftAmount = amount * smoothstep(0.5, 0.0, dist);
    
    let rUV = uv + shiftDir * shiftAmount;
    let gUV = uv;
    let bUV = uv - shiftDir * shiftAmount;
    
    let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    
    return vec3<f32>(r, g, b);
}

// Wave displacement
fn waveDisplace(uv: vec2<f32>, mouse: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    let dist = length(uv - mouse);
    let wave = sin(dist * 30.0 - time * 8.0) * intensity * 0.05;
    
    let angle = atan2(uv.y - mouse.y, uv.x - mouse.x);
    let displacement = vec2<f32>(cos(angle), sin(angle)) * wave * smoothstep(0.4, 0.0, dist);
    
    return uv + displacement;
}

// Pixel sorting effect
fn pixelSort(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    let sortThreshold = 0.7 + intensity * 0.25;
    let h = hash2(vec2<f32>(uv.x, floor(time * 5.0)));
    
    if (h > sortThreshold) {
        let sortAmount = (hash1(h) - 0.5) * intensity * 0.2;
        return uv + vec2<f32>(0.0, sortAmount);
    }
    return uv;
}

// Datamoshing-like effect
fn datamosh(uv: vec2<f32>, mouse: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    let dist = length(uv - mouse);
    let moshStrength = intensity * smoothstep(0.3, 0.0, dist);
    
    let blockY = floor(uv.y * 30.0) / 30.0;
    let h = hash2(vec2<f32>(blockY, floor(time * 8.0)));
    
    if (h > 0.9) {
        let offsetX = (hash1(h) - 0.5) * moshStrength * 0.4;
        return uv + vec2<f32>(offsetX, 0.0);
    }
    return uv;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    
    // Parameters from sliders
    let glitchIntensity = u.zoom_params.x;
    let scanlineDensity = u.zoom_params.y * 100.0 + 20.0;
    let colorShift = u.zoom_params.z * 0.05;
    
    var p = uv;
    
    // === LAYER 1: Mouse-reactive wave displacement ===
    p = waveDisplace(p, mouse, time, glitchIntensity);
    
    // === LAYER 2: Block glitch ===
    let blockOffset = blockGlitch(p, time, glitchIntensity);
    p = p + blockOffset;
    
    // === LAYER 3: Scanline glitch ===
    let scanOffset = scanlineGlitch(p, time, glitchIntensity);
    p.x = p.x + scanOffset;
    
    // === LAYER 4: Pixel sorting ===
    p = pixelSort(p, time, glitchIntensity);
    
    // === LAYER 5: Datamosh near mouse ===
    p = datamosh(p, mouse, time, glitchIntensity);
    
    // === SAMPLE WITH RGB SHIFT ===
    var color = rgbShift(p, mouse, colorShift);
    
    // === ADD SCANLINES ===
    let scanline = sin(uv.y * scanlineDensity + time * 2.0);
    let scanlinePattern = 0.9 + 0.1 * scanline;
    color = color * scanlinePattern;
    
    // === DIGITAL NOISE ===
    let noise = digitalNoise(uv, time);
    color = mix(color, vec3<f32>(noise), glitchIntensity * 0.1);
    
    // === COLOR BANDING/POSTERIZATION ===
    let bands = 8.0 + (1.0 - glitchIntensity) * 24.0;
    color = floor(color * bands) / bands;
    
    // === BRIGHTNESS FLICKER ===
    let flicker = 1.0 + sin(time * 20.0) * glitchIntensity * 0.1;
    color = color * flicker;
    
    // === CHROMATIC ABERRATION AT EDGES ===
    let edgeDist = abs(uv.x - 0.5) * 2.0;
    let edgeAberration = edgeDist * glitchIntensity * 0.02;
    
    let r = textureSampleLevel(readTexture, u_sampler, clamp(p + vec2<f32>(edgeAberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(p - vec2<f32>(edgeAberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    color.r = mix(color.r, r, edgeDist * 0.5);
    color.b = mix(color.b, b, edgeDist * 0.5);
    
    // === GLITCH BARS ===
    let barHeight = 0.02;
    let barY = fract(time * 0.3);
    let inBar = step(abs(uv.y - barY), barHeight);
    
    if (inBar > 0.5 && glitchIntensity > 0.3) {
        let barShift = sin(time * 10.0) * glitchIntensity * 0.1;
        let barColor = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(barShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        color = mix(color, barColor.rgb, 0.5);
    }
    
    // === MOUSE GLOW ===
    let mouseDist = length(uv - mouse);
    let mouseGlow = exp(-mouseDist * 5.0) * glitchIntensity * 0.3;
    color = color + vec3<f32>(0.2, 0.4, 0.8) * mouseGlow;
    
    // === VIGNETTE ===
    let vignetteUV = (uv - 0.5) * 1.5;
    let vignette = 1.0 - dot(vignetteUV, vignetteUV) * 0.4;
    color = color * vignette;
    
    // Write output
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
