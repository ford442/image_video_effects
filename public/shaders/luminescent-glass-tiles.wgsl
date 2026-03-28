// ═══════════════════════════════════════════════════════════════
// Luminescent Glass Tiles - Physical glass transmission with Beer-Lambert law
// Category: distortion
// Features: luma-driven distortion, mouse influence, physically-based alpha
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let density = max(u.zoom_params.x * 50.0, 1.0);
    let refractStr = u.zoom_params.y * 0.5;
    let radius = max(u.zoom_params.z, 0.01);
    let turbulence = u.zoom_params.w;
    let glassDensity = 1.0 + turbulence * 1.5; // Beer-Lambert density

    // Grid calculations
    let gridUV = uv * vec2<f32>(density * aspect, density);
    let cellID = floor(gridUV);
    let cellUV = fract(gridUV);

    // Find center of cell in global UV space
    let cellCenterGrid = cellID + vec2<f32>(0.5);
    let cellCenterUV = cellCenterGrid / vec2<f32>(density * aspect, density);

    // Sample video luminance at cell center to drive distortion
    let centerColor = textureSampleLevel(readTexture, u_sampler, cellCenterUV, 0.0);
    let luma = dot(centerColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Mouse influence
    let diff = cellCenterUV - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    let mouseFactor = smoothstep(radius, 0.0, dist);

    // Distortion logic
    var distUV = cellUV - 0.5;
    var scale = 1.0 - (luma * refractStr * 2.0);

    // Add mouse turbulence
    if (mouseFactor > 0.0) {
        scale = scale * (1.0 - mouseFactor * turbulence);
        let angle = mouseFactor * turbulence * 3.14;
        let s = sin(angle);
        let c = cos(angle);
        distUV = vec2<f32>(distUV.x * c - distUV.y * s, distUV.x * s + distUV.y * c);
    }

    distUV = distUV * scale;
    distUV = distUV + 0.5;

    // Reconstruct Global UV from distorted Cell UV
    let finalUV = (cellID + distUV) / vec2<f32>(density * aspect, density);

    // Border distance
    let border = max(abs(distUV.x - 0.5), abs(distUV.y - 0.5));
    
    // Glass normal from distortion
    let distortionVec = (finalUV - uv) * density;
    let normal = normalize(vec3<f32>(-distortionVec * 2.0, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    
    // Fresnel effect
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
    
    // Glass thickness varies with scale and border
    let tileThickness = 0.05 + (1.0 - scale) * 0.1;
    let edgeThickness = smoothstep(0.4, 0.5, border) * 0.05;
    let thickness = tileThickness + edgeThickness;
    
    // Luminescent glass color - shifts with luma
    let baseGlassColor = vec3<f32>(0.92, 0.96, 1.0);
    let luminescentTint = vec3<f32>(0.8 + luma * 0.4, 0.9 + luma * 0.2, 1.0);
    let glassColor = mix(baseGlassColor, luminescentTint, luma * 0.5);
    
    // Beer-Lambert absorption
    let absorption = exp(-(1.0 - glassColor) * thickness * glassDensity);
    
    // Transmission coefficient
    var transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;
    
    // Border reduces transmission (more opaque edges)
    transmission = mix(transmission * 0.6, transmission, 1.0 - smoothstep(0.45, 0.48, border));

    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Darken edges of tiles with adjusted alpha
    if (border > 0.45) {
        color = color * 0.5;
        transmission = transmission * 0.5;
    }

    // Apply glass tint and transmission
    color = vec4<f32>(color.rgb * glassColor, transmission);

    // Highlight based on luma (glass glow) - adds to transmission
    let glow = luma * 0.2 * mouseFactor;
    color = color + vec4<f32>(glow, glow, glow, glow * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
