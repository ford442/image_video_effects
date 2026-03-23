// ═══════════════════════════════════════════════════════════════
//  Bioluminescent - Image Effect with Organic Material Properties
//  Category: artistic
//  Features: Reaction-diffusion growth, subsurface scattering, tissue alpha
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=GrowthRate, y=ColorMode, z=Pulse, w=DepthInfluence
  zoom_params: vec4<f32>,  // x=SpreadSpeed, y=BranchDensity, z=GlowIntensity, w=SporeCount
  ripples: array<vec4<f32>, 50>,
};
@group(0) @binding(3) var<uniform> u: Uniforms;

// Organic Growth Properties
const BIO_TISSUE_DENSITY: f32 = 2.0;      // Density of organic growth
const VEIN_OPACITY: f32 = 0.85;           // Veins are semi-transparent
const GLOW_TRANSPARENCY: f32 = 0.6;       // Bioluminescent areas transmit light

// Hash for randomness
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 3D noise for organic variation
fn noise3d(p: vec3<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    var u = f * f * (3.0 - 2.0 * f);
    let n = i.x + i.y * 57.0 + i.z * 113.0;
    
    return mix(mix(mix(hash(vec2<f32>(n + 0.0, 0.0)), hash(vec2<f32>(n + 1.0, 0.0)), u.x),
                   mix(hash(vec2<f32>(n + 57.0, 0.0)), hash(vec2<f32>(n + 58.0, 0.0)), u.x), u.y),
               mix(mix(hash(vec2<f32>(n + 113.0, 0.0)), hash(vec2<f32>(n + 114.0, 0.0)), u.x),
                   mix(hash(vec2<f32>(n + 170.0, 0.0)), hash(vec2<f32>(n + 171.0, 0.0)), u.x), u.y), u.z);
}

// Calculate surface normal from depth
fn calculate_normal(uv: vec2<f32>, depth: f32, texel: vec2<f32>) -> vec3<f32> {
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    
    let dx = (dR - dL) * 0.5;
    let dy = (dD - dU) * 0.5;
    
    return normalize(vec3<f32>(-dx, -dy, 1.0));
}

// Reaction-diffusion growth step
fn growth_step(uv: vec2<f32>, current: f32, normal: vec3<f32>, time: f32, 
               spread_speed: f32, density: f32, depth_influence: f32, depth: f32, res: vec2<f32>) -> f32 {
    var texel = 1.0 / res;
    
    let noise_val = noise3d(vec3<f32>(uv * 5.0, time * 0.1 * audioReactivity)); 
    let noise_val2 = noise3d(vec3<f32>(uv * 5.0 + 10.0, time * 0.1 * audioReactivity));
    
    let noise_offset = vec2<f32>(noise_val * 0.5, noise_val2 * 0.5) * texel * 2.0;
    
    let n1 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0) + noise_offset, 0.0).r;
    let n2 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0) + noise_offset, 0.0).r;
    let n3 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y) + noise_offset, 0.0).r;
    let n4 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y) + noise_offset, 0.0).r;
    
    var neighbor_avg = (n1 + n2 + n3 + n4) * 0.25;
    
    let flatness = smoothstep(0.3, 0.8, normal.y);
    let edge_avoidance = 1.0;
    let depth_mask = smoothstep(0.1, 0.9, depth);
    
    var growth = neighbor_avg * spread_speed * flatness * edge_avoidance * depth_mask;
    let decay = 0.998;
    
    return min(1.0, current * decay + growth * density);
}

// Color palette for bioluminescence
fn bio_color(t: f32, mode: f32, pulse: f32) -> vec3<f32> {
    let pulse_beat = sin(t * 10.0 + pulse * 5.0) * 0.3 + 0.7;
    
    if (mode < 0.25) { // Toxic Green
        return vec3<f32>(0.2, 1.0, 0.3) * pulse_beat;
    } else if (mode < 0.5) { // Deep Sea Blue
        return vec3<f32>(0.1, 0.6, 1.0) * pulse_beat;
    } else if (mode < 0.75) { // Magenta Coral
        return vec3<f32>(1.0, 0.2, 0.8) * pulse_beat;
    } else { // Lava Orange
        return vec3<f32>(1.0, 0.4, 0.1) * pulse_beat;
    }
}

