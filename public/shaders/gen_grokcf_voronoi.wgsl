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

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let h = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(h) * 43758.5453);
}

fn hash3(p: vec2<f32>) -> vec3<f32> {
    let h = vec3<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)), dot(p, vec2<f32>(419.2, 371.9)));
    return fract(sin(h) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.02;
    let mouse = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z);

    var min_dist = 1e10;
    var closest_color = vec3<f32>(0.0);

    // Sample 8 points
    for (var i = 0; i < 8; i++) {
        let fi = f32(i);
        let seed = vec2<f32>(fi, time * 0.1);
        let point = hash2(uv * 10.0 + seed) * 2.0 - 1.0 + mouse * 0.5;
        let dist = distance(uv, point);
        if dist < min_dist {
            min_dist = dist;
            closest_color = hash3(point + time);
        }
    }

    // Color based on distance and closest point
    let color = closest_color * (1.0 - min_dist * 5.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}