// ═══════════════════════════════════════════════════════════════════
//  Digital Haze
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
// ═══════════════════════════════════════════════════════════════════
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// Digital haze extinction coefficients
const SIGMA_T_HAZE: f32 = 1.2;          // Haze extinction (thick)
const SIGMA_T_CLEAR: f32 = 0.05;        // Clear area extinction (minimal)
const STEP_SIZE: f32 = 0.03;            // Ray step

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    var mouse = u.zoom_config.yz;
    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    // Params; bass pulses the haze density, mids vary the noise texture
    let pixelStrength = u.zoom_params.x * 100.0 + 10.0;
    let clearRadius = u.zoom_params.y * 0.4 + 0.05;
    let noiseAmt = u.zoom_params.z * (1.0 + mids * 0.4);

    // ═══════════════════════════════════════════════════════════════
    //  Calculate Grid-based "Volumetric Cells"
    // ═══════════════════════════════════════════════════════════════
    
    // Mask: 0.0 near mouse (clear), 1.0 far away (haze)
    let mask = smoothstep(clearRadius, clearRadius + 0.2, dist);

    // Dynamic Pixelation
    let gridSize = vec2<f32>(pixelStrength * aspect, pixelStrength);
    let quantizedUV = floor(uv * gridSize) / gridSize;

    // Add digital noise to the quantized UV
    let seed = quantizedUV + vec2<f32>(time * 0.1, time * 0.05);
    let noiseVal = (hash(seed) - 0.5) * noiseAmt * 0.05;
    let hazeUV = quantizedUV + noiseVal;

    // Sample colors
    let colClear = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let colHaze = textureSampleLevel(readTexture, u_sampler, hazeUV, 0.0).rgb;

    // Apply a "digital" tint to the haze
    let greenTint = vec3<f32>(0.0, 0.1, 0.0) * noiseAmt;
    let finalHaze = colHaze + greenTint;

    // ═══════════════════════════════════════════════════════════════
    //  Volumetric Fog Calculation
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate optical depth based on mask (haze density); bass pulses fog thickness
    let hazeDensity = (mask * SIGMA_T_HAZE + (1.0 - mask) * SIGMA_T_CLEAR) * (1.0 + bass * 0.5);
    
    // Optical depth through the haze layer
    let opticalDepth = hazeDensity * STEP_SIZE * (1.0 + noiseAmt * 0.5);
    
    // Transmittance (Beer-Lambert): T = exp(-τ)
    let transmittance = exp(-opticalDepth);
    
    // Volumetric alpha: α = 1 - T
    let alpha = 1.0 - transmittance;
    
    // In-scattered light (digital haze color)
    let hazeColor = vec3<f32>(0.1, 0.15, 0.1); // Digital green-grey haze
    let inScattered = hazeColor * mask * (1.0 - transmittance);
    
    // Volumetric composition
    // Final = in_scattered + transmitted_clear * T + transmitted_haze * (1-T)
    let transmittedClear = colClear * transmittance;
    let transmittedHaze = finalHaze * (1.0 - transmittance) * 0.3;
    
    let finalColor = inScattered + transmittedClear + transmittedHaze;

    // Output with volumetric alpha; A = Beer-Lambert optical opacity
    let finalOut = vec4<f32>(finalColor, alpha);
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, gid.xy, finalOut);
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), finalOut);
}