// Calculate organic alpha for growth pattern
fn calculateGrowthAlpha(growth: f32, vein_pattern: f32, glow_intensity: f32) -> f32 {
    // Base alpha from growth density
    // Thicker growth = more opaque
    let densityAlpha = mix(0.2, VEIN_OPACITY, growth);
    
    // Veins are more opaque than surrounding tissue
    let veinAlpha = mix(densityAlpha, VEIN_OPACITY * 0.95, vein_pattern * 0.5);
    
    // Bioluminescent glow reduces alpha for light transmission
    let glowAlpha = mix(veinAlpha, GLOW_TRANSPARENCY, glow_intensity * growth * 0.6);
    
    // Apply Beer-Lambert style absorption
    let absorption = exp(-growth * BIO_TISSUE_DENSITY * 0.5);
    let finalAlpha = mix(glowAlpha, glowAlpha * 0.7, absorption * 0.3);
    
    return clamp(finalAlpha, 0.25, 0.92);
}

// Subsurface scattering for organic growth
fn growthSSS(growth: f32, vein_pattern: f32, baseColor: vec3<f32>) -> vec3<f32> {
    // Organic tissue absorbs different wavelengths
    let absorptionR = exp(-growth * 1.2);
    let absorptionG = exp(-growth * 0.9);
    let absorptionB = exp(-growth * 0.7);
    
    let scattered = vec3<f32>(
        baseColor.r * absorptionR,
        baseColor.g * absorptionG,
        baseColor.b * absorptionB
    );
    
    // Veins scatter differently
    let veinScatter = vein_pattern * vec3<f32>(0.3, 0.5, 0.4) * growth;
    
    return scattered + veinScatter;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    var texel = 1.0 / resolution;

    // Parameters
    let spread_mult = 1.0 + u.zoom_params.x * 0.1; 
    let branch_density = u.zoom_params.y;
    let glow_intensity = u.zoom_params.z;
    let spore_count = u32(u.zoom_params.w * 10.0);
    let growth_rate = u.zoom_config.x;
    let color_mode = u.zoom_config.y;
    let pulse = u.zoom_config.z;
    let depth_influence = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Calculate surface normal
    let normal = calculate_normal(uv, depth, texel);

    // Initialize or load growth state
    var growth = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    
    // Interactive Spore Placement
    let ripple_count = u32(u.config.y); 
    
    for (var i: u32 = 0u; i < min(50u, spore_count + 1u); i = i + 1u) {
         if (i < u32(u.config.y)) {
            let ripple = u.ripples[i];
            var center = ripple.xy;
            let age = time - ripple.z;
                                       
            if (age > 0.1 && age < 2.0) {
                let d = distance(uv, center);
                let aspect = resolution.x / resolution.y;
                let d_aspect = distance(uv * vec2<f32>(aspect, 1.0), center * vec2<f32>(aspect, 1.0));
                
                let influence = smoothstep(0.05, 0.0, d_aspect) * (1.0 - smoothstep(1.5, 2.0, age));
                growth = max(growth, influence);
            }
         }
    }

    // Growth Simulation
    if (growth_rate > 0.01) {
        growth = growth_step(uv, growth, normal, time, spread_mult, branch_density, depth_influence, depth, resolution);
    }

    // Store growth for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(growth, 0.0, 0.0, 1.0));

    // Vein Structure
    let vein_noise = noise3d(vec3<f32>(uv * 20.0, time * 0.5 * audioReactivity));
    let veins = smoothstep(0.3, 0.7, growth + vein_noise * 0.2);

    // Glow & Lighting
    let glow_falloff = pow(growth, 2.0) * glow_intensity;
    let bio_light = bio_color(time, color_mode, pulse) * glow_falloff;
    
    // Subsurface scattering approximation
    let ss_scatter = smoothstep(0.0, 0.5, growth) * 0.3;
    
    // Apply organic SSS to base color
    let scatteredBase = growthSSS(growth, veins, base_color);
    
    // Composition with alpha calculation
    let growth_alpha = calculateGrowthAlpha(growth, veins, glow_intensity);
    let final_color = scatteredBase * (1.0 - veins * 0.3) + bio_light + ss_scatter;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, growth_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
