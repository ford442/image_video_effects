// ═══════════════════════════════════════════════════════════════════════════════
//  bio_lenia_continuous.wgsl - Continuous Cellular Automata (Lenia)
//  
//  Agent: Algorithmist + Interactivist
//  Techniques:
//    - Lenia continuous CA (smoothLife-like)
//    - Multiple kernel radii
//    - Growth function with bell curve
//    - Mouse-DOWN gated spawn (fixed from stuck ripple-count gate)
//    - Audio-reactive growth parameters (real mids -> slow growthCenter "seasons")
//    - Second competing species in dataTextureA.g with cross-feeding inhibition
//    - Click seed bombs from the ripples[] ring buffer (species-B colonies)
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

// Bell curve function for Lenia growth
fn bell(x: f32, m: f32, s: f32) -> f32 {
    return exp(-pow((x - m) / s, 2.0) / 2.0);
}

// Smooth step
fn smoothStep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// Lenia kernel (smooth ring)
fn kernel(r: f32, radius: f32) -> f32 {
    if (r > radius) {
        return 0.0;
    }
    // Ring kernel: peaks at r = radius/2
    let peak = radius * 0.5;
    return bell(r, peak, radius * 0.15);
}

// Growth function for Lenia
fn growth(neighborhood: f32, growthCenter: f32, growthWidth: f32) -> f32 {
    return bell(neighborhood, growthCenter, growthWidth) * 2.0 - 1.0;
}

// Sample previous state of species A (red channel of packed feedback)
fn sampleState(uv: vec2<f32>, tex: texture_2d<f32>) -> f32 {
    return textureSampleLevel(tex, non_filtering_sampler, uv, 0.0).r;
}

// Sample previous state of species B (green channel of packed feedback)
fn sampleStateB(uv: vec2<f32>, tex: texture_2d<f32>) -> f32 {
    return textureSampleLevel(tex, non_filtering_sampler, uv, 0.0).g;
}

// Pseudo-random
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// HSV to RGB helper
fn hsv2rgb(hue: f32, sat: f32, val: f32) -> vec3<f32> {
    let c = val * sat;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = val - c;

    var rgb: vec3<f32>;
    let h = hue * 6.0;
    if (h < 1.0) {
        rgb = vec3<f32>(c, x, 0.0);
    } else if (h < 2.0) {
        rgb = vec3<f32>(x, c, 0.0);
    } else if (h < 3.0) {
        rgb = vec3<f32>(0.0, c, x);
    } else if (h < 4.0) {
        rgb = vec3<f32>(0.0, x, c);
    } else if (h < 5.0) {
        rgb = vec3<f32>(x, 0.0, c);
    } else {
        rgb = vec3<f32>(c, 0.0, x);
    }

    return rgb + m;
}

// Species A color: biological green-to-yellow palette
fn leniaColor(value: f32, time: f32) -> vec3<f32> {
    let hue = 0.25 + value * 0.15 + sin(time * 0.1) * 0.05;
    let sat = 0.6 + value * 0.4;
    let val = 0.3 + value * 0.7;
    return hsv2rgb(hue, sat, val);
}

