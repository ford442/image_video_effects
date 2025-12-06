// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Accumulation buffer
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // Normal buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=Speed, y=Density, z=Wind, w=Accumulation
  ripples: array<vec4<f32>, 50>,
};

// Hash functions for procedural snowflakes
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

// Hexagonal snowflake using distance field
fn hexagon_dist(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    var pa = abs(p);
    pa -= 2.0 * min(dot(k.xy, pa), 0.0) * k.xy;
    pa -= vec2<f32>(clamp(pa.x, -k.z * r, k.z * r), r);
    return length(pa) * sign(pa.y);
}

fn snowflake(uv: vec2<f32>, seed: f32, size: f32) -> f32 {
    let center = vec2<f32>(0.5);
    let d = hexagon_dist((uv - center) * 2.0, size);
    
    // Add crystal branches
    let angle = seed * 6.28;
    let c = cos(angle);
    let s = sin(angle);
    let rot = mat2x2<f32>(c, -s, s, c);
    let branch_uv = rot * (uv - center);
    let branch = 1.0 - smoothstep(0.0, 0.1, abs(branch_uv.x) - size * 0.3) * 
                         smoothstep(0.0, 0.1, abs(branch_uv.y) - size * 0.8);
    
    return smoothstep(0.0, 0.02, -d) * branch;
}

fn snow_layer(uv: vec2<f32>, layer: u32, speed: f32, density: f32, wind: f32, time: f32) -> f32 {
    let seed = f32(layer) * 3.7;
    let layer_speed = speed * (1.0 + f32(layer) * 0.2);
    
    // Wind turbulence with gusts
    let gust = sin(time * 0.1 + seed) * 0.5 + 0.5;
    let turbulence = sin(uv.y * 8.0 + time * 2.0 + seed) * 0.15 * wind * gust;
    let wind_drift = time * layer_speed * wind * 0.3;
    
    let skewed_uv = vec2<f32>(
        uv.x * (1.0 + f32(layer) * 0.1) + turbulence + wind_drift,
        uv.y * (0.8 + f32(layer) * 0.05) + time * layer_speed
    );
    
    // Grid for snowflake distribution
    let cell_size = vec2<f32>(40.0, 40.0) / (1.0 + f32(layer) * 0.3);
    let cell = floor(skewed_uv * cell_size);
    let pos = fract(skewed_uv * cell_size);
    
    let rand = hash13(vec3<f32>(cell, seed));
    if (rand > density) { return 0.0; }
    
    // Varying flake sizes
    let flake_size = 0.3 + rand * 0.4;
    let flake = snowflake(pos, rand, flake_size);
    
    // Depth-based transparency
    let depth_fade = 1.0 - f32(layer) * 0.3;
    
    return flake * depth_fade;
}

// Calculate surface normal from depth
fn calculate_normal(uv: vec2<f32>, depth: f32, texel: vec2<f32>) -> vec3<f32> {
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    
    let dx = (dR - dL) * 0.5;
    let dy = (dD - dU) * 0.5;
    
    // Reconstruct normal (assuming depth is view-space Z)
    let normal = normalize(vec3<f32>(-dx, -dy, 1.0));
    return normal;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;

    // Parameters
    let speed = max(0.01, u.zoom_params.x * 2.0);
    let density = clamp(u.zoom_params.y * 0.5, 0.0, 1.0);
    let wind = (u.zoom_params.z - 0.5) * 4.0; // -2 to 2 range
    let accumulation_amt = u.zoom_params.w;
    let melt_rate = 0.001; // Per-second melt

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // --- Snowfall Layers ---
    var snow_acc = 0.0;
    snow_acc += snow_layer(uv, 0u, speed, density * 0.7, wind, time) * 0.6; // Far layer
    snow_acc += snow_layer(uv, 1u, speed, density * 0.9, wind, time) * 0.8; // Mid layer
    snow_acc += snow_layer(uv, 2u, speed, density, wind, time) * 1.0;       // Near layer

    // --- Surface Accumulation ---
    var accumulated_snow = 0.0;
    if (accumulation_amt > 0.01) {
        // Calculate surface normal
        let normal = calculate_normal(uv, depth, texel);
        
        // Snow accumulates on upward-facing surfaces (normal.y > 0.5)
        // and on flat surfaces (normal.y > 0.7)
        let up_factor = smoothstep(0.3, 0.7, normal.y);
        
        // Edge detection - avoid snow on vertical edges
        let d_center = depth;
        let d_up = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
        let edge_factor = 1.0 - smoothstep(0.01, 0.05, abs(d_center - d_up));
        
        // Height factor - less snow on distant objects
        let height_factor = smoothstep(0.0, 0.5, depth);
        
        // Combine factors
        let accumulation_factor = up_factor * edge_factor * height_factor * accumulation_amt;
        
        // Use persistence buffer for temporal accumulation
        let prev_snow = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
        accumulated_snow = clamp(prev_snow + accumulation_factor * 0.01 - melt_rate, 0.0, 0.8);
    }

    // Store accumulation for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(accumulated_snow, 0.0, 0.0, 1.0));

    // --- Lighting & Composition ---
    let snow_color = vec3<f32>(0.92, 0.95, 1.0);
    
    // Add subtle lighting to accumulated snow based on normal
    let normal = calculate_normal(uv, depth, texel);
    let light_dir = normalize(vec3<f32>(0.3, 0.8, 0.5));
    let snow_lighting = max(0.2, dot(normal, light_dir));
    
    // Mix snow with base color
    var final_color = base_color.rgb;
    
    // Falling snow (additive blending)
    final_color = mix(final_color, snow_color, snow_acc * 0.9);
    
    // Accumulated snow (multiplicative blending with lighting)
    final_color = mix(final_color, snow_color * snow_lighting, accumulated_snow);

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
