// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn complex_mul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

// z^w = exp(w * ln(z))
fn complex_pow(z: vec2<f32>, w: vec2<f32>) -> vec2<f32> {
    let r = length(z);
    if (r < 0.0001) { return vec2<f32>(0.0); }
    let angle = atan2(z.y, z.x);

    // ln(z) = ln(r) + i*angle
    let ln_z = vec2<f32>(log(r), angle);

    // w * ln(z)
    let exponent = complex_mul(w, ln_z);

    // exp(x + iy) = exp(x) * (cos(y) + i*sin(y))
    let mag = exp(exponent.x);
    return vec2<f32>(mag * cos(exponent.y), mag * sin(exponent.y));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }

    // Normalized UV [0, 1]
    let uv = vec2<f32>(gid.xy) / resolution;

    // Center UV [-1, 1] for complex plane, correcting for aspect ratio
    let aspect = resolution.x / resolution.y;
    var z = (uv - 0.5) * 2.0;
    z.x *= aspect;

    // Parameters
    // Scale: Zoom into the complex plane
    let scale = mix(1.0, 5.0, u.zoom_params.x);
    z *= scale;

    // Mouse Interaction -> Complex Exponent w
    // Mouse X: Real part (u), Mouse Y: Imaginary part (v)
    // Default to z^1 if mouse not moved?
    // Mouse coords are typically [0, 1] in u.zoom_config.yz (if I recall correct usage from other shaders)
    // Actually standard is u.zoom_config.y = mouseX (0..1), u.zoom_config.z = mouseY (0..1)

    let mouse = u.zoom_config.yz;

    // Map mouse to a reasonable range for exponents
    // Center (0.5, 0.5) -> Exponent (1.0, 0.0) implies Identity z^1
    // Range: Real [-2, 4], Imag [-2, 2]

    let w_real = (mouse.x - 0.5) * 6.0 + 1.0;
    let w_imag = (mouse.y - 0.5) * 6.0;
    let w = vec2<f32>(w_real, w_imag);

    // Apply z^w
    var result_z = complex_pow(z, w);

    // Add spiral parameter from zoom_params.y
    let spiral = u.zoom_params.y * 3.14159;
    let rotation = vec2<f32>(cos(spiral), sin(spiral));
    result_z = complex_mul(result_z, rotation);

    // Convert back to UV [0, 1]
    // Undo aspect ratio correction
    result_z.x /= aspect;
    var final_uv = result_z * 0.5 + 0.5;

    // Mirror repeat or clamp? Mirror looks more "infinite"
    // final_uv = fract(final_uv); // Tiling
    // Let's use mirror for smoother edges
    // final_uv = abs(fract(final_uv * 0.5) * 2.0 - 1.0); // Triangle wave

    // Simple wrapping
    final_uv = fract(final_uv);

    let color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).rgb;

    // Visualizing the complex plane grid slightly?
    // Maybe fade to black at infinity if result_z is huge
    let dist = length(result_z);
    // let fade = smoothstep(10.0, 5.0, dist);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, 1.0));
}
