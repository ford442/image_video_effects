// ═══════════════════════════════════════════════════════════════════════════════
//  gen_quantum_foam.wgsl - Quantum Foam Entanglement Shader
//  
//  Agent: Algorithmist + Visualist (Batch 18 upgrade)
//  Techniques:
//    - Quantum fluctuation simulation (virtual particle pairs)
//    - Entanglement visualization (correlated particle networks)
//    - HDR volumetric glow with chromatic dispersion
//    - Temporal coherence for smooth evolution
//    - Honest audio reactivity (plasmaBuffer bass + per-bin FFT)
//    - Entanglement strikes (click shockwaves perturbing the web field)
//    - Spring-dampered vacuum polarity warp (extraBuffer[133..136])
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
const PHI: f32 = 1.61803398875;

// extraBuffer persistent state slots (safe zone [133..255] only)
const WARP_POS_X: i32 = 133;
const WARP_POS_Y: i32 = 134;
const WARP_VEL_X: i32 = 135;
const WARP_VEL_Y: i32 = 136;
const WARP_TIME: i32 = 137;

// Hash functions
fn hash3(p: vec3<f32>) -> f32 {
    var q = fract(p * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Smooth noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    return mix(
        mix(
            mix(hash3(i), hash3(i + vec3<f32>(1, 0, 0)), f.x),
            mix(hash3(i + vec3<f32>(0, 1, 0)), hash3(i + vec3<f32>(1, 1, 0)), f.x),
            f.y
        ),
        mix(
            mix(hash3(i + vec3<f32>(0, 0, 1)), hash3(i + vec3<f32>(1, 0, 1)), f.x),
            mix(hash3(i + vec3<f32>(0, 1, 1)), hash3(i + vec3<f32>(1, 1, 1)), f.x),
            f.y
        ),
        f.z
    );
}

// FBM for quantum foam texture
fn fbm(p: vec3<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Quantum foam - particle pair fluctuations
fn quantumFoam(uv: vec2<f32>, time: f32, scale: f32) -> vec3<f32> {
    let p = vec3<f32>(uv * scale, time * 0.5);
    
    // Virtual particle pairs
    let foam = fbm(p, 4);
    let foam2 = fbm(p * 2.0 + vec3<f32>(100.0), 3);
    
    // Entanglement correlations
    let correlation = sin(foam * PI * 4.0 + time) * cos(foam2 * PI * 3.0);
    
    // Energy density (vacuum fluctuations)
    let energy = pow(abs(correlation), 0.5) * 2.0;
    
    // Chromatic dispersion based on energy
    let r = energy * (1.0 + 0.3 * sin(time * 2.0));
    let g = energy * (0.8 + 0.2 * cos(time * 1.5));
    let b = energy * (1.2 + 0.4 * sin(time * 2.5 + 1.0));
    
    return vec3<f32>(r, g, b);
}

// Entanglement web - connecting correlated regions
fn entanglementWeb(uv: vec2<f32>, time: f32, density: f32) -> f32 {
    var web = 0.0;
    let numConnections = i32(density * 20.0);
    
    for (var i: i32 = 0; i < numConnections; i = i + 1) {
        let fi = f32(i);
        let seed = vec2<f32>(fi * 1.618, fi * 2.718);
        let p1 = vec2<f32>(
            hash2(seed) + sin(time * 0.3 + fi) * 0.2,
            hash2(seed + 10.0) + cos(time * 0.4 + fi) * 0.2
        );
        let p2 = vec2<f32>(
            hash2(seed + 20.0) + sin(time * 0.35 + fi + PI) * 0.2,
            hash2(seed + 30.0) + cos(time * 0.45 + fi + PI) * 0.2
        );
        
        // Distance to line segment
        let pa = uv - p1;
        let ba = p2 - p1;
        let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        let dist = length(pa - ba * h);
        
        // Entanglement strength (thicker where correlated)
        let strength = hash2(seed + 50.0);
        web += smoothstep(0.01 + strength * 0.02, 0.0, dist) * strength;
    }
    
    return web;
}

// Tone mapping
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<u32>(global_id.xy);
    let coordI = vec2<i32>(global_id.xy);
    
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 5.0; // Fast motion upgrade
    
    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // ═══ SLIDER WIRING (saved-preset contract: ids/defaults unchanged) ═══
    //   Foam Scale      -> fbm domain scale of quantumFoam (3..12)
    //   Web Density     -> entanglement connection count ceiling (0..1)
    //   Glow Intensity  -> volumetric glow accumulation gain (0..1.4)
    //   Evolution Speed -> vacuum fluctuation time rate (0.2..1.5)
    let foamScale = 3.0 + u.zoom_params.x * 9.0;
    let webDensity = u.zoom_params.y;
    let glowGain = u.zoom_params.z * 1.4;
    let evolutionSpeed = 0.2 + u.zoom_params.w * 1.3;
    
    // ═══ HONEST AUDIO (plasmaBuffer, not mouse-Y proxy) ═══
    // Bass drives the virtual pair-production rate and the vacuum burst.
    let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
    let pairRate = 1.0 + bass * 1.5;
    let burst = 1.0 + bass * 1.2;
    // Per-bin FFT [1..8] modulates entanglement-web density spatially:
    // screen column selects its bin, so the web thickens where its band lives.
    let binPos = clamp(u32(floor(uv.x * 8.0)), 0u, 7u);
    let fftLocal = plasmaBuffer[1u + binPos].x;
    let localDensity = clamp(webDensity * (0.45 + fftLocal * 1.1), 0.0, 1.0);
    
    // ═══ SPRING-DAMPERED VACUUM POLARITY WARP ═══
    // extraBuffer[133..136] = eased mouse warp point + velocity (safe zone).
    // Invocation (0,0) integrates; every pixel reads the eased value so the
    // vacuum polarity eases toward the cursor instead of snapping.
    let rawMouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    var warpPos = vec2<f32>(extraBuffer[WARP_POS_X], extraBuffer[WARP_POS_Y]);
    var warpVel = vec2<f32>(extraBuffer[WARP_VEL_X], extraBuffer[WARP_VEL_Y]);
    if (global_id.x == 0u && global_id.y == 0u) {
        let dt = clamp(time - extraBuffer[WARP_TIME], 0.0, 0.1);
        if (time < 0.1) {
            warpPos = rawMouse; // cold start: snap once to avoid a startup swoop
            warpVel = vec2<f32>(0.0);
        } else {
            let stiffness = 42.0;
            let damping = 9.0;
            let accel = (rawMouse - warpPos) * stiffness - warpVel * damping;
            warpVel += accel * dt;
            warpPos += warpVel * dt;
        }
        extraBuffer[WARP_POS_X] = warpPos.x;
        extraBuffer[WARP_POS_Y] = warpPos.y;
        extraBuffer[WARP_VEL_X] = warpVel.x;
        extraBuffer[WARP_VEL_Y] = warpVel.y;
        extraBuffer[WARP_TIME] = time;
    }
    // Polarity warp: eased cursor bends the vacuum domain; mouse-down deepens it.
    let polarity = (warpPos - vec2<f32>(0.5)) * (0.15 + u.zoom_config.w * 0.25);
    let warpedUV = uv + polarity;
    
    // Opacity control
    let opacity = 0.85;
    
    // Quantum foam base (bass-accelerated pair production)
    var generatedColor = quantumFoam(warpedUV, time * evolutionSpeed * pairRate, foamScale);
    
    // ═══ ENTANGLEMENT STRIKES (click shockwaves perturbing the web field) ═══
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri: u32 = 0u; ri < rippleCount; ri = ri + 1u) {
        let strike = u.ripples[ri];
        let age = time - strike.z;
        if (age > 0.0 && age < 5.0) {
            let dist = length(uv - strike.xy);
            let wavefront = age * 0.55;
            let ring = exp(-pow((dist - wavefront) * 14.0, 2.0));
            shock += ring * exp(-age * 1.4);
        }
    }
    
    // Add entanglement web (FFT-local density + strike perturbation)
    let strikeDensity = clamp(localDensity + shock * 0.5, 0.0, 1.0);
    let web = entanglementWeb(warpedUV, time * evolutionSpeed * 0.5, strikeDensity);
    generatedColor += vec3<f32>(web * 0.8, web * 0.9, web * 1.2);
    generatedColor += vec3<f32>(0.6, 0.8, 1.2) * shock * 0.6; // strike flash
    
    // Bass-driven vacuum burst
    generatedColor *= burst;
    
    // Volumetric glow simulation (blur approximation)
    let glowRadius = 2;
    var glowAccum = vec3<f32>(0.0);
    for (var gx: i32 = -glowRadius; gx <= glowRadius; gx = gx + 1) {
        for (var gy: i32 = -glowRadius; gy <= glowRadius; gy = gy + 1) {
            let sampleUV = warpedUV + vec2<f32>(f32(gx), f32(gy)) / resolution * 4.0;
            let sampleFoam = quantumFoam(sampleUV, time * evolutionSpeed * pairRate, foamScale);
            glowAccum += sampleFoam;
        }
    }
    glowAccum /= f32((glowRadius * 2 + 1) * (glowRadius * 2 + 1));
    generatedColor += glowAccum * glowGain * (0.8 + bass * 0.4);
    
    // HDR tone mapping
    generatedColor = acesToneMap(generatedColor * 0.8);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    generatedColor *= vignette;
    
    // ═══ TEMPORAL COHERENCE (bounded feedback <= 0.1 from dataTextureC) ═══
    let prevColor = textureLoad(dataTextureC, coordI, 0).rgb;
    generatedColor = mix(generatedColor, prevColor, 0.08);
    
    // ═══ BLEND WITH INPUT ═══
    let finalColor = mix(inputColor.rgb, generatedColor, opacity);
    let finalAlpha = max(inputColor.a, opacity);
    
    // Output
    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
    
    // Store clean display color for next-frame feedback (dataTextureC)
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, finalAlpha));
}
