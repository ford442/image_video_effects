// ═══════════════════════════════════════════════════════════════════════════════
//  ink_dispersion_alpha.wgsl - Ink in Water with Density-Based Alpha
//  
//  RGBA Focus: Alpha = ink density/concentration (thick = opaque, thin = transparent)
//  Techniques:
//    - Navier-Stokes approximated velocity field
//    - Advection-diffusion for ink transport
//    - Color mixing with alpha blending
//    - Multiple ink drops with different colors
//    - Mouse creates new ink sources
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

// Hash
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// Curl noise for divergence-free velocity field
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    
    let n = vec2<f32>(
        hash3(vec3<f32>(p, time * 0.1)),
        hash3(vec3<f32>(p + 10.0, time * 0.1))
    );
    
    let dx = vec2<f32>(eps, 0.0);
    let dy = vec2<f32>(0.0, eps);
    
    let dpdx = (hash3(vec3<f32>(p + dx, time * 0.1)) - hash3(vec3<f32>(p - dx, time * 0.1))) / (2.0 * eps);
    let dpdy = (hash3(vec3<f32>(p + dy, time * 0.1)) - hash3(vec3<f32>(p - dy, time * 0.1))) / (2.0 * eps);
    
    return vec2<f32>(dpdy, -dpdx);
}

// Sample ink from previous frame
fn sampleInk(uv: vec2<f32>, tex: texture_2d<f32>) -> vec4<f32> {
    return textureSampleLevel(tex, non_filtering_sampler, uv, 0.0);
}

// Advect ink by velocity field
fn advectInk(uv: vec2<f32>, velocity: vec2<f32>, dt: f32, tex: texture_2d<f32>) -> vec4<f32> {
    let backUV = uv - velocity * dt;
    return sampleInk(backUV, tex);
}

// Diffuse ink (blur)
fn diffuseInk(uv: vec2<f32>, invRes: vec2<f32>, tex: texture_2d<f32>) -> vec4<f32> {
    var accum = vec4<f32>(0.0);
    let kernel = array<f32, 9>(0.05, 0.1, 0.05, 0.1, 0.4, 0.1, 0.05, 0.1, 0.05);
    let offsets = array<vec2<f32>, 9>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(0.0, -1.0), vec2<f32>(1.0, -1.0),
        vec2<f32>(-1.0,  0.0), vec2<f32>(0.0,  0.0), vec2<f32>(1.0,  0.0),
        vec2<f32>(-1.0,  1.0), vec2<f32>(0.0,  1.0), vec2<f32>(1.0,  1.0)
    );
    
    for (var i: i32 = 0; i < 9; i = i + 1) {
        accum += sampleInk(uv + offsets[i] * invRes, tex) * kernel[i];
    }
    
    return accum;
}

// Ink drop color based on type
fn inkColor(type: i32) -> vec3<f32> {
    switch(type % 6) {
        case 0: { return vec3<f32>(0.1, 0.1, 0.8); } // Blue
        case 1: { return vec3<f32>(0.8, 0.1, 0.1); } // Red
        case 2: { return vec3<f32>(0.1, 0.6, 0.2); } // Green
        case 3: { return vec3<f32>(0.7, 0.2, 0.7); } // Purple
        case 4: { return vec3<f32>(0.9, 0.5, 0.1); } // Orange
        case 5: { return vec3<f32>(0.1, 0.5, 0.7); } // Cyan
        default: { return vec3<f32>(0.5); }
    }
}

// Mix two inks with alpha compositing
fn mixInks(inkA: vec4<f32>, inkB: vec4<f32>) -> vec4<f32> {
    // Standard alpha compositing
    let outAlpha = inkB.a + inkA.a * (1.0 - inkB.a);
    let outRGB = inkB.rgb * inkB.a + inkA.rgb * inkA.a * (1.0 - inkB.a);
    
    if (outAlpha > 0.001) {
        return vec4<f32>(outRGB / outAlpha, outAlpha);
    }
    return vec4<f32>(0.0);
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
    let invRes = 1.0 / resolution;
    
    // Parameters
    let diffusion = 0.1 + u.zoom_params.x * 0.4; // 0.1-0.5
    let viscosity = u.zoom_params.y; // Affects velocity smoothness
    let inkIntensity = 0.5 + u.zoom_params.z * 0.5; // 0.5-1.0
    let reaction = u.zoom_params.w; // Chemical reaction mixing
    
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    let mouseClick = u.config.y;
    
    // Velocity field (curl noise for divergence-free flow)
    let velocity = curlNoise(uv * 2.0, time) * (1.0 - viscosity) + 
                   curlNoise(uv * 4.0, time * 1.5) * viscosity * 0.5;
    
    // Audio adds turbulence
    velocity += curlNoise(uv * 8.0, time * 2.0) * audioPulse * 0.3;
    
    // Get previous ink state
    let prevInk = sampleInk(uv, dataTextureC);
    
    // Advect ink
    var ink = advectInk(uv, velocity, 0.016, dataTextureC);
    
    // Apply diffusion
    let diffused = diffuseInk(uv, invRes, dataTextureC);
    ink = mix(ink, diffused, diffusion * 0.1);
    
    // Decay over time
    ink.a *= 0.995;
    
    // Spawn new ink from mouse
    let toMouse = length(uv - mousePos);
    if (toMouse < 0.05 && mouseClick > 0.0) {
        let inkType = i32(mouseClick) % 6;
        let newColor = inkColor(inkType);
        let density = smoothstep(0.05, 0.0, toMouse) * inkIntensity;
        let newInk = vec4<f32>(newColor, density);
        ink = mixInks(ink, newInk);
    }
    
    // Random ink drops
    if (hash3(vec3<f32>(floor(time * 2.0), floor(uv * 10.0))) < 0.001 * (1.0 + audioPulse)) {
        let dropPos = vec2<f32>(hash2(vec2<f32>(time, 0.0)), hash2(vec2<f32>(0.0, time)));
        let toDrop = length(uv - dropPos);
        if (toDrop < 0.03) {
            let dropType = i32(time * 10.0) % 6;
            let dropInk = vec4<f32>(inkColor(dropType), smoothstep(0.03, 0.0, toDrop) * 0.8);
            ink = mixInks(ink, dropInk);
        }
    }
    
    // Chemical reaction mixing (optional)
    if (reaction > 0.1 && ink.a > 0.1) {
        // Check neighbors for different colors
        let right = sampleInk(uv + vec2<f32>(invRes.x, 0.0), dataTextureC);
        let left = sampleInk(uv - vec2<f32>(invRes.x, 0.0), dataTextureC);
        
        // Color blending when different inks meet
        if (right.a > 0.1 && length(right.rgb - ink.rgb) > 0.2) {
            ink.rgb = mix(ink.rgb, right.rgb, reaction * 0.1);
        }
    }
    
    // Render to screen
    // Water background
    let waterColor = vec3<f32>(0.9, 0.95, 1.0);
    
    // Alpha blend ink over water
    var finalRGB = mix(waterColor, ink.rgb, ink.a);
    var finalAlpha = ink.a;
    
    // Caustic-like light through ink
    if (ink.a > 0.05) {
        let caustic = sin(uv.x * 50.0 + time) * sin(uv.y * 50.0 + time * 1.3);
        finalRGB += vec3<f32>(0.1, 0.15, 0.2) * caustic * ink.a * 0.2;
    }
    
    // Tone mapping
    finalRGB = finalRGB / (1.0 + finalRGB * 0.2);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    finalRGB *= vignette;
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    // Store ink state (RGBA) for next frame
    textureStore(dataTextureA, coord, ink);
}
