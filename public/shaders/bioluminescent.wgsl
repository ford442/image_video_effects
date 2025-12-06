// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Growth buffer
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // Normal buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=GrowthRate, y=ColorMode, z=Pulse, w=DepthInfluence
  zoom_params: vec4<f32>,  // x=SpreadSpeed, y=BranchDensity, z=GlowIntensity, w=SporeCount
  ripples: array<vec4<f32>, 50>,
};
@group(0) @binding(3) var<uniform> u: Uniforms;

// Hash for randomness
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 3D noise for organic variation
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(mix(hash(i.xy + vec2<f32>(0.0, 0.0)), hash(i.xy + vec2<f32>(1.0, 0.0)), u.x),
                   mix(hash(i.xy + vec2<f32>(0.0, 1.0)), hash(i.xy + vec2<f32>(1.0, 1.0)), u.x), u.y),
               mix(mix(hash(i.xy + vec2<f32>(0.0, 0.0) + vec2<f32>(113.0, 113.0)), hash(i.xy + vec2<f32>(1.0, 0.0) + vec2<f32>(113.0, 113.0)), u.x),
                   mix(hash(i.xy + vec2<f32>(0.0, 1.0) + vec2<f32>(113.0, 113.0)), hash(i.xy + vec2<f32>(1.0, 1.0) + vec2<f32>(113.0, 113.0)), u.x), u.y), u.z);
}

// Better 3D noise approximation since the above hash hack is a bit weird for 3d
fn noise3d(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    
    // Smoothstep interpolation
    let u = f * f * (3.0 - 2.0 * f);
    
    // Hash function that handles 3D input better
    // Simple way: offset the 2D hash
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
    let texel = 1.0 / res;
    
    // Sample neighbors with organic noise offset
    let noise_val = noise3d(vec3<f32>(uv * 5.0, time * 0.1)); 
    let noise_val2 = noise3d(vec3<f32>(uv * 5.0 + 10.0, time * 0.1));
    
    let noise_offset = vec2<f32>(noise_val * 0.5, noise_val2 * 0.5) * texel * 2.0; // Scale offset by texel
    
    let n1 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0) + noise_offset, 0.0).r;
    let n2 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0) + noise_offset, 0.0).r;
    let n3 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y) + noise_offset, 0.0).r;
    let n4 = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y) + noise_offset, 0.0).r;
    
    // Average neighbor growth
    var neighbor_avg = (n1 + n2 + n3 + n4) * 0.25;
    
    // Surface normal influence (grow on flat/upward surfaces)
    let flatness = smoothstep(0.3, 0.8, normal.y);
    // Recalculate dx/dy for edge avoidance locally if needed, or approximate from neighboring samples or normal
    let edge_avoidance = 1.0; // Simplified for now
    
    // Depth masking (avoid background)
    let depth_mask = smoothstep(0.1, 0.9, depth);
    
    // Growth factor
    let growth = neighbor_avg * spread_speed * flatness * edge_avoidance * depth_mask;
    
    // Decay over time
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;

    // Parameters
    let spread_speed = u.zoom_params.x * 0.02 + 1.0; // Needs to be > 1 to spread? Or additive. Original code used * 0.02 which makes it tiny.
    // Actually the logic is neighbor_avg * spread_speed. If spread_speed < 1 it will decay. 
    // Let's stick closer to the user provided logic but ensure it spreads.
    // User logic: let spread_speed = u.zoom_params.x * 0.02; -> this seems too small for a multiplicative factor.
    // Reaction diffusion usually needs slightly > 1 or additive terms.
    // Let's assume the user meant additive or a strong multiplier.
    // Let's try adjusting:
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

    // --- Initialize or load growth state ---
    var growth = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    
    // --- Interactive Spore Placement ---
    // Each ripple becomes a growth seed
    let ripple_count = u32(u.config.y); 
    // Warning: ripple_count logic might differ in actual app, usually u.config.y is just a count.
    
    for (var i: u32 = 0u; i < min(50u, spore_count + 1u); i = i + 1u) { // Check active ripples, simplified loop
         // Actually we should iterate through all ripples if they are active
         // But the User Code used u.config.y as ripple count.
         // Let's just iterate a fixed amount or up to ripple count if available.
         // Since we don't know exact ripple count passed in uniform (it varies), let's check array.
         // Actually u.config.y IS ripple count.
         if (i < u32(u.config.y)) {
            let ripple = u.ripples[i];
            let center = ripple.xy;
            let age = time - ripple.z; // ripple.z is start time? or normalized age?
                                       // Usually in this app ripples are [x, y, startTime, maxRadius]
                                       
            // Spores activate after 0.1 seconds and last 2 seconds
            if (age > 0.1 && age < 2.0) {
                let d = distance(uv, center);
                // Fix aspect ratio distro
                let aspect = resolution.x / resolution.y;
                let d_aspect = distance(uv * vec2<f32>(aspect, 1.0), center * vec2<f32>(aspect, 1.0));
                
                let influence = smoothstep(0.05, 0.0, d_aspect) * (1.0 - smoothstep(1.5, 2.0, age));
                growth = max(growth, influence);
            }
         }
    }

    // --- Growth Simulation ---
    if (growth_rate > 0.01) {
        // Use the corrected growth_step
        // We use spread_mult as 'spread_speed'
        growth = growth_step(uv, growth, normal, time, spread_mult, branch_density, depth_influence, depth, resolution);
    }

    // Store growth for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(growth, 0.0, 0.0, 1.0));

    // --- Vein Structure ---
    // Create vein-like patterns from growth map
    let vein_noise = noise3d(vec3<f32>(uv * 20.0, time * 0.5));
    let veins = smoothstep(0.3, 0.7, growth + vein_noise * 0.2);

    // --- Glow & Lighting ---
    // Distance-based glow falloff
    let glow_falloff = pow(growth, 2.0) * glow_intensity;
    let bio_light = bio_color(time, color_mode, pulse) * glow_falloff;
    
    // Subsurface scattering approximation
    let ss_scatter = smoothstep(0.0, 0.5, growth) * 0.3;
    
    // --- Composition ---
    // Multiply blend for organic integration
    let final_color = base_color * (1.0 - veins * 0.3) + bio_light + ss_scatter;
    
    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
