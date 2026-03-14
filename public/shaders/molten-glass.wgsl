// ═══════════════════════════════════════════════════════════════
// Molten Glass - Physical glass transmission with Beer-Lambert law
// Category: distortion
// Features: heat simulation, melting distortion, physically-based alpha
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=HeatRadius, y=Viscosity, z=Refraction, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);

    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;

    // Parameters
    let heatRadius = u.zoom_params.x * 0.2;
    let viscosity = u.zoom_params.y;
    let refraction = u.zoom_params.z * 0.1;
    let coolingRate = 0.01 + u.zoom_params.w * 0.1;
    let glassDensity = 0.5 + u.zoom_params.w * 2.0; // Beer-Lambert density

    // Mouse interaction
    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Read previous heat state
    let prevColor = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var heat = prevColor.r;

    // Decay heat
    heat = max(0.0, heat - coolingRate);

    // Add heat from mouse
    let influence = smoothstep(heatRadius, 0.0, dist);
    heat = min(1.0, heat + influence * 0.5);

    // Write new heat state
    textureStore(dataTextureA, coord, vec4<f32>(heat, 0.0, 0.0, 1.0));

    // Calculate distortion based on heat
    let wobble = sin(uv.y * 20.0 + time * 5.0) * cos(uv.x * 20.0 + time * 3.0) * 0.02;
    let distort = (heat * refraction) + (heat * wobble * viscosity);

    // Offset UVs based on heat gradient
    let pushDir = normalize(uv - mousePos);
    let safePushDir = select(pushDir, vec2<f32>(0.0, 0.0), length(uv - mousePos) < 0.001);

    let offset = safePushDir * distort * 0.5 + vec2<f32>(
        sin(uv.y * 50.0 + heat * 10.0),
        cos(uv.x * 50.0 + heat * 10.0)
    ) * distort * 0.5;

    let finalUV = uv + offset;
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Physical properties of molten glass
    // Normal from heat distortion
    let normal = normalize(vec3<f32>(offset * 10.0, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    
    // Fresnel increases with heat (surface becomes more irregular)
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let roughness = heat * 0.3; // More rough when hot
    let fresnel = R0 + (1.0 - R0 - roughness) * pow(1.0 - cos_theta, 5.0);
    
    // Glass thickness varies inversely with heat (thins when melting)
    let thickness = 0.1 * (1.0 - heat * 0.3);
    
    // Molten glass color shifts with heat (orange/red when hot)
    let coolGlassColor = vec3<f32>(0.92, 0.96, 1.0);
    let hotGlassColor = vec3<f32>(1.0, 0.7, 0.4);
    let glassColor = mix(coolGlassColor, hotGlassColor, heat);
    
    // Beer-Lambert absorption
    let absorption = exp(-(1.0 - glassColor) * thickness * glassDensity);
    
    // Transmission coefficient
    let transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;

    // Apply glass tint and transmission
    color = vec4<f32>(color.rgb * glassColor, transmission);

    // Gloss/specular where heat is high
    let gloss = smoothstep(0.8, 1.0, heat) * 0.2;
    color = color + vec4<f32>(gloss, gloss, gloss, 0.0);

    textureStore(writeTexture, coord, color);
}
