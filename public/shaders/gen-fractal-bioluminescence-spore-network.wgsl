// ----------------------------------------------------------------
// Fractal Bioluminescence Spore-Network
// Category: generative
// ----------------------------------------------------------------
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

fn rot2d(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

fn map(p_in: vec3<f32>, complexity: f32, time: f32, audio_react: f32) -> f32 {
    var p = p_in;
    let iters = i32(clamp(complexity, 1.0, 10.0));
    var scale = 1.0;

    for (var i = 0; i < iters; i = i + 1) {
        p = abs(p) - vec3<f32>(1.5, 1.5, 1.5) * scale;
        let p_xy = rot2d(time * 0.1 + f32(i)) * vec2<f32>(p.x, p.y);
        p = vec3<f32>(p_xy.x, p_xy.y, p.z);

        let p_yz = rot2d(time * 0.15) * vec2<f32>(p.y, p.z);
        p = vec3<f32>(p.x, p_yz.x, p_yz.y);

        scale *= 0.8;
    }

    return length(p) - 0.2 * scale;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * vec2<f32>(dimensions)) / f32(dimensions.y);
    let time = u.config.x;

    let spore_density = u.zoom_params.x;
    let network_complexity = u.zoom_params.y;
    let bio_intensity = u.zoom_params.z;
    let audio_react = u.zoom_params.w;

    let audio = u.config.y;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let mouse_dist = length(uv - mouse);
    let injection = (1.0 / (1.0 + mouse_dist * 10.0)) * u.zoom_config.w;

    var ro = vec3<f32>(0.0, 0.0, -5.0 + time * 0.2);
    var rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var d = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 64; i = i + 1) {
        let p = ro + rd * t;
        d = map(p, network_complexity + injection * 2.0, time + audio * audio_react, audio_react);

        if (d < 0.01) {
            break;
        }

        t += d * 0.5;
        glow += (0.01 / (0.01 + d * d)) * spore_density;

        if (t > 20.0) {
            break;
        }
    }

    let col_base = vec3<f32>(0.1, 0.5, 0.8);
    let col_hot = vec3<f32>(1.0, 0.9, 0.2);

    var final_col = mix(col_base, col_hot, glow * 0.1) * glow * bio_intensity * 0.2;
    final_col += vec3<f32>(0.2, 0.8, 0.5) * injection * 2.0;

    textureStore(writeTexture, id.xy, vec4<f32>(final_col, 1.0));
}
