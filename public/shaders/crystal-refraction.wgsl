// ═══════════════════════════════════════════════════════════════
//  Crystal Refraction - Physical Light Transmission with Alpha
//  Category: interactive-mouse
//  Features: mouse-driven, faceted lens, chromatic dispersion
//  Simulates faceted crystal lens with physical transmission
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

const IOR_QUARTZ: f32 = 1.54;
const IOR_DIAMOND: f32 = 2.42;

// Fresnel-Schlick
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;

    // ═══════════════════════════════════════════════════════════════
    // Parameters:
    // x: facetScale (number of facets)
    // y: dispersion (IOR-based chromatic aberration)
    // z: strength (refraction strength)
    // w: crystalThickness (affects transmission)
    // ═══════════════════════════════════════════════════════════════
    
    let facetScale = u.zoom_params.x;
    let dispersion = u.zoom_params.y;
    let strength = u.zoom_params.z;
    let crystalThickness = mix(0.1, 1.5, u.zoom_params.w);
    let ior = mix(IOR_QUARTZ, IOR_DIAMOND, u.zoom_params.y);
    
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

    // Mouse Interaction
    var mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Calculate distance to mouse for lens effect
    let toCenter = uv - mousePos;
    let dist = length(toCenter);

    // Lens Radius
    let lensRadius = 0.4;
    let falloff = smoothstep(lensRadius, 0.0, dist);

    // Facet Logic - Create angular stepping for facets
    let angle = atan2(toCenter.y, toCenter.x);
    let numFacets = floor(10.0 * facetScale + 3.0);
    let steppedAngle = floor(angle / (6.28318 / numFacets) + 0.5) * (6.28318 / numFacets);

    // Calculate displacement vector
    let displacementDir = vec2<f32>(cos(steppedAngle), sin(steppedAngle));

    // Refraction strength falls off with distance from center
    let displaceAmount = displacementDir * dist * strength * falloff;

    // Chromatic Aberration (Dispersion) based on IOR
    // Higher IOR = more dispersion
    let dispersionAmt = (ior - 1.0) * dispersion * 2.0;
    let rOffset = displaceAmount * (1.0 + dispersionAmt);
    let gOffset = displaceAmount;
    let bOffset = displaceAmount * (1.0 - dispersionAmt);

    let r = textureSampleLevel(readTexture, u_sampler, uv - rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv - gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - bOffset, 0.0).b;

    // ═══════════════════════════════════════════════════════════════
    // Physical Transmission & Alpha
    // ═══════════════════════════════════════════════════════════════
    
    // Angle from lens center affects Fresnel
    let cosTheta = 1.0 - dist / lensRadius; // 1 at center, 0 at edge
    let fresnel = fresnelSchlick(max(cosTheta, 0.0), F0);
    
    // Path length through crystal (longer at edges)
    let pathLength = crystalThickness * (1.0 + dist / lensRadius);
    
    // Absorption (minimal for clear crystal)
    let absorption = exp(-0.2 * pathLength);
    
    // Transmission coefficient
    let transmission = absorption * (1.0 - fresnel) * falloff;
    
    // Add specular highlight on facet edges
    let angleDiff = abs(angle - steppedAngle);
    let edgeHighlight = (1.0 - smoothstep(0.0, 0.1, angleDiff)) * falloff * fresnel * 0.5;

    var color = vec3<f32>(r, g, b);
    color += vec3<f32>(edgeHighlight);

    // Alpha based on transmission within lens area
    let alpha = mix(1.0, transmission, falloff);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

    // Update Depth (Pass-through)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