// Species B color: cool magenta/violet palette so colonies visibly compete
fn leniaColorB(value: f32, time: f32) -> vec3<f32> {
    let hue = 0.78 + value * 0.12 + sin(time * 0.07) * 0.04;
    let sat = 0.55 + value * 0.45;
    let val = 0.25 + value * 0.75;
    return hsv2rgb(hue, sat, val);
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
    let invRes = 1.0 / resolution;
    
    // ── Parameters (slider contract: zoom_params.x/y/z/w) ───────────────────
    let radius = 5.0 + u.zoom_params.x * 15.0;           // 5-20 pixel radius
    let growthCenter = 0.15 + u.zoom_params.y * 0.25;    // 0.15-0.4
    let growthWidth = 0.01 + u.zoom_params.z * 0.04;     // 0.01-0.05
    let dt = 0.1 + u.zoom_params.w * 0.2;                // 0.1-0.3 time step
    
    // Species B: same bell() family, tuned to a smaller, hungrier niche
    let radiusB = radius * 0.6;                          // tighter kernel
    let growthCenterB = growthCenter + 0.06;             // prefers denser crowds
    let growthWidthB = growthWidth * 1.3;                // more tolerant
    let dtB = dt * 0.85;                                 // slightly slower metabolism
    
    // ── Interaction & audio truth ───────────────────────────────────────────
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;                     // 1.0 only while held
    let audioMids = clamp(plasmaBuffer[0].y, 0.0, 1.0);  // real mids
    
    // Audio "seasons": slow wobble of the growth center driven by mids.
    // Classic Lenia modulation - shifts the whole ecosystem's climate gently.
    let season = sin(time * 0.23) * 0.5 + 0.5;
    let growthCenterA = growthCenter + (audioMids - 0.5) * 0.08 * season;
    
    // ── Sample current state from dataTextureC (feedback) ───────────────────
    let currentState = sampleState(uv, dataTextureC);
    let currentStateB = sampleStateB(uv, dataTextureC);
    
    // ── Neighborhood integral (O(r^2) kernel loop - expensive by design) ────
    var neighborhood = 0.0;
    var neighborhoodB = 0.0;
    var kernelSum = 0.0;
    var kernelSumB = 0.0;
    let r = i32(radius);
    
    for (var dy: i32 = -r; dy <= r; dy = dy + 1) {
        for (var dx: i32 = -r; dx <= r; dx = dx + 1) {
            let d = sqrt(f32(dx * dx + dy * dy));
            if (d > radius) {
                continue;
            }
            
            let sampleUV = uv + vec2<f32>(f32(dx), f32(dy)) * invRes;
            let k = kernel(d, radius);
            neighborhood += sampleState(sampleUV, dataTextureC) * k;
            kernelSum += k;
            // Species B shares the sample tap, weighted by its own kernel
            let kB = kernel(d, radiusB);
            neighborhoodB += sampleStateB(sampleUV, dataTextureC) * kB;
            kernelSumB += kB;
        }
    }
    
    // Normalize
    if (kernelSum > 0.0) {
        neighborhood /= kernelSum;
    }
    if (kernelSumB > 0.0) {
        neighborhoodB /= kernelSumB;
    }
    
    // ── Growth + cross-feeding competition ──────────────────────────────────
    let g = growth(neighborhood, growthCenterA, growthWidth);
    let gB = growth(neighborhoodB, growthCenterB, growthWidthB);
    
    // Update species A (primary state layout preserved verbatim)
    var newState = currentState + dt * g;
    newState = clamp(newState, 0.0, 1.0);
    
    // Species B update: dense A colonies inhibit B (resource competition),
    // while sparse A edges slightly fertilize B (mutualist fringe).
    let inhibition = smoothStep(0.45, 0.85, currentState) * 0.35;
    let fertilize = smoothStep(0.05, 0.25, currentState)
                  * (1.0 - smoothStep(0.25, 0.5, currentState)) * 0.15;
    var newStateB = currentStateB + dtB * (gB - inhibition + fertilize);
    newStateB = clamp(newStateB, 0.0, 1.0);
    
    // Dense B also grazes A back a touch, so fronts visibly swap territory
    newState = clamp(newState - smoothStep(0.5, 0.9, currentStateB) * dt * 0.25, 0.0, 1.0);
    
    // ── Mouse-DOWN spawn (fixed gate: was stuck-on ripple count) ────────────
    let toMouse = length(uv - mousePos);
    if (toMouse < 0.05 && mouseDown > 0.5) {
        // Soft radial species-A brush instead of a hard overwrite
        let brush = 1.0 - smoothStep(0.0, 0.05, toMouse);
        newState = clamp(newState + brush * 0.5, 0.0, 1.0);
    }
    
    // ── Click seed bombs: live ripples drop species-B blobs ─────────────────
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 3.0) {
            continue;
        }
        let blobDist = length(uv - ripple.xy);
        let blobRadius = 0.03 + age * 0.015;             // bomb swells as it decays
        if (blobDist < blobRadius) {
            let decay = 1.0 - age / 3.0;                 // fades with ripple age
            let blob = (1.0 - smoothStep(0.0, blobRadius, blobDist)) * decay;
            newStateB = clamp(newStateB + blob * 0.8, 0.0, 1.0);
        }
    }
    
    // ── Random seeding if very dead (mids boost spore rain) ─────────────────
    if (newState < 0.01 && rand(uv + time) < 0.001 * (1.0 + audioMids)) {
        newState = rand(uv + time * 2.0);
    }
    if (newStateB < 0.01 && rand(uv * 1.7 - time) < 0.0004 * (1.0 + audioMids)) {
        newStateB = rand(uv - time * 1.3);
    }
    
    // ── Color mapping: two species blended by local dominance ───────────────
    var color = leniaColor(newState, time);
    let colorB = leniaColorB(newStateB, time);
    let dominance = smoothStep(0.15, 0.6, newStateB) * (1.0 - smoothStep(0.3, 0.8, newState));
    color = mix(color, colorB, clamp(dominance + newStateB * 0.5, 0.0, 1.0));
    
    // Add glow around living cells (A warm, B cool)
    let glow = smoothStep(0.2, 0.8, newState) * 0.5;
    let glowB = smoothStep(0.2, 0.8, newStateB) * 0.5;
    color += vec3<f32>(0.4, 0.8, 0.3) * glow;
    color += vec3<f32>(0.5, 0.3, 0.9) * glowB;
    
    // Tone map (display only - sim state below is never tonemapped)
    color = color / (1.0 + color);
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(max(newState, newStateB), 0.0, 0.0, 1.0));
    
    // Store state for next frame: A in .r (contract), B in .g (new species)
    textureStore(dataTextureA, coord, vec4<f32>(newState, newStateB, 0.0, 1.0));
}
