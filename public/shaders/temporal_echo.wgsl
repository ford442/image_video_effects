// ═══════════════════════════════════════════════════════════════════════════════
//  temporal_echo.wgsl - Time-Warp Temporal Echo Effect
//  
//  RGBA Focus: Alpha = temporal echo strength/age
//  Techniques:
//    - Multi-frame temporal accumulation
//    - Motion vectors for warping
//    - Echo trails with decay
//    - Time displacement based on motion
//    - RGB channel time offset
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

// Sample with motion warp
fn sampleWarped(uv: vec2<f32>, motion: vec2<f32>, age: f32, tex: texture_2d<f32>) -> vec4<f32> {
    let warpedUV = uv - motion * age;
    return textureSampleLevel(tex, non_filtering_sampler, warpedUV, 0.0);
}

// Calculate motion vector from previous frames
fn calculateMotion(uv: vec2<f32>, time: f32, audioPulse: f32) -> vec2<f32> {
    // Synthetic motion based on time
    let angle = time * 0.5;
    let baseMotion = vec2<f32>(cos(angle), sin(angle)) * 0.01;
    
    // Add audio-driven turbulence
    let turb = vec2<f32>(
        sin(uv.y * 10.0 + time * 5.0),
        cos(uv.x * 10.0 + time * 5.0)
    ) * 0.005 * audioPulse;
    
    return baseMotion + turb;
}

// Echo color with RGB time offset
fn rgbEcho(uv: vec2<f32>, motion: vec2<f32>, timeOffset: vec3<f32>, 
           decay: f32, tex: texture_2d<f32>) -> vec4<f32> {
    var result: vec4<f32>;
    
    // Sample each channel at different times
    let rUV = uv - motion * timeOffset.r;
    let gUV = uv - motion * timeOffset.g;
    let bUV = uv - motion * timeOffset.b;
    
    // Sample with boundary check
    var rSample = vec4<f32>(0.0);
    var gSample = vec4<f32>(0.0);
    var bSample = vec4<f32>(0.0);
    
    if (all(rUV >= vec2<f32>(0.0)) && all(rUV <= vec2<f32>(1.0))) {
        rSample = textureSampleLevel(tex, non_filtering_sampler, rUV, 0.0);
    }
    if (all(gUV >= vec2<f32>(0.0)) && all(gUV <= vec2<f32>(1.0))) {
        gSample = textureSampleLevel(tex, non_filtering_sampler, gUV, 0.0);
    }
    if (all(bUV >= vec2<f32>(0.0)) && all(bUV <= vec2<f32>(1.0))) {
        bSample = textureSampleLevel(tex, non_filtering_sampler, bUV, 0.0);
    }
    
    result.r = rSample.r * decay;
    result.g = gSample.g * decay;
    result.b = bSample.b * decay;
    result.a = (rSample.a + gSample.a + bSample.a) / 3.0 * decay;
    
    return result;
}

// Ghost trail accumulation
fn ghostTrail(uv: vec2<f32>, motion: vec2<f32>, numGhosts: i32, 
              baseDecay: f32, tex: texture_2d<f32>) -> vec4<f32> {
    var accum = vec4<f32>(0.0);
    var totalWeight = 0.0;
    
    for (var i: i32 = 1; i <= numGhosts; i = i + 1) {
        let fi = f32(i);
        let age = fi * 0.02;
        let decay = pow(baseDecay, fi);
        
        let ghostUV = uv - motion * fi * 2.0;
        if (all(ghostUV >= vec2<f32>(0.0)) && all(ghostUV <= vec2<f32>(1.0))) {
            let ghost = textureSampleLevel(tex, non_filtering_sampler, ghostUV, 0.0);
            accum += ghost * decay;
            totalWeight += decay;
        }
    }
    
    if (totalWeight > 0.0) {
        accum /= totalWeight;
    }
    
    return accum;
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
    let numEchoes = i32(3.0 + u.zoom_params.x * 8.0); // 3-11 echoes
    let timeScale = u.zoom_params.y * 0.1; // 0-0.1 RGB offset
    let decayRate = 0.7 + u.zoom_params.z * 0.25; // 0.7-0.95
    let displacement = u.zoom_params.w * 0.1; // 0-0.1
    
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Calculate motion
    let motion = calculateMotion(uv, time, audioPulse);
    
    // Add mouse influence to motion
    let toMouse = mousePos - uv;
    motion += toMouse * 0.02 * audioPulse;
    
    // RGB time offset (chromatic temporal displacement)
    let timeOffset = vec3<f32>(
        0.0,
        timeScale * (1.0 + audioPulse),
        timeScale * 2.0 * (1.0 + audioPulse)
    );
    
    // Sample current frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Sample echoes with RGB offset
    let echoes = rgbEcho(uv, motion * (1.0 + displacement), timeOffset, 
                         f32(numEchoes), dataTextureC);
    
    // Ghost trail
    let trails = ghostTrail(uv, motion, numEchoes, decayRate, dataTextureC);
    
    // Combine: current + echoes + trails
    let echoWeight = 0.4;
    let trailWeight = 0.3;
    
    var finalRGB = current.rgb + echoes.rgb * echoWeight + trails.rgb * trailWeight;
    var finalAlpha = current.a + echoes.a * echoWeight + trails.a * trailWeight;
    
    // Temporal displacement blur (radial from center)
    let center = vec2<f32>(0.5);
    let toCenter = uv - center;
    let dist = length(toCenter);
    let angle = atan2(toCenter.y, toCenter.x);
    
    // Displace based on distance and time
    let displacedAngle = angle + sin(time + dist * 10.0) * displacement;
    let displacedUV = center + vec2<f32>(cos(displacedAngle), sin(displacedAngle)) * dist;
    
    if (all(displacedUV >= vec2<f32>(0.0)) && all(displacedUV <= vec2<f32>(1.0))) {
        let displaced = textureSampleLevel(dataTextureC, non_filtering_sampler, displacedUV, 0.0);
        finalRGB = mix(finalRGB, displaced.rgb, 0.2 * displacement);
    }
    
    // HDR boost
    finalRGB *= 1.0 + audioPulse * 0.3;
    
    // Tone mapping
    finalRGB = finalRGB / (1.0 + finalRGB * 0.3);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    
    // Clamp alpha
    finalAlpha = min(finalAlpha, 1.0);
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB * vignette, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    // Store for next frame's echo
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, finalAlpha * decayRate));
}
