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

fn palette(t: f32) -> vec3<f32> {
    // Spectral / Iridescent palette
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }

    let pixel_pos = vec2<f32>(gid.xy);
    let uv = pixel_pos / resolution;
    // Fix aspect ratio for geometric calculations
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    let mouse = u.zoom_config.yz;
    // Map mouse to center offset.
    // If mouse is at 0,0 (start), center it.
    var center = (mouse * 2.0 - 1.0);
    center.x *= aspect;
    if (length(mouse) < 0.01) {
        center = vec2<f32>(0.0);
    }

    // Shift P by center
    var local_p = p - center;

    // Rotate slowly by time
    let time = u.config.x;
    let angle = time * 0.1;
    let s = sin(angle);
    let c = cos(angle);
    let rot = mat2x2<f32>(c, -s, s, c);
    local_p = rot * local_p;

    // Hopper Crystal Logic
    // Concentric square steps
    let num_steps = 10.0;
    let dist = max(abs(local_p.x), abs(local_p.y)); // Chebyshev distance (square)

    // Quantize distance
    let step_idx = floor(dist * num_steps);
    let step_t = fract(dist * num_steps);

    // Determine normal for this step.
    // Normal roughly points towards center but angled up.
    var normal = vec3<f32>(0.0, 0.0, 1.0);
    if (abs(local_p.x) > abs(local_p.y)) {
        // X face
        let sign_x = sign(local_p.x);
        normal = normalize(vec3<f32>(sign_x, 0.0, 0.5));
    } else {
        // Y face
        let sign_y = sign(local_p.y);
        normal = normalize(vec3<f32>(0.0, sign_y, 0.5));
    }

    // View vector
    let view_dir = vec3<f32>(0.0, 0.0, 1.0);

    // Iridescence / Thin Film
    // Based on N dot V and layer thickness (step_idx)
    let ndotv = max(0.0, dot(normal, view_dir));
    let irid_t = ndotv + step_idx * 0.15 + u.config.x * 0.1; // Add time for shifting colors

    let iridescent_color = palette(irid_t);

    // UV Sampling
    // Refract the texture sample based on the normal
    // Mouse X controls intensity
    let refraction_scale = 0.02 * (1.0 + mouse.x * 5.0);
    var refracted_uv = uv - normal.xy * refraction_scale * (step_idx + 1.0);

    // Clamp UV
    refracted_uv = clamp(refracted_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    let tex_color = textureSampleLevel(readTexture, u_sampler, refracted_uv, 0.0).rgb;

    // Combine
    // Use the step pattern to mix between raw texture and iridescent sheen
    // Edges of steps (step_t close to 0 or 1) can be highlighted
    let edge_highlight = smoothstep(0.0, 0.1, step_t) * smoothstep(1.0, 0.9, step_t);

    // Mix
    var final_color = mix(tex_color, tex_color * iridescent_color * 1.5, 0.6);

    // Add specular highlight on edges
    let highlight = (1.0 - edge_highlight) * 0.5;
    final_color += vec3<f32>(highlight);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(final_color, 1.0));
}
