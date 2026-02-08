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

// Psychedelic Hyper-Warp
// Advanced WGSL shader with domain warping, fractal noise, and reaction-diffusion feedback.

// 2D random function for noise generation
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// 2D noise function
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let a = rand(i);
    let b = rand(i + vec2<f32>(1.0, 0.0));
    let c = rand(i + vec2<f32>(0.0, 1.0));
    let d = rand(i + vec2<f32>(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion (fBm) for detailed patterns
fn fbm(p: vec2<f32>, octaves: i32, persistence: f32) -> f32 {
    var total = 0.0;
    var frequency = 1.0;
    var amplitude = 1.0;
    var maxValue = 0.0;
    for (var i = 0; i < octaves; i++) {
        total += noise(p * frequency) * amplitude;
        maxValue += amplitude;
        amplitude *= persistence;
        frequency *= 2.0;
    }
    return total / maxValue;
}

// Function to create a vibrant color palette
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.2;

    // --- Feedback and Coordinates ---
    // Sample a slightly offset point for reaction-diffusion effect
    let feedback_offset = vec2<i32>(i32((noise(uv * 4.0 + time) - 0.5) * 0.005 * resolution.x), 
                                     i32((noise(uv * 4.0 + time + 1.0) - 0.5) * 0.005 * resolution.y));
    let history = textureLoad(dataTextureC, px + feedback_offset, 0).rgb;

    let aspect = resolution.x / resolution.y;
    var p = uv - 0.5;
    p.x *= aspect;

    // --- Mouse Interaction ---
    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) - 0.5;
    mouse.x *= aspect;
    let mouse_dist = length(p - mouse);
    // Inverted smoothstep logic
    let mouse_warp = pow(1.0 - smoothstep(0.2, 0.0, mouse_dist), 2.0) * u.zoom_config.w;

    // --- Domain Warping ---
    // Warp the coordinate space using multiple layers of fBm for a liquid-like distortion
    var q = vec2<f32>(
        fbm(p + vec2<f32>(0.0, time * 0.4), 3, 0.5),
        fbm(p + vec2<f32>(5.2, time * 0.3), 3, 0.5)
    );
    // Add mouse influence to the domain warp
    let warp_dir = normalize(p - mouse);
    // Only apply if mouse_warp has value
    if (length(warp_dir) > 0.001) {
         q += mouse_warp * warp_dir * 0.5;
    }

    var r = vec2<f32>(
        fbm(p + q * 2.0 + vec2<f32>(1.7, 9.2) + 0.1 * time, 4, 0.6),
        fbm(p + q * 2.0 + vec2<f32>(8.3, 2.8) + 0.1 * time, 4, 0.6)
    );

    // --- Final Pattern Generation ---
    // The final value is a mix of warped coordinates and a radial component
    let val = fbm((p + r) * 2.0, 5, 0.5);
    // Inverted smoothstep logic
    let radial_burst = pow(1.0 - smoothstep(0.5, 0.0, length(p)), 2.0);
    let final_val = val + radial_burst * 0.2;

    // --- Advanced Color Mapping ---
    // Blend between two psychedelic palettes based on the pattern value
    let color1 = palette(final_val + time, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.0, 0.1, 0.2));
    let color2 = palette(final_val + time, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 1.0, 0.5), vec3<f32>(0.8, 0.9, 0.3));
    var color = mix(color1, color2, smoothstep(0.4, 0.6, final_val));

    // Boost brightness and contrast for intensity
    color = pow(color, vec3<f32>(0.8)) * 1.5;

    // --- Feedback and Output ---
    // Reaction-diffusion style feedback: sharpen and blend
    let sharpened_history = clamp(history * 1.1 - 0.05, vec3<f32>(0.0), vec3<f32>(1.0));
    let final_color = mix(color, sharpened_history, 0.95);

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(final_color, 1.0));
}
