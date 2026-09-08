// ═══════════════════════════════════════════════════════════════════
//  Fractal Kernel
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: fractal-shaped-kernel
//  Complexity: High
//  Upgraded: 2026-09-08
//  Ideas: boundary vs interior kernel weight; distance-estimator glint
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Accumulated color from fractal-shaped kernel samples
//    Alpha: Fractal iteration count at sample position (how "deep" into
//           the fractal set each pixel is). This creates a natural depth
//           map for downstream effects.
//
//  Uses Mandelbrot set membership as the kernel shape — pixels "inside"
//  the fractal are sampled, others are not. Creates alien, mathematically
//  beautiful blur patterns.
//
//  MOUSE INTERACTIVITY:
//    Mouse position warps the Mandelbrot center, creating live morphing
//    of the fractal kernel. Ripples inject Julia-set perturbations.
//
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn mandelbrotMember(c: vec2<f32>, maxIter: i32) -> f32 {
    var z = vec2<f32>(0.0);
    var iter = 0;
    for (var i = 0; i < maxIter; i++) {
        let x2 = z.x * z.x;
        let y2 = z.y * z.y;
        if (x2 + y2 > 4.0) {
            iter = i;
            break;
        }
        z = vec2<f32>(x2 - y2 + c.x, 2.0 * z.x * z.y + c.y);
        iter = i;
    }
    // Smooth iteration count
    let smoothIter = f32(iter) + 1.0 - log2(log2(dot(z, z))) / log2(2.0);
    return clamp(smoothIter / f32(maxIter), 0.0, 1.0);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let pixel = vec2<i32>(global_id.xy);
    
    // Parameters
    let kernelRadius = mix(0.02, 0.08, u.zoom_params.x) * (1.0 + bass * 0.2);
    let fractalZoom = mix(0.5, 4.0, u.zoom_params.y);
    let maxIter = i32(mix(10.0, 40.0, u.zoom_params.z));
    let mouseInfluence = u.zoom_params.w;
    
    // Mouse warps the Mandelbrot center
    let fractalCenter = vec2<f32>(
        mix(-0.5, mousePos.x - 0.5, mouseInfluence * 0.5),
        mix(0.0, mousePos.y - 0.5, mouseInfluence * 0.5)
    );
    
    // Ripple Julia perturbations
    var juliaC = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-rDist * rDist * 20.0) * (1.0 - rElapsed / 3.0);
            juliaC += vec2<f32>(cos(rElapsed * 3.0), sin(rElapsed * 3.0)) * wave * 0.3;
        }
    }
    
    // Build fractal-shaped convolution kernel
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    var avgFractalDepth = 0.0;
    
    let sampleSteps = 7; // 7x7 grid
    for (var dy = -sampleSteps; dy <= sampleSteps; dy++) {
        for (var dx = -sampleSteps; dx <= sampleSteps; dx++) {
            let relX = f32(dx) / f32(sampleSteps) * kernelRadius;
            let relY = f32(dy) / f32(sampleSteps) * kernelRadius;
            
            // Map to fractal space
            let c = vec2<f32>(
                fractalCenter.x + relX * fractalZoom,
                fractalCenter.y + relY * fractalZoom
            ) + juliaC;
            
            let fractalVal = mandelbrotMember(c, maxIter);
            let boundary = 4.0 * fractalVal * (1.0 - fractalVal);
            let weight = pow(fractalVal, 2.0) * 0.45 + boundary * 0.7 + 0.05;
            let glint = pow(clamp(boundary, 0.0, 1.0), 6.0);
            let sampleUV = clamp(uv + vec2<f32>(f32(dx), f32(dy)) * pixelSize * (kernelRadius / 0.08), vec2<f32>(0.0), vec2<f32>(1.0));
            let sample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
            accumColor += (sample + vec3<f32>(glint) * 0.35 * (0.5 + treble)) * weight;
            accumWeight += weight;
            avgFractalDepth += fractalVal;
        }
    }
    
    var result = vec3<f32>(0.0);
    var fractalDepth = 0.0;
    if (accumWeight > 0.001) {
        result = accumColor / accumWeight;
        fractalDepth = avgFractalDepth / accumWeight;
    }
    
    // Psychedelic colorization based on fractal depth
    let depthColor = palette(fractalDepth + time * 0.05, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    result = mix(result, result * depthColor * 2.0, fractalDepth * 0.4);
    result = acesToneMap(result * (1.0 + mids * 0.2));
    
    let packed = vec4<f32>(result, fractalDepth);
    textureStore(writeTexture, pixel, packed);
    textureStore(dataTextureA, pixel, packed);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
