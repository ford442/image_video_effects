// ═══════════════════════════════════════════════════════════════
//  Volumetric Rainbow Clouds - PASS 1 of 2 with Scientific Alpha
//  Generates 3D noise clouds with volumetric density, lighting, and 
//  depth-aware rainbow coloring for prismatic effects.
//  
//  Volumetric Implementation:
//  - Layered 3D density sampling for optical depth
//  - Beer-Lambert extinction for each cloud layer
//  - Accumulated alpha from multiple scattering layers
//  
//  Outputs:
//    - writeTexture: Rainbow-colored clouds with RGBA
//    - writeDepthTexture: Cloud optical depth and depth information
//  
//  Next Pass: prismatic-3d-compositor.wgsl
// ═══════════════════════════════════════════════════════════════

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

// Volumetric constants for rainbow clouds
const SIGMA_T_CLOUD: f32 = 1.8;         // Cloud extinction
const SIGMA_S_CLOUD: f32 = 1.6;         // High scattering albedo
const LAYER_THICKNESS: f32 = 0.5;       // Thickness of each cloud layer

fn hash3d(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 = p3 + dot(p3, p3 + vec3<f32>(33.33, 333.33, 133.33));
    return fract(p3.x * p3.y * p3.z);
}

fn fbm3d(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < 6; i = i + 1) {
        value = value + amplitude * (hash3d(p * frequency) - 0.5);
        frequency = frequency * 2.1;
        amplitude = amplitude * 0.5;
    }
    return value;
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    var uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    var mousePos = vec2<f32>(u.zoom_config.y / dims.x, u.zoom_config.z / dims.y);

    let scale = max(0.001, u.zoom_params.x) * 5.0;
    let flowSpeed = u.zoom_params.y;
    let densityParam = u.zoom_params.z;
    let lightIntensity = u.zoom_params.w;
    let cameraZ = u.zoom_config.w;

    // Perspective transform
    var center = vec2<f32>(0.5, 0.5);
    let delta = uv - center;
    let perspective = 1.0 + cameraZ;
    let perspUV = center + delta / perspective;

    // ═══════════════════════════════════════════════════════════════
    //  Volumetric Cloud Layer Sampling
    //  Sample multiple depth layers and accumulate optical depth
    // ═══════════════════════════════════════════════════════════════
    
    var totalOpticalDepth = 0.0;
    var accumulatedColor = vec3<f32>(0.0);
    var transmittance = 1.0;
    var normal = vec3<f32>(0.0, 0.0, 1.0);

    // Sample multiple depth layers to approximate 3D volumetric integration
    let numLayers = 3;
    for (var layer: i32 = 0; layer < numLayers; layer = layer + 1) {
        let layerZ = f32(layer) * LAYER_THICKNESS + time * flowSpeed * 0.1;
        let noisePos = vec3<f32>(perspUV * scale, layerZ);
        let noise = fbm3d(noisePos);
        
        // Layer density with falloff
        let layerWeight = 1.0 - f32(layer) * 0.3;
        let layerDensity = abs(noise) * layerWeight * densityParam * 2.0;
        
        // Calculate optical depth for this layer
        let layerOpticalDepth = layerDensity * LAYER_THICKNESS * SIGMA_T_CLOUD;
        totalOpticalDepth += layerOpticalDepth;
        
        // Transmittance through this layer
        let layerTransmittance = exp(-layerOpticalDepth);
        
        // Rainbow color for this layer based on position and time
        let hue = fract(atan2(noisePos.y, noisePos.x) / (2.0 * 3.14159) + time * 0.1 + f32(layer) * 0.1);
        let layerColor = hsv2rgb(fract(hue), 0.9, 1.0) * layerDensity * SIGMA_S_CLOUD;
        
        // Accumulate in-scattered light
        accumulatedColor += transmittance * layerColor * (1.0 - layerTransmittance);
        
        // Update transmittance
        transmittance *= layerTransmittance;

        // Normal calculation for lighting
        let eps = 0.01;
        let dx = fbm3d(noisePos + vec3<f32>(eps, 0.0, 0.0)) - noise;
        let dy = fbm3d(noisePos + vec3<f32>(0.0, eps, 0.0)) - noise;
        normal = normal + normalize(vec3<f32>(dx, dy, eps * 2.0)) * layerWeight;
    }

    // Final cloud density from accumulated optical depth
    let cloudDensity = 1.0 - exp(-totalOpticalDepth);
    normal = normalize(normal);

    // Lighting from mouse as light source
    let lightPos = vec3<f32>(mousePos - vec2<f32>(0.5, 0.5), 1.0);
    let viewPos = vec3<f32>(perspUV - vec2<f32>(0.5, 0.5), 0.0);
    let lightDir = normalize(lightPos - viewPos);

    let diffuse = max(dot(normal, lightDir), 0.0);
    let reflectDir = reflect(-lightDir, normal);
    let viewDir = normalize(-viewPos);
    let specular = pow(max(dot(viewDir, reflectDir), 0.0), 32.0) * lightIntensity;

    // Rainbow color based on normal orientation and time
    let hue = (atan2(normal.y, normal.x) + time * 0.5) / (2.0 * 3.14159);
    let rainbow = hsv2rgb(fract(hue), 0.9, 1.0);

    // Combine lighting with volumetric color
    let litColor = rainbow * (diffuse + 0.3) + vec3<f32>(1.0,1.0,1.0) * specular;
    
    // Blend volumetric accumulated color with lit color
    let finalColor = mix(accumulatedColor, litColor * cloudDensity, 0.5);

    // Depth-based fog parameters
    let fogStart = 0.5;
    let fogEnd = 2.0;
    let depth = length(viewPos) + cloudDensity;
    let fogFactor = smoothstep(fogStart, fogEnd, depth);
    let fogColor = vec3<f32>(0.1, 0.0, 0.2);
    let finalWithFog = mix(finalColor, fogColor, fogFactor);

    // ═══════════════════════════════════════════════════════════════
    //  Volumetric Alpha Output
    // ═══════════════════════════════════════════════════════════════
    
    // Alpha from total optical depth (Beer-Lambert)
    let finalAlpha = 1.0 - exp(-totalOpticalDepth);
    
    // Output RGBA
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalWithFog, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, totalOpticalDepth, 0.0, finalAlpha));
}
