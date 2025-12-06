// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, z=ResX, w=ResY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=Freq, y=Amp, z=Speed, w=Chromatic
  ripples: array<vec4<f32>, 50>,
};

// Multi-octave wave synthesis for richer distortion
fn multi_octave_wave(pos: f32, time: f32, freq: f32, speed: f32, octaves: u32) -> f32 {
    var value = 0.0;
    var amplitude = 1.0;
    var frequency = freq;
    
    for (var i: u32 = 0u; i < octaves; i = i + 1u) {
        value += sin(pos * frequency + time * speed * (1.0 + f32(i) * 0.5)) * amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// Safe texture sampling with edge clamping
fn sample_clamped(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>) -> vec4<f32> {
    let clampedUV = clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
    return textureSampleLevel(tex, samp, clampedUV, 0.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters from sliders
    let baseFreq = mix(3.0, 30.0, u.zoom_params.x);     // Wave frequency
    let baseAmp = u.zoom_params.y * 0.04;               // Base amplitude
    let speed = mix(0.3, 4.0, u.zoom_params.z);         // Animation speed
    let chromatic = u.zoom_params.w;                    // Chromatic aberration strength

    // Aspect ratio correction for uniform waves
    let aspect = resolution.x / resolution.y;
    let correctedUV = uv * vec2<f32>(aspect, 1.0);

    // --- Multi-Octave Wave Distortion ---
    // Primary wave (horizontal displacement)
    let waveX = multi_octave_wave(correctedUV.y, time, baseFreq, speed, 3u) * baseAmp;
    
    // Secondary wave (vertical displacement, different phase)
    let waveY = multi_octave_wave(correctedUV.x, time, baseFreq * 0.7, speed * 1.2, 2u) * baseAmp * 0.7;
    
    // Tertiary turbulence (high frequency detail)
    let turbulence = sin(correctedUV.x * baseFreq * 4.0 + correctedUV.y * baseFreq * 2.0 + time * speed * 2.0) 
                     * baseAmp * 0.1;

    // Combine displacements
    let totalDisplacement = vec2<f32>(waveX + turbulence, waveY + turbulence);
    let finalUV = uv + totalDisplacement;

    // --- Chromatic Aberration (Dispersion) ---
    // Different wavelengths refract at slightly different angles
    var finalColor = vec3<f32>(0.0);
    if (chromatic > 0.01) {
        // Red channel (least refraction)
        let redUV = finalUV - totalDisplacement * chromatic * 0.3;
        finalColor.r = sample_clamped(readTexture, u_sampler, redUV).r;
        
        // Green channel (medium refraction)
        finalColor.g = sample_clamped(readTexture, u_sampler, finalUV).g;
        
        // Blue channel (most refraction)
        let blueUV = finalUV + totalDisplacement * chromatic * 0.3;
        finalColor.b = sample_clamped(readTexture, u_sampler, blueUV).b;
    } else {
        // Standard sampling without chromatic aberration
        finalColor = sample_clamped(readTexture, u_sampler, finalUV).rgb;
    }

    // --- Edge Darkening (vignette effect to hide clamping) ---
    let edgeFade = 1.0 - smoothstep(0.7, 1.0, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0);
    finalColor *= edgeFade;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Depth distortion with chromatic offset
    var depthUV = finalUV;
    if (chromatic > 0.01) {
        depthUV = finalUV + totalDisplacement * chromatic * 0.2;
    }
    let depth = sample_clamped(readDepthTexture, non_filtering_sampler, depthUV).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
