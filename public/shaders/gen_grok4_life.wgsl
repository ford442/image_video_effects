// ═══════════════════════════════════════════════════════════════════════════════
//  Smooth Life - Continuous Cellular Automata
//  Based on Stephan Rafler's SmoothLife (2011) - continuous version of Conway's Life
//  
//  SCIENTIFIC CONCEPT:
//  - States are continuous [0, 1] instead of binary {0, 1}
//  - Neighbor count uses convolution with bell-shaped kernel (approximated with 7x7)
//  - Transition uses smooth step functions instead of hard thresholds
//  - Supports gliders, scrollers, and organic blob-like patterns
//
//  Key equations:
//  - Inner radius (R1), outer radius (R2) define neighborhood rings
//  - m = average neighbor state over annulus (R1 to R2)
//  - n = average neighbor state over inner disk (0 to R1)
//  - s' = s + dt * transition(s, m, n)
//
//  ARTISTIC VISION:
//  - Organic blob-like patterns that flow and pulse
//  - No sharp pixel edges - all smooth gradients
//  - Living, breathing cellular tissue appearance
//  - Color-coded by cell age/activity
// ═══════════════════════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);
    let mouse = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z);
    let mouse_down = u.zoom_config.w > 0.0;
    
    // Parameters
    let dt = u.zoom_params.x;           // Time step (default: 0.1)
    let sharpness = u.zoom_params.y;    // Sharpness of transition (default: 0.5)
    let color_speed = u.zoom_params.z;  // Color cycle speed
    let initial_density = u.zoom_params.w; // Initial density for seeding
    
    // SmoothLife parameters (Rafler 2011 defaults with slight tweaks)
    let inner_radius = 3.0;   // R1 - inner neighborhood radius
    let outer_radius = 9.0;   // R2 - outer neighborhood radius
    
    // Birth and survival thresholds
    let b1 = 0.257;  // Birth inner threshold
    let b2 = 0.336;  // Birth outer threshold  
    let d1 = 0.365;  // Death inner threshold
    let d2 = 0.549;  // Death outer threshold
    
    // Read current state and age from dataTextureC
    let state_data = textureLoad(dataTextureC, px, 0);
    let state = state_data.r;        // Current cell state [0, 1]
    let age = state_data.g;          // Cell age for coloring
    let activity = state_data.b;     // Activity level
    
    // ═══════════════════════════════════════════════════════════════════
    // SMOOTH NEIGHBORHOOD CONVOLUTION
    // Use a 9x9 kernel approximation for the annular neighborhood
    // Inner disk (0 to R1): contributes to 'n'
    // Outer annulus (R1 to R2): contributes to 'm'
    // ═══════════════════════════════════════════════════════════════════
    
    var inner_sum = 0.0;   // Sum over inner disk
    var inner_weight = 0.0;
    var outer_sum = 0.0;   // Sum over outer annulus
    var outer_weight = 0.0;
    
    // 9x9 kernel for smooth convolution
    for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
            let offset = vec2<i32>(dx, dy);
            let npx = (px + offset + vec2<i32>(resolution)) % vec2<i32>(resolution);
            let neighbor_state = textureLoad(dataTextureC, npx, 0).r;
            
            // Distance from center (in pixel units)
            let dist = sqrt(f32(dx * dx + dy * dy));
            
            // Bell-shaped kernel weight (approximating Gaussian)
            // Using smoothstep for bell curve: 1 at center, 0 at radius
            if (dist < inner_radius) {
                let w = 1.0 - smoothstep(0.0, inner_radius, dist);
                inner_sum += neighbor_state * w;
                inner_weight += w;
            }
            if (dist < outer_radius && dist >= inner_radius * 0.5) {
                // Annulus weight - peaks at middle of annulus
                let mid_radius = (inner_radius + outer_radius) * 0.5;
                let w = 1.0 - abs(dist - mid_radius) / (outer_radius - inner_radius);
                let weight = max(0.0, w * w);  // Sharpen the bell curve
                outer_sum += neighbor_state * weight;
                outer_weight += weight;
            }
        }
    }
    
    // Normalize to get average neighbor states
    let n = select(inner_sum / inner_weight, 0.0, inner_weight < 0.001);
    let m = select(outer_sum / outer_weight, 0.0, outer_weight < 0.001);
    
    // ═══════════════════════════════════════════════════════════════════
    // SMOOTH TRANSITION FUNCTION
    // σ(x, a, b) = smoothstep(a, b, x) with adjustable sharpness
    // ═══════════════════════════════════════════════════════════════════
    
    // Adjusted sharpness based on parameter
    let sharp = max(0.01, sharpness * 2.0);
    
    // Smooth interval function: 1 when a < x < b, 0 otherwise
    // Using smoothstep for smooth transitions
    fn smooth_interval(x: f32, a: f32, b: f32, sharp: f32) -> f32 {
        let left = smoothstep(a - sharp, a + sharp, x);
        let right = 1.0 - smoothstep(b - sharp, b + sharp, x);
        return left * right;
    }
    
    // SmoothLife transition function
    // s' = σ(n, b1, b2) * (1 - s) + σ(n, d1, d2) * s
    // This gives: birth when s≈0 and n in [b1,b2], survival when s≈1 and n in [d1,d2]
    
    let birth = smooth_interval(n, b1, b2, sharp * 0.05);
    let survival = smooth_interval(n, d1, d2, sharp * 0.05);
    
    // Also consider the inner state for more organic behavior
    let inner_factor = smoothstep(0.0, 1.0, n * 2.0);
    
    // Combined transition: tend toward birth if dead, survival if alive
    var transition = birth * (1.0 - state) + survival * state;
    
    // Add slight influence from outer neighborhood for more dynamics
    transition += m * 0.05 * (0.5 - state);
    
    // ═══════════════════════════════════════════════════════════════════
    // STATE UPDATE WITH DISCRETE TIME STEP
    // s' = s + dt * (transition - s)  [approach target smoothly]
    // ═══════════════════════════════════════════════════════════════════
    
    let time_step = max(0.01, min(0.5, dt));
    var new_state = state + time_step * (transition - state);
    
    // Clamp to valid range
    new_state = clamp(new_state, 0.0, 1.0);
    
    // ═══════════════════════════════════════════════════════════════════
    // MOUSE INTERACTION - Draw living tissue
    // ═══════════════════════════════════════════════════════════════════
    
    let dist = distance(uv, mouse);
    if (mouse_down && dist < 0.03) {
        // Create organic blob at mouse position
        let blob = 1.0 - smoothstep(0.0, 0.03, dist);
        new_state = max(new_state, blob);
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // OCCASIONAL RANDOM SEEDING - Keep simulation alive
    // ═══════════════════════════════════════════════════════════════════
    
    let noise = fract(sin(dot(uv + time * 0.001, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let density_threshold = 1.0 - max(0.001, initial_density * 0.01);
    
    if (noise > density_threshold) {
        // Seed with smooth blob, not sharp pixel
        let seed_pos = vec2<f32>(
            fract(noise * 1.618),
            fract(noise * 2.718)
        );
        let seed_dist = distance(uv, seed_pos);
        if (seed_dist < 0.05) {
            new_state = max(new_state, 1.0 - smoothstep(0.0, 0.05, seed_dist));
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // AGE AND ACTIVITY TRACKING
    // ═══════════════════════════════════════════════════════════════════
    
    // Age increases when alive, decays when dead
    let age_rate = 0.02;
    var new_age = age + age_rate * (new_state - 0.1);
    new_age = fract(new_age);  // Cycle through colors
    
    // Activity tracks how much state is changing
    let change = abs(new_state - state);
    let new_activity = mix(activity, change, 0.1);
    
    // ═══════════════════════════════════════════════════════════════════
    // COLORING - Organic tissue appearance
    // ═══════════════════════════════════════════════════════════════════
    
    // Base colors for dead and alive states
    let dead_color = vec3<f32>(0.05, 0.08, 0.15);      // Deep blue-black
    let alive_base = vec3<f32>(0.1, 0.6, 0.3);         // Green base
    let alive_peak = vec3<f32>(0.9, 0.95, 0.3);        // Yellow-white peak
    let activity_color = vec3<f32>(1.0, 0.3, 0.5);     // Pink for activity
    
    // Color cycling based on age and time
    let cycle = new_age * 6.28318 + time * color_speed;
    let age_color = vec3<f32>(
        0.5 + 0.5 * sin(cycle),
        0.5 + 0.5 * sin(cycle + 2.094),
        0.5 + 0.5 * sin(cycle + 4.188)
    );
    
    // Mix colors based on state
    var color = mix(dead_color, alive_base, smoothstep(0.0, 0.3, new_state));
    
    // Add age coloring for living cells
    let age_influence = smoothstep(0.2, 0.8, new_state);
    color = mix(color, age_color, age_influence * 0.4);
    
    // Highlight peak states
    let peak = smoothstep(0.7, 1.0, new_state);
    color = mix(color, alive_peak, peak * 0.5);
    
    // Add activity glow
    let activity_glow = smoothstep(0.01, 0.1, new_activity) * 0.4;
    color += activity_color * activity_glow;
    
    // Subtle pulse based on neighborhood density
    let pulse = sin(time * 2.0 + m * 10.0) * 0.02 * new_state;
    color += vec3<f32>(pulse);
    
    // Vignette for organic feel
    let center_dist = length(uv - 0.5) * 1.4;
    color *= 1.0 - center_dist * center_dist * 0.3;
    
    // Output to textures
    textureStore(writeTexture, px, vec4<f32>(color, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(new_state, new_age, new_activity, 1.0));
}
