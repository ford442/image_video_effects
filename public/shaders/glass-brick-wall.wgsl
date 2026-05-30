// ═══════════════════════════════════════════════════════════════
// Glass Brick Wall - Physical glass transmission with Beer-Lambert law
// Category: distortion
// Features: refraction, specular, physically-based alpha
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BrickSize, y=DistortionStr, z=MortarSize, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let brickSize = mix(10.0, 50.0, u.zoom_params.x);
    let distortionStr = mix(0.0, 0.1, u.zoom_params.y);
    let mortarSize = mix(0.01, 0.1, u.zoom_params.z);
    let glassDensity = u.zoom_params.w * 2.0 + 0.5; // Beer-Lambert density parameter

    // Mouse as light source
    var mouse = u.zoom_config.yz;
    let lightPos = vec3<f32>(mouse * vec2<f32>(aspect, 1.0), 0.5);
    let pixelPos = vec3<f32>(uv * vec2<f32>(aspect, 1.0), 0.0);
    let lightDir = normalize(lightPos - pixelPos);

    // Grid Logic
    let gridUV = uv * vec2<f32>(brickSize * aspect, brickSize);
    let cellID = floor(gridUV);
    let cellUV = fract(gridUV);

    // Squircle Distance Field
    let d = cellUV - 0.5;
    let r = dot(d, d) * 4.0;

    // Calculate Normal from height map
    let normalXY = d * -2.0;
    let normalZ = sqrt(max(0.0, 1.0 - dot(normalXY, normalXY)));
    let normal = normalize(vec3<f32>(normalXY, normalZ));

    // Mortar Mask
    let distFromCenter = max(abs(d.x), abs(d.y));
    let mortarMask = smoothstep(0.48 - mortarSize, 0.5, distFromCenter);

    // Distortion
    let refractOffset = normal.xy * distortionStr * (1.0 - mortarMask);
    let finalUV = uv + refractOffset;
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Physical glass properties
    var transmission = 1.0;
    var glassColor = vec3<f32>(0.94, 0.97, 1.0); // Slight blue-green tint
    
    if (mortarMask < 0.5) {
        // Inside glass brick - apply Beer-Lambert law
        let viewDir = vec3<f32>(0.0, 0.0, 1.0);
        
        // Fresnel reflection (Schlick's approximation)
        let cos_theta = max(dot(viewDir, normal), 0.0);
        let R0 = 0.04; // Reflectance at normal incidence
        let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
        
        // Glass thickness based on curvature (thicker at edges)
        let thickness = 0.08 + r * 0.15;
        
        // Beer-Lambert: I = I0 * exp(-absorption * thickness * density)
        let absorption = exp(-(1.0 - glassColor) * thickness * glassDensity);
        
        // Transmission combines absorption and fresnel
        transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;
        
        // Apply glass tint
        color = vec4<f32>(color.rgb * glassColor, transmission);
        
        // Specular Highlight (Phong)
        let halfDir = normalize(lightDir + viewDir);
        let specular = pow(max(dot(normal, halfDir), 0.0), 16.0);
        color = color + vec4<f32>(specular * 0.3);

        // ═══ UNIQUE VISUAL IDEA: per-brick lens caustics ═══
        // Each squircle brick acts as a plano-convex lens. Light refracting through
        // it converges into a bright focal caustic. We trace the refracted light ray
        // and measure how tightly the brick's curvature focuses it toward this pixel:
        // where the refracted ray aligns with the view axis, energy concentrates.
        let iorGlass = 1.0 / 1.52; // air→glass inverse IOR for refract()
        let refLight = refract(-lightDir, normal, iorGlass);
        // Focal alignment: caustic is brightest where the refracted ray points back
        // along +Z (toward the viewer) AND the brick surface is steeply curved (edges).
        let focal = pow(max(refLight.z, 0.0), 6.0);
        let curvature = smoothstep(0.0, 0.6, r); // 0 at brick center, 1 at edges
        // Animated shimmer so the caustic "swims" like real refracted light.
        let causticPhase = sin(r * 22.0 - u.config.x * 2.0 + cellID.x * 1.3 + cellID.y * 0.7);
        let caustic = focal * (0.5 + 0.5 * causticPhase) * (0.35 + curvature * 0.8);
        // Chromatic focus: wavelengths focus at slightly different depths, tinting
        // the caustic core warm and its halo cool.
        let causticColor = vec3<f32>(1.0, 0.9, 0.7) + vec3<f32>(-0.2, 0.0, 0.4) * causticPhase;
        color = color + vec4<f32>(causticColor * caustic * 1.4, caustic * 0.5);
    } else {
        // Mortar - less transparent
        color = color * 0.4;
        transmission = 0.4;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Pass depth through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
