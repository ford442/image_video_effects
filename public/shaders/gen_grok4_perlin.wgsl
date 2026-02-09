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

fn permute(x: vec3<f32>) -> vec3<f32> {
    return ((x * 34.0) + 1.0) * x % 289.0;
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(
            mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(
            mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution * 10.0;
    let time = u.config.x * 0.1;
    let mouse = vec2<f32>(u.zoom_config.y * 10.0, (1.0 - u.zoom_config.z) * 10.0);

    // Multi-octave Perlin noise
    var n = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 5; i++) {
        n += amp * noise(vec3<f32>(uv * freq + mouse * 0.2, time * 0.5));
        amp *= 0.5;
        freq *= 2.0;
    }
    n = (n + 1.0) * 0.5;

    // Color as terrain: blue water, green land, white peaks
    var color: vec3<f32>;
    if (n < 0.3) {
        color = vec3<f32>(0.1, 0.2, 0.6) * (n / 0.3);
    } else if (n < 0.7) {
        color = vec3<f32>(0.2, 0.6, 0.3) * ((n - 0.3) / 0.4 + 0.6);
    } else {
        color = vec3<f32>(1.0, 1.0, 1.0) * ((n - 0.7) / 0.3 + 0.8);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}