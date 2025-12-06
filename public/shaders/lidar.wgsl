// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // Persistence buffer
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, z=ResX, w=ResY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=Speed, y=Width, z=Contours, w=Edges
  ripples: array<vec4<f32>, 50>,
};

// Hash function for noise
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 3D Sobel operator for robust edge detection
fn sobel_edge(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    // Sample 3x3 grid
    let tl = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).r;
    let tc = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let tr = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, -texel.y), 0.0).r;
    let ml = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;
    let mr = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let bl = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, texel.y), 0.0).r;
    let bc = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let br = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, texel.y), 0.0).r;
    
    // Sobel kernels
    let sum_x = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
    let sum_y = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
    
    return length(vec2<f32>(sum_x, sum_y));
}

// Generate scan pattern based on mode
fn scan_pattern(uv: vec2<f32>, time: f32, speed: f32, mode: u32) -> f32 {
    let center = vec2<f32>(0.5);
    
    if (mode == 1u) { // Radial scan from center
        let dist = length(uv - center);
        return fract((dist - time * speed * 0.5));
    } else if (mode == 2u) { // Spiral scan
        let delta = uv - center;
        let angle = atan2(delta.y, delta.x) / (2.0 * 3.14159);
        let radius = length(delta);
        return fract(angle + time * speed * 0.2 + radius * 0.5);
    } else { // Linear vertical scan (default)
        return fract(time * speed);
    }
}

// Generate point cloud pattern
fn point_cloud(uv: vec2<f32>, depth: f32, time: f32) -> f32 {
    let grid_size = 8.0; // Points per dimension
    let cell = floor(uv * grid_size);
    let pos = fract(uv * grid_size);
    
    // Depth-based jitter
    let jitter = hash12(cell) * 0.5;
    let depth_jitter = fract(depth + jitter + time * 0.1);
    
    // Point size based on depth
    let point_size = 0.3 * (1.0 - depth);
    
    let d = distance(pos, vec2<f32>(0.5));
    return smoothstep(point_size, point_size * 0.5, d) * (1.0 - depth_jitter);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;

    // Parameters
    let scan_speed = u.zoom_params.x * 0.6;
    let beam_width = mix(0.005, 0.15, u.zoom_params.y);
    let contour_freq = mix(5.0, 80.0, u.zoom_params.z);
    let edge_sensitivity = mix(0.002, 0.05, u.zoom_params.w);
    let scan_mode = u32(u.zoom_config.x); // 0=linear, 1=radial, 2=spiral
    let persistence = u.zoom_config.y; // Echo trail strength

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // --- Edge Detection (3D Sobel) ---
    let edge_val = sobel_edge(uv, texel);
    let is_edge = smoothstep(edge_sensitivity, edge_sensitivity * 2.0, edge_val);

    // --- Contour Lines (Topographic) ---
    let contour = 0.5 + 0.5 * sin(depth * contour_freq + time * 0.1);
    let is_contour = smoothstep(0.92, 1.0, contour);

    // --- Scan Beam ---
    let scan_pos = scan_pattern(uv, time, scan_speed, scan_mode);
    let dist_to_scan = abs(depth - scan_pos);
    let in_beam = 1.0 - smoothstep(0.0, beam_width, dist_to_scan);
    
    // Beam intensity fades at edges
    let beam_falloff = 1.0 - smoothstep(0.0, beam_width * 2.0, dist_to_scan);
    
    // --- Point Cloud ---
    let points = point_cloud(uv, depth, time) * in_beam;

    // --- Persistence (Echo Trails) ---
    let prev_echo = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    let new_echo = in_beam * (1.0 - depth); // Brighter echoes for nearer surfaces
    let echo = max(prev_echo * (1.0 - persistence * 0.1), new_echo);
    
    // Store echo for next frame
    textureStore(dataTextureB, global_id.xy, vec4<f32>(echo, 0.0, 0.0, 1.0));

    // --- Grid Overlay ---
    let grid_line = smoothstep(0.48, 0.5, fract(uv.x * 20.0)) + 
                    smoothstep(0.48, 0.5, fract(uv.y * 20.0));
    let grid = grid_line * 0.3 * (1.0 - depth * 0.5);

    // --- Color Mapping ---
    // Height-based color gradient
    let height_color = mix(
        vec3<f32>(0.0, 0.2, 0.8),  // Deep blue (far)
        vec3<f32>(0.0, 1.0, 0.8),  // Cyan (near)
        depth
    );
    
    // Edge color
    let edge_color = vec3<f32>(0.0, 0.9, 1.0) * (1.0 + beam_falloff);
    
    // Beam color with pulse
    let pulse = sin(time * 10.0) * 0.3 + 0.7;
    let beam_color = vec3<f32>(1.0, 0.1, 0.1) * pulse;

    // --- Composition ---
    var final_rgb = height_color * 0.3; // Base height map
    
    // Add grid
    final_rgb += grid;
    
    // Add contours
    final_rgb = mix(final_rgb, edge_color * 0.5, is_contour);
    
    // Add edges
    final_rgb = mix(final_rgb, edge_color, is_edge * (0.5 + beam_falloff * 0.5));
    
    // Add scan beam (illuminates everything)
    final_rgb += beam_color * in_beam * 0.5;
    
    // Add point cloud
    final_rgb = mix(final_rgb, beam_color, points);
    
    // Add echo trails
    final_rgb += vec3<f32>(0.5, 0.2, 0.0) * echo * persistence;

    // Scan artifacts (noise)
    let artifact = hash12(uv * 100.0 + time) * 0.05 * (1.0 - depth);
    final_rgb += artifact;

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_rgb, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
