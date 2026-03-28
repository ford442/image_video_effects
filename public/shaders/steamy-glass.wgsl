// ═══════════════════════════════════════════════════════════════
//  Steamy Glass - Volumetric Alpha Upgrade
//  Simulates steam/fog on glass with physically-based volumetric
//  properties and dynamic wiping interaction.
//  
//  Scientific Implementation:
//  - Steam accumulates as participating medium
//  - Optical depth from steam density (feedback buffer)
//  - Mouse wiping reduces local optical depth
//  - Beer-Lambert extinction for realistic steam appearance
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Steam density buffer
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame density
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Steam/water vapor physical constants
const SIGMA_T_STEAM: f32 = 1.5;         // Steam extinction coefficient
const SIGMA_S_STEAM: f32 = 1.3;         // Steam scattering (white/milky)
const SIGMA_A_STEAM: f32 = 0.2;         // Steam absorption (minimal)
const STEP_SIZE: f32 = 0.025;           // Thickness of steam layer

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    // Params
    let steamAccumulationRate = u.zoom_params.x * 0.02;  // How fast steam builds
    let fadeSpeed = u.zoom_params.y * 0.05;              // Natural dissipation
    let wipeRadius = u.zoom_params.z * 0.3 + 0.05;       // Mouse wipe size
    let blurAmount = u.zoom_params.w;

    // ═══════════════════════════════════════════════════════════════
    //  Steam Density Simulation (Participating Medium)
    // ═══════════════════════════════════════════════════════════════
    
    // Read previous steam density from feedback buffer
    let prevSteam = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Generate noise for steam pattern (turbulent condensation)
    let steamNoise = hash12(uv * 50.0 + u.config.x * 0.01);
    let turbulence = hash12(uv * 100.0 - u.config.x * 0.02) * 0.5 + 0.5;
    
    // Steam naturally accumulates (returns)
    let accumulation = steamNoise * steamAccumulationRate;
    var newSteam = min(prevSteam + accumulation, 1.0);
    
    // Natural dissipation over time
    newSteam = max(0.0, newSteam - fadeSpeed * 0.01);

    // Wipe logic - mouse clears the steam
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let wipe = smoothstep(wipeRadius, wipeRadius - 0.1, dist);

    // Apply wipe (clear steam near mouse)
    newSteam = max(0.0, newSteam - wipe);

    // Write new steam state to feedback buffer
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newSteam, 0.0, 0.0, 1.0));

    // ═══════════════════════════════════════════════════════════════
    //  Volumetric Light Transport for Steam
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate optical depth through steam layer
    // τ = density * step_size * extinction_coefficient
    let opticalDepth = newSteam * STEP_SIZE * SIGMA_T_STEAM;
    
    // Transmittance (Beer-Lambert law): T = exp(-τ)
    let transmittance = exp(-opticalDepth);
    
    // Volumetric alpha: α = 1 - T
    let alpha = 1.0 - transmittance;

    // ═══════════════════════════════════════════════════════════════
    //  Render Logic with Volumetric Blending
    // ═══════════════════════════════════════════════════════════════
    
    // Sample clear image (what's behind the glass)
    let clearColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Sample blurred image (fake blur by sampling neighbors)
    // This simulates light scattering in the steam
    let offset = blurAmount * 0.01 * (1.0 + newSteam);
    var blurColor = vec3<f32>(0.0);
    blurColor += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset, 0.0), 0.0).rgb;
    blurColor += textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(offset, 0.0), 0.0).rgb;
    blurColor += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset), 0.0).rgb;
    blurColor += textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, offset), 0.0).rgb;
    blurColor *= 0.25;

    // Steam color (white/milky with slight blue tint for water vapor)
    let steamColor = vec3<f32>(0.95, 0.97, 1.0);

    // Volumetric composition:
    // 1. Clear image transmitted through steam
    // 2. Scattered light from steam itself
    // 3. Blurred image from scattering
    
    // Mix clear and blur based on steam density
    let scatteredImage = mix(clearColor, blurColor, newSteam * blurAmount);
    
    // In-scattered light from steam (white/milky glow)
    let inScattered = steamColor * newSteam * SIGMA_S_STEAM * (1.0 - transmittance);
    
    // Final color: transmitted + in-scattered
    let finalColor = scatteredImage * transmittance + inScattered;

    // Add condensation droplet highlights
    let dropletNoise = hash12(uv * 200.0 + u.config.x * 0.5);
    let droplets = smoothstep(0.98, 1.0, dropletNoise) * newSteam * 0.3;
    let finalWithDroplets = finalColor + vec3<f32>(droplets);

    // ═══════════════════════════════════════════════════════════════
    //  Output with Volumetric Alpha
    // ═══════════════════════════════════════════════════════════════
    // RGB: Steam-distorted image with in-scattered light
    // A: Physical opacity from optical depth
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalWithDroplets, alpha));

    // Pass depth with steam information
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Modify depth based on steam opacity
    let steamDepth = mix(depth, 0.9, alpha * 0.3);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(steamDepth, opticalDepth, 0.0, alpha));
}
