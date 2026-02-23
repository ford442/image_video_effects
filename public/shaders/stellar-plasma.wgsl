// ═══════════════════════════════════════════════════════════════
//  Stellar Plasma - Endless procedural cosmic nebula using domain-warped FBM
//  Category: generative
//  Features: generative, procedural, loops
//  Author: Gemini 3.1 Pro Vertex
// ═══════════════════════════════════════════════════════════════

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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Pseudo-random hash
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 2D Value Noise
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u_f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u_f.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u_f.x),
        u_f.y
    );
}

// Fractional Brownian Motion (Organic cloud shapes)
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let shift = vec2<f32>(100.0, 100.0);
    // Rotation matrix to reduce artifacting in noise layering
    let c = cos(0.5);
    let s = sin(0.5);
    let rot = mat2x2<f32>(vec2<f32>(c, s), vec2<f32>(-s, c));
    
    var p_mut = p;
    for (var i: i32 = 0; i < 6; i++) {
        v += a * noise(p_mut);
        p_mut = rot * p_mut * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Hue shift function to cycle colors based on parameters
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    
    // Boundary check
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) {
        return;
    }

    // Normalize UV coordinates (-1.0 to 1.0) and fix aspect ratio
    var uv = vec2<f32>(global_id.xy) / res;
    var p = uv * 2.0 - 1.0;
    p.x *= res.x / res.y;

    // Parameters mapped from UI
    // zoom_params: x = hue shift, y = speed, z = zoom scale, w = mouse influence
    let hue_offset = u.zoom_params.x * 6.28318; 
    let speed = mix(0.5, 2.0, u.zoom_params.y);
    let scale = mix(1.0, 4.0, u.zoom_params.z);
    let mouse_influence = u.zoom_params.w;

    let time = u.config.x * speed;

    // Mouse Interaction (from zoom_config.yz)
    var mouse_pos = u.zoom_config.yz * 2.0 - 1.0;
    mouse_pos.x *= res.x / res.y;
    let dist_to_mouse = length(p - mouse_pos);
    let interaction = exp(-dist_to_mouse * 3.0) * mouse_influence;

    // Apply scaling and interaction displacement
    var q_pos = p * scale + interaction;

    // Domain Warping Step 1
    var q = vec2<f32>(
        fbm(q_pos + vec2<f32>(0.0, time * 0.2)),
        fbm(q_pos + vec2<f32>(1.0, 2.0) + time * 0.2)
    );

    // Domain Warping Step 2 (Nested FBM)
    var r = vec2<f32>(
        fbm(q_pos + 4.0 * q + vec2<f32>(1.7, 9.2) + time * 0.15),
        fbm(q_pos + 4.0 * q + vec2<f32>(8.3, 2.8) + time * 0.126)
    );

    // Final Noise Value
    let f = fbm(q_pos + 4.0 * r);

    // Color Palette Mixing
    var base_col1 = vec3<f32>(0.1, 0.6, 0.7); // Cyan
    var base_col2 = vec3<f32>(0.7, 0.2, 0.5); // Magenta
    var base_col3 = vec3<f32>(0.0, 0.0, 0.2); // Deep Blue
    var base_col4 = vec3<f32>(1.0, 0.9, 0.5); // Bright Yellow/White glow

    // Construct color based on warping layers
    var color = mix(base_col1, base_col2, clamp(f * f * 4.0, 0.0, 1.0));
    color = mix(color, base_col3, clamp(length(q), 0.0, 1.0));
    color = mix(color, base_col4, clamp(length(r.x), 0.0, 1.0));

    // Apply hue shift from params
    color = hueShift(color, hue_offset + time * 0.1);

    // Enhance contrast and glow
    color = (f * f * f + 0.6 * f * f + 0.5 * f) * color;

    // Output final color
    let final_color = vec4<f32>(color, 1.0);
    textureStore(writeTexture, global_id.xy, final_color);

    // Write empty depth (required for the pipeline, but flat for generative)
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
