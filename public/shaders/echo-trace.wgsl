@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 32>,
};

fn hue_shift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cos_angle = cos(shift);
    return vec3<f32>(color * cos_angle + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cos_angle));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);

    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) {
        return;
    }

    let uv = vec2<f32>(coords) / vec2<f32>(dimensions);

    // Parameters
    let decay_rate = u.zoom_params.x; // 0.8 to 0.99
    let brush_size = u.zoom_params.y; // 0.05 to 0.5
    let shift_amount = u.zoom_params.z; // 0.0 to 0.5

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let aspect = u.config.z / u.config.w;
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Read Inputs
    let current_video = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let history = textureLoad(dataTextureC, coords, 0);

    // Logic:
    // 1. Decay the history slightly
    var new_history = history.rgb * decay_rate;

    // 2. Apply Hue Shift to history if requested
    if (shift_amount > 0.0) {
        new_history = hue_shift(new_history, shift_amount);
    }

    // 3. If mouse is near, paint with current video
    if (dist < brush_size) {
        let alpha = smoothstep(brush_size, brush_size * 0.5, dist);
        // Paint: mix history with current video based on brush strength
        new_history = mix(new_history, current_video.rgb, alpha);
    }

    // Output
    let out_color = vec4<f32>(new_history, 1.0);

    textureStore(writeTexture, coords, out_color);
    textureStore(dataTextureA, coords, out_color);
}
