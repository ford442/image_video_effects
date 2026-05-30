// ═══════════════════════════════════════════════════════════════════════════════
//  Bubble Lens - Advanced Alpha
//  Category: distortion
//  Alpha Mode: Effect Intensity Alpha + Physical Transmittance
//  Features: advanced-alpha, lens-distortion, physical-alpha
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

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 5: Effect Intensity Alpha
fn effectIntensityAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    intensity: f32
) -> f32 {
    let displacement = length(displacedUV - originalUV);
    let displacementAlpha = smoothstep(0.0, 0.1, displacement);
    return baseAlpha * mix(0.5, 1.0, displacementAlpha * intensity);
}

// Mode 4: Physical Transmittance (Beer's Law for bubble film)
fn physicalTransmittanceAlpha(
    baseColor: vec3<f32>,
    thickness: f32,
    ior: f32
) -> f32 {
    // Thin film interference affects alpha
    let absorption = exp(-thickness * 0.5);
    let fresnel = pow((ior - 1.0) / (ior + 1.0), 2.0);
    return mix(absorption, 1.0, fresnel);
}

// Combined advanced alpha
fn calculateAdvancedAlpha(
    baseColor: vec3<f32>,
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    thickness: f32,
    ior: f32,
    params: vec4<f32>
) -> f32 {
    let effectAlpha = effectIntensityAlpha(originalUV, displacedUV, baseAlpha, params.x);
    let physicalAlpha = physicalTransmittanceAlpha(baseColor, thickness, ior);
    return clamp(effectAlpha * physicalAlpha, 0.0, 1.0);
}

// Schlick Fresnel approximation
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ UNIQUE VISUAL IDEA: gravity-driven soap-film drainage ═══
// Real soap bubbles thin at the top as the film drains downward under gravity,
// forming the iconic "black spot" before they pop, while color bands pool and
// swirl at the bottom. This value-noise drives turbulent thickness variation.
fn filmHash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn filmNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(filmHash(i), filmHash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(filmHash(i + vec2<f32>(0.0, 1.0)), filmHash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let bubbleRadius = u.zoom_params.x * 0.3 + 0.1;
    let magnification = u.zoom_params.y * 2.0 + 1.0;
    let filmThickness = u.zoom_params.z * 2.0 + 0.5;  // For interference
    let ior = u.zoom_params.w * 0.3 + 1.3;            // Index of refraction
    
    let mousePos = u.zoom_config.yz;
    
    // Distance from mouse (bubble center)
    let aspect = resolution.x / resolution.y;
    let d = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(d);
    
    // Calculate bubble effect
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
    
    var finalColor: vec3<f32>;
    var warpedUV = uv;
    var baseAlpha: f32 = 1.0;
    
    if (dist < bubbleRadius) {
        // Inside bubble - lens magnification effect
        let factor = dist / bubbleRadius;
        let lensStrength = (1.0 - factor * factor) * (magnification - 1.0);
        let direction = normalize(d);
        
        // Displace towards center for magnifying effect
        let displacement = direction * lensStrength * bubbleRadius * (1.0 - factor);
        warpedUV = uv - displacement / vec2<f32>(aspect, 1.0);
        warpedUV = clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0));
        
        let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
        
        // ═══ Gravity-driven film drainage ═══
        // Vertical position within the bubble: -1 at top, +1 at bottom.
        let vertInBubble = d.y / bubbleRadius;
        // Film drains downward: thin at top (drainGrad→0), thick at bottom (drainGrad→1).
        // Slow time drift makes the drainage living rather than static.
        let drainGrad = clamp(0.5 + vertInBubble * 0.5 + sin(time * 0.4) * 0.04, 0.0, 1.0);
        // Turbulent flow in the film — bands swirl and migrate down over time.
        let flowUV = warpedUV * 7.0 + vec2<f32>(0.0, -time * 0.25);
        let turb = filmNoise(flowUV) * 0.6 + filmNoise(flowUV * 2.3 + 11.0) * 0.4;
        // Effective thickness: drainage gradient × turbulence, scaled by the param.
        let drainThickness = filmThickness * (0.15 + drainGrad * 1.6) * (0.7 + turb * 0.6);

        // Thin film interference colors driven by the drained, turbulent thickness
        let phase = drainThickness * 10.0 * (1.0 - factor * 0.5);
        var interference = vec3<f32>(
            0.5 + 0.5 * cos(phase),
            0.5 + 0.5 * cos(phase + 2.09),
            0.5 + 0.5 * cos(phase + 4.18)
        );
        // The "black spot": where the film has drained to near-nothing at the very top,
        // interference collapses to a dark, colorless thin region (Newton's black film).
        let blackSpot = smoothstep(0.12, 0.0, drainThickness);
        interference = mix(interference, vec3<f32>(0.02, 0.02, 0.03), blackSpot);
        
        // Fresnel effect at edges
        let viewDir = vec2<f32>(0.0, 0.0) - d;
        let cosTheta = dot(normalize(viewDir), vec2<f32>(0.0, 1.0));
        let fresnel = schlickFresnel(abs(cosTheta), F0);
        
        finalColor = mix(sample.rgb, sample.rgb * interference * 1.2, fresnel * 0.5);
        baseAlpha = sample.a;
        
        // ═══ ADVANCED ALPHA CALCULATION ═══
        let alpha = calculateAdvancedAlpha(finalColor, uv, warpedUV, baseAlpha, filmThickness, ior, u.zoom_params);
        
        // Add specular highlight
        let highlight = pow(max(0.0, 1.0 - dist / bubbleRadius), 3.0) * fresnel;
        finalColor += vec3<f32>(highlight);
        
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
        
        // Depth modification inside bubble
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
        textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
        
    } else {
        // Outside bubble - normal sampling
        let sample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        textureStore(writeTexture, vec2<i32>(global_id.xy), sample);
        
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    }
}
