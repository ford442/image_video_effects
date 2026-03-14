// ═══════════════════════════════════════════════════════════════
//  Crystal Facets - Physical Light Transmission with Alpha
//  Category: distortion
//  Features: mouse-driven, refraction, fresnel, dispersion
//  IOR: Quartz (1.54) - Diamond (2.42) configurable
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

// Refractive indices for different crystal types
const IOR_QUARTZ: f32 = 1.54;
const IOR_DIAMOND: f32 = 2.42;
const IOR_GLASS: f32 = 1.5;
const IOR_ICE: f32 = 1.31;

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

// Fresnel reflectance for unpolarized light
fn fresnelReflectance(cosTheta: f32, ior: f32) -> f32 {
    let g = sqrt(ior * ior - 1.0 + cosTheta * cosTheta);
    let gmc = g - cosTheta;
    let gpc = g + cosTheta;
    let a = (gmc * gpc) / ((gpc) * (gpc));
    let b = (cosTheta * gpc - 1.0) / (cosTheta * gmc + 1.0);
    return 0.5 * a * (1.0 + b * b);
}

// Fresnel-Schlick approximation (cheaper)
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate path length through crystal based on angle and thickness
fn pathLengthThroughCrystal(cosTheta: f32, thickness: f32) -> f32 {
    // Path length increases as viewing angle becomes more grazing
    return thickness / max(abs(cosTheta), 0.01);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    // ═══════════════════════════════════════════════════════════════
    // Parameters via zoom_params:
    // x: Facet Count (3 to 16)
    // y: Refraction Strength + IOR mix
    // z: Rotation Speed / Fracture density
    // w: Crystal Thickness / Transmission
    // ═══════════════════════════════════════════════════════════════
    
    let facetCount = floor(mix(3.0, 16.0, u.zoom_params.x));
    let iorMix = u.zoom_params.y; // 0 = glass, 1 = diamond
    let fractureDensity = u.zoom_params.z; // 0 = pure crystal, 1 = heavily fractured
    let crystalThickness = mix(0.1, 2.0, u.zoom_params.w);
    
    // Calculate IOR based on mix parameter
    let ior = mix(IOR_GLASS, IOR_DIAMOND, iorMix);
    let refraction = mix(0.02, 0.15, iorMix);
    let rotation = u.config.x * 0.1;
    let zoom = 1.0;

    // Coordinate relative to mouse/center
    var center = mouse;
    var dir = (uv - center);
    dir.x *= aspect;

    let dist = length(dir);
    var angle = atan2(dir.y, dir.x);
    angle += rotation;

    // Quantize angle to create facets
    let sector = floor(angle / (6.28318 / facetCount));
    let sectorAngle = sector * (6.28318 / facetCount);

    // Each facet has a random tilt/offset
    let facetID = sector;
    let randomTilt = (hash11(facetID) - 0.5) * 2.0;
    let facetFracture = hash11(facetID + 100.0); // Per-facet fracture amount

    // Offset vector for this facet
    let offsetDir = vec2<f32>(cos(sectorAngle), sin(sectorAngle));

    // Chromatic aberration with dispersion based on IOR
    let dispersion = (ior - 1.0) * 0.1; // Higher IOR = more dispersion
    let rOffset = offsetDir * refraction * (1.0 + randomTilt * 0.5);
    let gOffset = offsetDir * refraction * 0.5;
    let bOffset = offsetDir * refraction * (0.0 - randomTilt * 0.5);

    // Zoom effect per facet
    let distDistorted = pow(dist, zoom);

    // Reconstruct coordinate
    let baseUV = center + vec2<f32>(cos(angle - rotation), sin(angle - rotation)) * distDistorted / vec2<f32>(aspect, 1.0);

    // Sample background
    let r = textureSampleLevel(readTexture, u_sampler, baseUV - rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, baseUV - gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, baseUV - bOffset, 0.0).b;
    var color = vec3<f32>(r, g, b);

    // ═══════════════════════════════════════════════════════════════
    // Physical Light Transmission & Alpha Calculation
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate angle to facet normal (simplified as angle from facet center)
    let angleToNormal = abs(fract(angle / (6.28318 / facetCount)) - 0.5) * 2.0; // 0 = center, 1 = edge
    let cosTheta = cos(angleToNormal * 1.57); // Approximate angle
    
    // Fresnel at surface
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
    let fresnel = fresnelSchlick(cosTheta, F0);
    
    // Path length through crystal (varies by viewing angle)
    let pathLength = pathLengthThroughCrystal(cosTheta, crystalThickness);
    
    // Purity factor (inverse of fracture density)
    let purity = 1.0 - (fractureDensity * facetFracture);
    
    // Absorption coefficient based on purity
    let absorptionCoeff = mix(0.5, 5.0, fractureDensity);
    let absorption = exp(-absorptionCoeff * pathLength / max(purity, 0.1));
    
    // Distance to facet edge for edge effects
    let angleLocal = fract(angle / (6.28318 / facetCount));
    let edgeDist = min(angleLocal, 1.0 - angleLocal);
    let edgeFactor = smoothstep(0.02, 0.0, edgeDist);
    
    // Transmission coefficient (alpha)
    // Face-on: mostly transmitted (high alpha)
    // Edge-on: mostly reflected (low alpha)
    // More fractures = more scattering = lower alpha
    let transmission = absorption * (1.0 - fresnel) * purity;
    
    // Add specular highlight on edges
    let specular = edgeFactor * fresnel * 0.8;
    color += vec3<f32>(specular);
    
    // Internal reflections and scattering tint
    let internalScatter = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.95, 1.0), fractureDensity);
    color = color * internalScatter;

    // Output RGBA
    let alpha = clamp(transmission, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
