// ═══════════════════════════════════════════════════════════════════
//  Multi-Fractal Compositor
//  Category: generative
//  Features: advanced-hybrid, mandelbrot, julia, burning-ship, smooth-blend
//  Complexity: High
//  Chunks From: gen_grok41_mandelbrot.wgsl, gen_julia_set.wgsl, gen_grid
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Smooth morphing between fractal types
//  Mandelbrot, Julia, Burning Ship, Newton fractal
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

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: palette ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ═══ MANDELBROT ═══
fn mandelbrot(c: vec2<f32>, maxIter: i32) -> vec2<f32> {
    var z = vec2<f32>(0.0);
    var iter = 0;
    
    for (var i = 0; i < maxIter; i++) {
        let x = z.x * z.x - z.y * z.y + c.x;
        let y = 2.0 * z.x * z.y + c.y;
        z = vec2<f32>(x, y);
        
        if (dot(z, z) > 4.0) {
            iter = i;
            break;
        }
        iter = i;
    }
    
    // Smooth iteration count
    let smoothIter = f32(iter) + 1.0 - log2(log2(length(z)));
    return vec2<f32>(smoothIter, length(z));
}

// ═══ JULIA SET ═══
fn juliaSet(z: vec2<f32>, c: vec2<f32>, maxIter: i32) -> vec2<f32> {
    var zv = z;
    var iter = 0;
    
    for (var i = 0; i < maxIter; i++) {
        let x = zv.x * zv.x - zv.y * zv.y + c.x;
        let y = 2.0 * zv.x * zv.y + c.y;
        zv = vec2<f32>(x, y);
        
        if (dot(zv, zv) > 4.0) {
            iter = i;
            break;
        }
        iter = i;
    }
    
    let smoothIter = f32(iter) + 1.0 - log2(log2(length(zv)));
    return vec2<f32>(smoothIter, length(zv));
}

// ═══ BURNING SHIP ═══
fn burningShip(c: vec2<f32>, maxIter: i32) -> vec2<f32> {
    var z = vec2<f32>(0.0);
    var iter = 0;
    
    for (var i = 0; i < maxIter; i++) {
        let x = z.x * z.x - z.y * z.y + c.x;
        let y = 2.0 * abs(z.x * z.y) + c.y;
        z = vec2<f32>(abs(x), abs(y));
        
        if (dot(z, z) > 4.0) {
            iter = i;
            break;
        }
        iter = i;
    }
    
    let smoothIter = f32(iter) + 1.0 - log2(log2(length(z)));
    return vec2<f32>(smoothIter, length(z));
}

// ═══ NEWTON FRACTAL (z^3 - 1 = 0) ═══
fn newtonFractal(z: vec2<f32>, maxIter: i32) -> vec2<f32> {
    var zv = z;
    var iter = 0;
    
    for (var i = 0; i < maxIter; i++) {
        // f(z) = z^3 - 1
        // f'(z) = 3z^2
        let z2 = vec2<f32>(zv.x * zv.x - zv.y * zv.y, 2.0 * zv.x * zv.y);
        let z3 = vec2<f32>(z2.x * zv.x - z2.y * zv.y, z2.x * zv.y + z2.y * zv.x);
        
        let fz = vec2<f32>(z3.x - 1.0, z3.y);
        let fzp = vec2<f32>(3.0 * z2.x, 3.0 * z2.y);
        
        // Newton iteration: z = z - f(z)/f'(z)
        let denom = fzp.x * fzp.x + fzp.y * fzp.y;
        if (denom < 0.0001) { break; }
        
        let div = vec2<f32>(
            (fz.x * fzp.x + fz.y * fzp.y) / denom,
            (fz.y * fzp.x - fz.x * fzp.y) / denom
        );
        zv = zv - div;
        
        if (dot(zv - vec2<f32>(1.0, 0.0), zv - vec2<f32>(1.0, 0.0)) < 0.0001) {
            iter = i;
            break;
        }
        iter = i;
    }
    
    return vec2<f32>(f32(iter), length(zv));
}

// ═══ DOMAIN WARP ═══
fn domainWarp(uv: vec2<f32>, time: f32) -> vec2<f32> {
    let warp = vec2<f32>(
        sin(uv.y * 3.0 + time) * 0.1,
        cos(uv.x * 3.0 + time * 0.7 * audioReactivity) * 0.1
    );
    return uv + warp;
}

// ═══ MAIN ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.config.y;
    let audioBass = u.config.y * 1.2;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioOverall * 0.5;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let zoom = pow(2.0, mix(0.0, 8.0, u.zoom_params.x)); // x: Zoom level
    let maxIter = i32(mix(30.0, 200.0, u.zoom_params.y)); // y: Iteration count
    let domainWarp = mix(0.0, 0.2, u.zoom_params.z);     // z: Domain warp amount
    let fractalMix = u.zoom_params.w;                     // w: Fractal blend
    
    // Map to fractal coordinate space
    let aspect = resolution.x / resolution.y;
    let center = vec2<f32>(-0.5, 0.0);
    let c = (uv - 0.5) * 4.0 / zoom + center;
    
    // Domain warping
    let warpedC = domainWarp(c, time) * (1.0 + domainWarp);
    
    // Determine which two fractals to blend
    let typeA = i32(fractalMix * 4.0) % 4;
    let typeB = (typeA + 1) % 4;
    let blend = fract(fractalMix * 4.0);
    
    // Calculate both fractals
    var resultA = vec2<f32>(0.0);
    var resultB = vec2<f32>(0.0);
    
    // Julia constant (animated)
    let juliaC = vec2<f32>(cos(time * 0.3 * audioReactivity) * 0.8, sin(time * 0.5 * audioReactivity) * 0.8);
    
    // Type A
    switch(typeA) {
        case 0: { resultA = mandelbrot(warpedC, maxIter); }
        case 1: { resultA = juliaSet(warpedC * 2.0, juliaC, maxIter); }
        case 2: { resultA = burningShip(warpedC, maxIter); }
        case 3: { resultA = newtonFractal(warpedC * 2.0, maxIter / 2); }
        default: { resultA = mandelbrot(warpedC, maxIter); }
    }
    
    // Type B
    switch(typeB) {
        case 0: { resultB = mandelbrot(warpedC, maxIter); }
        case 1: { resultB = juliaSet(warpedC * 2.0, juliaC, maxIter); }
        case 2: { resultB = burningShip(warpedC, maxIter); }
        case 3: { resultB = newtonFractal(warpedC * 2.0, maxIter / 2); }
        default: { resultB = juliaSet(warpedC * 2.0, juliaC, maxIter); }
    }
    
    // Smooth interpolation of iteration counts
    let smoothIter = mix(resultA.x, resultB.x, blend);
    let trap = mix(resultA.y, resultB.y, blend);
    
    // Color from iteration count + orbit trap
    let colorIter = smoothIter / f32(maxIter);
    
    let fractalColor = palette(colorIter + time * 0.05 * audioReactivity,
        vec3<f32>(0.5, 0.5, 0.5),
        vec3<f32>(0.5, 0.5, 0.5),
        vec3<f32>(1.0, 1.0, 0.8),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    
    // Add orbit trap coloring
    let trapColor = vec3<f32>(trap * 0.5, trap * 0.3, trap * 0.8);
    
    var color = fractalColor + trapColor * 0.3;
    
    // Blend with original image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    color = mix(baseColor * 0.2, color, 0.9);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.85, 1.0, colorIter);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
