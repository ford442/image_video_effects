// ═══════════════════════════════════════════════════════════════════
//  Fractal Kernel
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: fractal-shaped-kernel
//  Complexity: High
//  Upgraded: 2026-09-08, 2026-11-19
//  Ideas: boundary vs interior kernel weight; distance-estimator glint; circle orbit trap (§12.2E); defocus-scaled aperture (CoC from depth under pointer)
//  A packing: ACES display RGBA; alpha = mean fractal membership 0..1
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
//    The depth under the pointer is also the focal plane: the aperture
//    (same fractal shape) grows with defocus away from it.
//
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Circle orbit trap (Idea 1): radius² and how many leading orbit points are trapped.
// |z|² is already computed by the escape test. Only the first TRAP_ITERS points are trapped:
// over the whole orbit the rings are denser than the 15x15 tap lattice can resolve (aliasing).
const TRAP_R2: f32 = 0.1225;
const TRAP_ITERS: i32 = 4;

// Returns (smooth membership 0..1, orbit-trap distance).
fn mandelbrotMember(c: vec2<f32>, maxIter: i32) -> vec2<f32> {
    var z = vec2<f32>(0.0);
    var iter = 0;
    var trap = 1.0e9;
    var i = 0;
    // ── Idea 1: circle orbit trap (§12.2E) — nearest approach of the first orbit points to |z|² = TRAP_R2.
    for (; i < min(TRAP_ITERS, maxIter); i++) {
        let x2 = z.x * z.x;
        let y2 = z.y * z.y;
        if (x2 + y2 > 4.0) {
            iter = i;
            break;
        }
        trap = min(trap, abs(x2 + y2 - TRAP_R2));
        z = vec2<f32>(x2 - y2 + c.x, 2.0 * z.x * z.y + c.y);
        iter = i;
    }
    // Escape-time loop: HEAD body, unchanged (continues at the same i, so an early break repeats harmlessly).
    for (; i < maxIter; i++) {
        let x2 = z.x * z.x;
        let y2 = z.y * z.y;
        if (x2 + y2 > 4.0) {
            iter = i;
            break;
        }
        z = vec2<f32>(x2 - y2 + c.x, 2.0 * z.x * z.y + c.y);
        iter = i;
    }
    // Smooth iteration count — only meaningful for escaped orbits. HEAD also ran it on interior
    // points where dot(z,z) < 1 makes log2(log2(·)) NaN on real hardware; interior is exactly 1.0.
    let d = dot(z, z);
    let escaped = d > 4.0;
    let smoothEsc = f32(iter) + 1.0 - log2(log2(max(d, 4.0))) / log2(2.0);
    let smoothIter = select(f32(maxIter), smoothEsc, escaped);
    return vec2<f32>(clamp(smoothIter / f32(maxIter), 0.0, 1.0), trap);
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
    
    // ── Idea 2: defocus-scaled aperture. The tap footprint (not the fractal window) grows with
    // |depth − depth@pointer|, so the focal plane keeps the HEAD blur and the rest blurs with the
    // same fractal aperture, up to 1.75x wider (wider would lattice the 15x15 taps). Flat/absent depth => coc = 1 (identical to HEAD).
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let focusDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(mousePos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let coc = 1.0 + 0.75 * smoothstep(0.05, 0.6, abs(depth - focusDepth));

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
            
            let member = mandelbrotMember(c, maxIter);
            let fractalVal = member.x;
            let boundary = 4.0 * fractalVal * (1.0 - fractalVal);
            // Idea 1: ring weighting from the orbit trap (energy-conserving: lands in accumWeight)
            let trapRing = 0.55 + 0.9 * exp(-14.0 * member.y);
            let weight = (pow(fractalVal, 2.0) * 0.45 + boundary * 0.7 + 0.05) * trapRing;
            let glint = pow(clamp(boundary, 0.0, 1.0), 6.0);
            let sampleUV = clamp(uv + vec2<f32>(f32(dx), f32(dy)) * pixelSize * (kernelRadius / 0.08) * coc, vec2<f32>(0.0), vec2<f32>(1.0));
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
        // mean membership over the 15x15 taps (HEAD divided by the weight sum -> alpha up to ~2)
        fractalDepth = avgFractalDepth / f32((2 * sampleSteps + 1) * (2 * sampleSteps + 1));
    }
    
    // Psychedelic colorization based on fractal depth
    let depthColor = palette(fractalDepth + time * 0.05, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    result = mix(result, result * depthColor * 2.0, fractalDepth * 0.4);
    result = acesToneMap(result * (1.0 + mids * 0.2));
    
    let packed = vec4<f32>(result, fractalDepth);
    textureStore(writeTexture, pixel, packed);
    textureStore(dataTextureA, pixel, packed);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
