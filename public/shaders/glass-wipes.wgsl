// ═══════════════════════════════════════════════════════════════
// Glass Wipes - Physical glass transmission with Beer-Lambert law
// Category: distortion
// Features: rain simulation, wiper interaction, physically-based alpha
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
  zoom_params: vec4<f32>,  // x=RainIntensity, y=WiperSize, z=DistortionScale, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mousePos = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let rainIntensity = 0.005 + u.zoom_params.x * 0.05;
    let wiperSize = 0.05 + u.zoom_params.y * 0.25;
    let distortionScale = u.zoom_params.z * 0.05;
    let evaporation = 0.001 + u.zoom_params.w * 0.01;
    let glassDensity = u.zoom_params.w * 1.5 + 0.3; // Beer-Lambert density for water/glass

    // Read previous wetness state
    let prevState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var wetness = prevState.r;

    // Add Rain
    let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if (noise > (1.0 - rainIntensity)) {
        wetness = min(1.0, wetness + 0.3);
    }

    // Natural evaporation
    wetness = max(0.0, wetness - evaporation);

    // Mouse Wiper Interaction
    if (mousePos.x >= 0.0) {
        let dVec = uv - mousePos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        if (dist < wiperSize) {
             let wipeFactor = smoothstep(wiperSize, wiperSize * 0.5, dist);
             wetness = wetness * (1.0 - wipeFactor);
        }
    }

    // Droplet distortion
    let dripNoiseX = fract(sin(dot(uv + vec2<f32>(0.0, time * 0.1), vec2<f32>(12.9898, 78.233))) * 43758.5453) - 0.5;
    let dripNoiseY = fract(sin(dot(uv + vec2<f32>(0.0, time * 0.1), vec2<f32>(39.346, 11.135))) * 43758.5453) - 0.5;
    let distortion = vec2<f32>(dripNoiseX, dripNoiseY) * wetness * distortionScale;

    // Save state
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(wetness, 0.0, 0.0, 1.0));

    // Physical water properties
    // Water has slightly different refractive index (~1.33 vs glass ~1.5)
    // and absorption characteristics
    let waterColor = vec3<f32>(0.85, 0.95, 1.0); // Blue-tinted water
    
    // Calculate normal from distortion
    let normal = normalize(vec3<f32>(distortion * 100.0, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    
    // Fresnel for water
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.02; // Water-air interface (lower than glass)
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
    
    // Water thickness based on wetness
    let thickness = wetness * 0.05;
    
    // Beer-Lambert absorption for water
    let absorption = exp(-(1.0 - waterColor) * thickness * glassDensity);
    
    // Transmission coefficient
    let transmission = mix(1.0, (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0, wetness);

    // Render with distortion
    let distortedUV = clamp(uv + distortion, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Apply water tint and alpha based on wetness
    color = vec4<f32>(mix(color.rgb, color.rgb * waterColor, wetness * 0.5), transmission);

    // Add specular highlight for water droplets
    let lightDir = normalize(vec2<f32>(0.5, 0.5) - uv);
    let light = max(0.0, dot(normal, normalize(vec3<f32>(lightDir, 1.0))));
    let specular = pow(light, 20.0) * wetness * 0.5;

    color = color + vec4<f32>(specular, specular, specular, 0.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
