// ═══════════════════════════════════════════════════════════════
// Glass Wall - Physical glass transmission with Beer-Lambert law
// Category: distortion
// Features: refraction, chromatic aberration, physically-based alpha
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;
@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / dims.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Grid configuration
    let gridSize = 20.0;
    let scale = vec2<f32>(gridSize * aspect, gridSize);

    let cellID = floor(uv * scale);
    let cellUV = fract(uv * scale);

    // Cell Center in UV space
    let cellCenter = (cellID + 0.5) / scale;

    // Interaction Vector
    let aspectVec = vec2<f32>(aspect, 1.0);
    let vecToMouse = (mouse - cellCenter) * aspectVec;
    let dist = length(vecToMouse);

    // Interaction Strength
    let radius = 0.5;
    let influence = smoothstep(radius, 0.0, dist);

    // Calculate tilt based on mouse interaction
    var tilt = vec2<f32>(0.0);
    if (dist > 0.001) {
        tilt = normalize(vecToMouse) * influence;
    }

    // Bevel edges for 3D look
    let bevelX = smoothstep(0.0, 0.1, cellUV.x) * (1.0 - smoothstep(0.9, 1.0, cellUV.x));
    let bevelY = smoothstep(0.0, 0.1, cellUV.y) * (1.0 - smoothstep(0.9, 1.0, cellUV.y));
    let bevel = bevelX * bevelY;

    // Refraction displacement
    let refractionStrength = 0.05;
    let offset = tilt * refractionStrength;
    let bevelDistort = (vec2<f32>(0.5) - cellUV) * 0.02 * (1.0 - bevel);

    let finalUV = uv + offset + bevelDistort;

    // Calculate normal for fresnel effect
    let normal = normalize(vec3<f32>(tilt * 2.0 + (vec2<f32>(0.5)-cellUV)*0.5, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    
    // Glass physical properties (parameter via zoom_params.w)
    let glassDensity = u.zoom_params.w * 2.0 + 0.5;
    
    // Fresnel reflection
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
    
    // Glass thickness varies with tilt and bevel
    let thickness = 0.05 + (1.0 - bevel) * 0.1 + length(tilt) * 0.05;
    
    // Glass color (slight blue tint)
    let glassColor = vec3<f32>(0.93, 0.96, 1.0);
    
    // Beer-Lambert absorption
    let absorption = exp(-(1.0 - glassColor) * thickness * glassDensity);
    
    // Transmission coefficient
    let transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;

    // Chromatic Aberration with transmission-aware sampling
    let caStrength = 0.01 * influence + 0.005;

    let r = textureSampleLevel(videoTex, videoSampler, finalUV + tilt * caStrength, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, finalUV, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, finalUV - tilt * caStrength, 0.0).b;

    var color = vec4<f32>(r * glassColor.r, g * glassColor.g, b * glassColor.b, transmission);

    // Specular Highlight
    let lightDir = normalize(vec3<f32>(vecToMouse, 0.5));
    let spec = pow(max(dot(normal, lightDir), 0.0), 16.0) * influence;
    color = color + vec4<f32>(spec * 0.8);

    // Add grid lines (mortar) - less transparent
    let mortar = smoothstep(0.0, 0.05, cellUV.x) * smoothstep(1.0, 0.95, cellUV.x) *
                 smoothstep(0.0, 0.05, cellUV.y) * smoothstep(1.0, 0.95, cellUV.y);

    // Darken mortar with reduced transmission
    let mortarTransmission = transmission * 0.3;
    color = mix(vec4<f32>(color.rgb * 0.2, mortarTransmission), color, mortar);

    textureStore(outTex, gid.xy, color);

    // Pass through depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
