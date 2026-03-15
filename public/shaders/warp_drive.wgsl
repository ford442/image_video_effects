// ═══════════════════════════════════════════════════════════════════════════════
//  Warp Drive with Alpha Physics
//  Scientific: Radial blur with relativistic motion effects and light transmission
//  
//  ALPHA PHYSICS:
//  - Radial motion creates Doppler-like intensity shifts
//  - Motion blur accumulates alpha along light path
//  - Chromatic aberration separates channels with different opacities
//  - Center glow adds emission-based alpha
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
  config: vec4<f32>,       // x=Time, y=Ripples, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
  ripples: array<vec4<f32>, 50>,
};

// Calculate Doppler-like factor for motion
fn calculateDopplerFactor(percent: f32, intensity: f32) -> f32 {
    // Approaching (toward center) = blueshift = brighter
    // Receding would be redshift, but we're doing radial blur inward
    return 1.0 + intensity * percent * 0.5;
}

// Calculate motion blur alpha accumulation
fn calculateMotionAlpha(
    sampleAlpha: f32,
    weight: f32,
    sampleIndex: f32,
    totalSamples: f32,
    decay: f32
) -> f32 {
    // Earlier samples (closer to original) have more weight
    let distanceFactor = 1.0 - (sampleIndex / totalSamples);
    
    // Decay reduces alpha contribution along the path
    let decayFactor = pow(decay, sampleIndex);
    
    // Combined alpha contribution
    return sampleAlpha * weight * decayFactor * (0.5 + distanceFactor * 0.5);
}

// Chromatic aberration alpha calculation for motion
fn calculateMotionChromaticAlpha(
    baseAlpha: f32,
    percent: f32,
    aberration: f32,
    channel: i32
) -> f32 {
    // Motion causes wavelength-dependent scattering
    let wavelengthFactor = vec3<f32>(0.9, 1.0, 1.1); // R, G, B scattering
    let scatter = percent * aberration * wavelengthFactor[channel];
    
    return clamp(baseAlpha - scatter * 0.3, 0.4, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    // x: Warp Intensity (0.0 to 1.0)
    // y: Aberration Strength (0.0 to 1.0)
    // z: Center Brightness (0.0 to 1.0)
    // w: Samples (Step count) - mapped to e.g. 10 to 50

    let intensity = u.zoom_params.x * 0.2;
    let aberration = u.zoom_params.y * 0.05;
    let brightness = u.zoom_params.z * 2.0;
    let samples = i32(u.zoom_params.w * 30.0 + 5.0);

    var mouse = u.zoom_config.yz;

    // Vector from pixel to mouse
    var dir = mouse - uv;
    let dist = length(dir);

    var colorSum = vec3<f32>(0.0);
    var alphaSum = 0.0;
    var totalWeight = 0.0;

    // Dithering to break up banding
    let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);

    let decay = 0.95;

    for (var i = 0; i < samples; i++) {
        let percent = (f32(i) + noise) / f32(samples);
        let weight = 1.0 - percent;

        let samplePos = uv + dir * percent * intensity;

        // Chromatic Aberration: sample channels at slightly different offsets
        let rPos = samplePos + dir * aberration * percent;
        let bPos = samplePos - dir * aberration * percent;

        let sampleR = textureSampleLevel(readTexture, u_sampler, rPos, 0.0);
        let sampleG = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0);
        let sampleB = textureSampleLevel(readTexture, u_sampler, bPos, 0.0);

        // Doppler factor for intensity
        let doppler = calculateDopplerFactor(percent, intensity);

        // Per-channel alphas
        let alphaR = calculateMotionChromaticAlpha(sampleR.a, percent, aberration, 0);
        let alphaG = calculateMotionChromaticAlpha(sampleG.a, percent, aberration, 1);
        let alphaB = calculateMotionChromaticAlpha(sampleB.a, percent, aberration, 2);
        
        // Accumulate color with alpha weighting
        let sampleColor = vec3<f32>(sampleR.r, sampleG.g, sampleB.b) * doppler;
        let sampleAlpha = (alphaR + alphaG + alphaB) / 3.0;
        
        // Motion blur alpha accumulation
        let blurAlpha = calculateMotionAlpha(sampleAlpha, weight, f32(i), f32(samples), decay);

        colorSum += sampleColor * weight * blurAlpha;
        alphaSum += blurAlpha;
        totalWeight += weight;
    }

    var finalColor = colorSum / totalWeight;
    var finalAlpha = alphaSum / totalWeight;

    // Add center brightness (bloom/engine glow)
    let distAspect = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));
    let glow = exp(-distAspect * 5.0) * brightness;
    
    finalColor += vec3<f32>(glow * 0.8, glow * 0.9, glow * 1.0);
    // Glow adds to alpha
    finalAlpha = min(finalAlpha + glow * 0.3, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
