// ═══════════════════════════════════════════════════════════════════════════════
//  holographic_interference.wgsl - Holographic Rainbow with Alpha Ghosting
//  
//  RGBA Focus: Alpha = hologram ghost intensity/phase coherence
//  Techniques:
//    - Interference pattern simulation
//    - Wavelength-dependent phase shift (rainbow)
//    - Multi-layer ghost images with staggered alpha
//    - Diffraction grating effect
//    - Mouse-controlled light source position
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

// Wavelength to RGB
fn wavelengthToRGB(wavelength: f32) -> vec3<f32> {
    // Approximate visible spectrum (380-700nm)
    var color: vec3<f32>;
    
    if (wavelength >= 380.0 && wavelength < 440.0) {
        let t = (wavelength - 380.0) / (440.0 - 380.0);
        color = vec3<f32>(-(t - 1.0), 0.0, 1.0);
    } else if (wavelength >= 440.0 && wavelength < 490.0) {
        let t = (wavelength - 440.0) / (490.0 - 440.0);
        color = vec3<f32>(0.0, t, 1.0);
    } else if (wavelength >= 490.0 && wavelength < 510.0) {
        let t = (wavelength - 490.0) / (510.0 - 490.0);
        color = vec3<f32>(0.0, 1.0, -(t - 1.0));
    } else if (wavelength >= 510.0 && wavelength < 580.0) {
        let t = (wavelength - 510.0) / (580.0 - 510.0);
        color = vec3<f32>(t, 1.0, 0.0);
    } else if (wavelength >= 580.0 && wavelength < 645.0) {
        let t = (wavelength - 580.0) / (645.0 - 580.0);
        color = vec3<f32>(1.0, -(t - 1.0), 0.0);
    } else if (wavelength >= 645.0 && wavelength < 700.0) {
        color = vec3<f32>(1.0, 0.0, 0.0);
    }
    
    return saturate(color);
}

// Interference intensity
fn interferenceIntensity(pathDiff: f32, wavelength: f32) -> f32 {
    let phase = 2.0 * PI * pathDiff / wavelength;
    return 0.5 + 0.5 * cos(phase);
}

// Diffraction grating
fn diffractionGrating(uv: vec2<f32>, lineSpacing: f32, wavelength: f32, angle: f32) -> f32 {
    let d = sin(angle) + uv.x / lineSpacing;
    return 0.5 + 0.5 * sin(d * 2.0 * PI * wavelength);
}

// Holographic ghost layer
fn holographicLayer(uv: vec2<f32>, offset: vec2<f32>, time: f32, wavelength: f32, audioPulse: f32) -> vec4<f32> {
    let shiftedUV = uv + offset * (1.0 + audioPulse * 0.3);
    
    // Interference fringes
    let dist = length(shiftedUV - 0.5);
    let fringe = interferenceIntensity(dist * 100.0, wavelength);
    
    // Diffraction pattern
    let diffraction = diffractionGrating(shiftedUV, 0.01, wavelength, time * 0.5);
    
    // Combine
    let intensity = fringe * diffraction;
    let color = wavelengthToRGB(wavelength * 300.0 + 400.0) * intensity;
    
    // Alpha decreases with layer depth (ghosting effect)
    let alpha = intensity * (0.6 - length(offset) * 2.0);
    
    return vec4<f32>(color, max(alpha, 0.0));
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
    let numLayers = i32(3.0 + u.zoom_params.x * 5.0); // 3-8 ghost layers
    let rainbowSpread = u.zoom_params.y; // Wavelength spread
    let coherence = 0.5 + u.zoom_params.z * 0.5; // Phase coherence (affects alpha)
    let ghostOffset = u.zoom_params.w * 0.1; // Layer offset amount
    
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Accumulate holographic layers
    var accumRGBA = vec4<f32>(0.0);
    
    for (var i: i32 = 0; i < numLayers; i = i + 1) {
        let fi = f32(i);
        
        // Layer offset (ghosting)
        let angle = fi * 0.5 + time * 0.2;
        let offset = vec2<f32>(cos(angle), sin(angle)) * ghostOffset * fi;
        
        // Wavelength varies per layer and time
        let wavelength = 1.0 + fi * rainbowSpread + sin(time + fi) * 0.2;
        
        let layer = holographicLayer(uv, offset, time, wavelength, audioPulse);
        
        // Alpha modulation by coherence
        layer.a *= coherence * (1.0 + audioPulse * sin(fi * 2.0 + time * 3.0));
        
        // Composite
        accumRGBA.rgb = layer.rgb * layer.a + accumRGBA.rgb * (1.0 - layer.a);
        accumRGBA.a = layer.a + accumRGBA.a * (1.0 - layer.a);
    }
    
    // Add interference from mouse position (light source)
    let toMouse = length(uv - mousePos);
    let lightWave = interferenceIntensity(toMouse * 50.0, 0.5 + audioPulse * 0.3);
    let lightColor = wavelengthToRGB(500.0 + sin(time) * 100.0);
    accumRGBA.rgb += lightColor * lightWave * 0.3 * coherence;
    accumRGBA.a = min(accumRGBA.a + lightWave * 0.2, 1.0);
    
    // Sample background through hologram
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalRGB = mix(bg, accumRGBA.rgb, accumRGBA.a);
    let finalAlpha = accumRGBA.a;
    
    // HDR glow
    finalRGB = finalRGB * (1.0 + audioPulse * 0.5);
    
    // Tone mapping
    finalRGB = finalRGB / (1.0 + finalRGB * 0.3);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB * vignette, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, finalAlpha));
}

fn saturate(v: vec3<f32>) -> vec3<f32> {
    return clamp(v, vec3<f32>(0.0), vec3<f32>(1.0));
}
