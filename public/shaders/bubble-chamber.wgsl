// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
// ------------------------------

// Helper function for randomness
fn random(uv: vec2<f32>, seed: f32) -> f32 {
    return fract(sin(dot(uv + vec2(seed, seed), vec2(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;

    // Guard against out of bounds
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    // 1. Calculate Velocity Field
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    var mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    mouse_pos.x *= aspect;

    let to_mouse = p - mouse_pos;
    let dist = length(to_mouse);

    // Tangential component (magnetic spiral)
    // Rotates the vector 90 degrees
    let tangent = vec2(-to_mouse.y, to_mouse.x) / (dist + 0.001);

    // Radial component (drift towards/away from center)
    var radial = vec2(0.0);
    if (dist > 0.001) {
        radial = normalize(to_mouse);
    }

    // Combine based on Field Strength (Param 1: zoom_params.x)
    // Range roughly 0.0 to 1.0, scaled to appropriate velocity
    let field_strength = u.zoom_params.x * 0.02 + 0.002;

    // Spiral motion: mostly tangential, slight radial drift
    let velocity = (tangent + radial * 0.2) * field_strength;

    // 2. Advection (Sample History)
    // Convert velocity back to UV space for sampling
    let uv_velocity = velocity * vec2(1.0/aspect, 1.0);
    let sample_uv = uv - uv_velocity;

    // Sample previous frame
    let history = textureSampleLevel(dataTextureC, u_sampler, sample_uv, 0.0);

    // 3. Decay (Param 2: zoom_params.y)
    // Higher value = longer trails
    var decay = u.zoom_params.y;
    if (decay < 0.01) { decay = 0.96; } // Default persistence

    // Clamp decay to avoid explosion
    decay = min(decay, 0.995);

    // 4. Emission (Sparks/Ionization)
    let input_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luminance = dot(input_color.rgb, vec3(0.299, 0.587, 0.114));

    // Random seed varies by position and time
    let rand_val = random(uv, time);

    // Param 3: Ionization Rate (Probability of spawn)
    var spawn_rate = u.zoom_params.z;
    if (spawn_rate < 0.001) { spawn_rate = 0.05; } // Default rate

    var spark = vec4(0.0);
    // Probability check: brighter pixels emit more particles
    // Scale down spawn_rate to make it manageable
    if (rand_val < luminance * spawn_rate * 0.2) {
        // Spark color could be pulled from image or just white/gold
        // Let's use the input color but boosted
        spark = input_color * 2.0;
        spark.a = 1.0;
    }

    // Param 4: Color Shift over time
    var color_shift = u.zoom_params.w;
    var shifted_history = history * decay;

    if (color_shift > 0.1) {
        // Rotate hue slightly for psychedelic trails
        // Simple RGB rotation matrix approximation
        let r = shifted_history.r;
        let g = shifted_history.g;
        let b = shifted_history.b;

        let shift_speed = color_shift * 0.05;

        shifted_history.r = r * (1.0 - shift_speed) + g * shift_speed;
        shifted_history.g = g * (1.0 - shift_speed) + b * shift_speed;
        shifted_history.b = b * (1.0 - shift_speed) + r * shift_speed;
    }

    // 5. Composition
    // Max blending preserves the brightest trails
    let output = max(shifted_history, spark);

    // 6. Write Output
    textureStore(writeTexture, gid.xy, output);
    // Write to persistent history buffer
    textureStore(dataTextureA, gid.xy, output);
}
