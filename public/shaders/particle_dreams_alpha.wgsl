// ═══════════════════════════════════════════════════════════════════════════════
//  particle_dreams_alpha.wgsl - Particle System with Alpha Trails
//  
//  RGBA Focus: Alpha channel stores particle lifetime/trail density
//  Techniques:
//    - 100+ particles with individual alpha lifecycles
//    - Trail accumulation in alpha buffer
//    - Birth/death fade in/out
//    - Alpha-based depth sorting hint
//    - Mouse attraction with alpha falloff
//  
//  Target: 4.7★ rating
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
const NUM_PARTICLES: i32 = 80;

// Hash functions
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// Smooth noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    let n = i.x + i.y * 57.0 + i.z * 113.0;
    return mix(
        mix(mix(hash3(i), hash3(i + vec3<f32>(1, 0, 0)), f.x),
            mix(hash3(i + vec3<f32>(0, 1, 0)), hash3(i + vec3<f32>(1, 1, 0)), f.x), f.y),
        mix(mix(hash3(i + vec3<f32>(0, 0, 1)), hash3(i + vec3<f32>(1, 0, 1)), f.x),
            mix(hash3(i + vec3<f32>(0, 1, 1)), hash3(i + vec3<f32>(1, 1, 1)), f.x), f.y),
        f.z
    );
}

// Particle position with lifecycle
fn particlePos(i: i32, time: f32, audioPulse: f32) -> vec4<f32> {
    let fi = f32(i);
    let seed = vec3<f32>(fi * 1.618, fi * 2.718, fi * 3.142);
    
    // Lifecycle: birth time determines age
    let birthTime = hash3(seed) * 10.0;
    let age = fract((time + birthTime) * 0.1);
    
    // Alpha lifecycle: fade in, hold, fade out
    var alpha: f32;
    if (age < 0.2) {
        alpha = age / 0.2; // Fade in
    } else if (age < 0.7) {
        alpha = 1.0; // Hold
    } else {
        alpha = 1.0 - (age - 0.7) / 0.3; // Fade out
    }
    
    // Orbital motion
    let baseAngle = fi * (2.0 * PI / f32(NUM_PARTICLES));
    let radius = 0.15 + hash3(seed + 1.0) * 0.25;
    let speed = 0.2 + hash3(seed + 2.0) * 0.5;
    
    let angle = baseAngle + time * speed + audioPulse * fi * 0.05;
    
    // Vertical oscillation
    let yOffset = sin(time * 0.5 + fi) * 0.1 * (1.0 - age * 0.5);
    
    let x = 0.5 + cos(angle) * radius * (1.0 + audioPulse * 0.3);
    let y = 0.5 + sin(angle) * radius * 0.6 + yOffset;
    
    // Size varies with age
    let size = (0.01 + hash3(seed + 3.0) * 0.02) * (1.0 - age * 0.5);
    
    return vec4<f32>(x, y, size, alpha);
}

// Particle glow with alpha
fn particleGlow(uv: vec2<f32>, particle: vec4<f32>, color: vec3<f32>) -> vec4<f32> {
    let dist = length(uv - particle.xy);
    let size = particle.z;
    let alpha = particle.w;
    
    // Soft glow with alpha
    let glow = smoothstep(size * 2.0, 0.0, dist) * alpha;
    
    // Core brightness
    let core = smoothstep(size * 0.3, 0.0, dist) * alpha;
    
    let finalRGB = color * (glow * 0.5 + core);
    let finalAlpha = glow * 0.8 + core;
    
    return vec4<f32>(finalRGB, finalAlpha);
}

// Trail accumulation from previous frame
fn accumulateTrails(uv: vec2<f32>, current: vec4<f32>, prevTex: texture_2d<f32>) -> vec4<f32> {
    let prev = textureSampleLevel(prevTex, non_filtering_sampler, uv, 0.0);
    
    // Trail decay
    let decay = 0.92;
    let trailRGB = prev.rgb * decay;
    let trailAlpha = prev.a * decay * 0.95;
    
    // Blend new particle over trail
    let finalAlpha = current.a + trailAlpha * (1.0 - current.a);
    let finalRGB = current.rgb + trailRGB * (1.0 - current.a);
    
    return vec4<f32>(finalRGB, finalAlpha);
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
    let particleCount = i32(20.0 + u.zoom_params.x * 60.0); // 20-80
    let trailPersistence = u.zoom_params.y; // 0-1
    let colorShift = u.zoom_params.z; // 0-1 hue shift
    let chaos = u.zoom_params.w; // 0-1 movement chaos
    
    let audioPulse = u.zoom_config.w;
    let mousePos = u.zoom_config.yz;
    
    // Accumulate particles
    var accumColor = vec3<f32>(0.0);
    var accumAlpha = 0.0;
    
    for (var i: i32 = 0; i < particleCount; i = i + 1) {
        let p = particlePos(i, time + chaos * hash2(vec2<f32>(f32(i), time)), audioPulse);
        
        // Mouse attraction affects position
        let toMouse = mousePos - p.xy;
        let attractedPos = p.xy + toMouse * 0.1 * audioPulse;
        p.x = attractedPos.x;
        p.y = attractedPos.y;
        
        // Color based on particle index and audio
        let hue = f32(i) / f32(particleCount) + colorShift * 0.3 + audioPulse * 0.1;
        let particleColor = vec3<f32>(
            sin(hue * 6.28) * 0.5 + 0.5,
            sin(hue * 6.28 + 2.09) * 0.5 + 0.5,
            sin(hue * 6.28 + 4.19) * 0.5 + 0.5
        );
        
        let glow = particleGlow(uv, p, particleColor);
        
        // Alpha compositing
        accumColor = glow.rgb + accumColor * (1.0 - glow.a);
        accumAlpha = glow.a + accumAlpha * (1.0 - glow.a);
    }
    
    // Accumulate trails
    var finalRGBA = vec4<f32>(accumColor, accumAlpha);
    
    // Only sample trails if persistence > 0
    if (trailPersistence > 0.01) {
        let prevUV = uv + vec2<f32>(sin(time * 0.1), cos(time * 0.1)) * 0.001;
        let withTrails = accumulateTrails(prevUV, finalRGBA, dataTextureC);
        finalRGBA = mix(finalRGBA, withTrails, trailPersistence);
    }
    
    // Add background with alpha blending
    let bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let finalColor = finalRGBA.rgb + bgColor.rgb * (1.0 - finalRGBA.a) * 0.3;
    let finalAlpha = max(finalRGBA.a, bgColor.a * 0.3);
    
    // HDR tone mapping
    let toneMapped = finalColor / (1.0 + finalColor * 0.5);
    
    // Vignette affects alpha too
    let vignette = 1.0 - length(uv - 0.5) * 0.4;
    
    textureStore(writeTexture, coord, vec4<f32>(toneMapped * vignette, finalAlpha * vignette));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    // Store RGBA for next frame's trails
    textureStore(dataTextureA, coord, vec4<f32>(finalRGBA.rgb, finalRGBA.a * 0.95));
}
