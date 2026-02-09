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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.05;
    let mouse = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z);

    // Multiple wave layers
    let wave1 = sin(uv.x * 6.28318 * 5.0 + time) * sin(uv.y * 6.28318 * 5.0 + time * 1.2);
    let wave2 = sin(uv.x * 6.28318 * 8.0 + time * 0.8) * sin(uv.y * 6.28318 * 8.0 + time * 1.5);
    let wave3 = sin(uv.x * 6.28318 * 12.0 + time * 1.3) * sin(uv.y * 6.28318 * 12.0 + time * 2.1);

    let interference = wave1 + wave2 * 0.7 + wave3 * 0.4;

    // Mouse modulation
    let dist = distance(uv, mouse);
    let mod = 1.0 + exp(-dist * 20.0) * 2.0;
    let modulated = interference * mod;

    // Color from interference
    let r = sin(modulated * 3.0 + 0.0) * 0.5 + 0.5;
    let g = sin(modulated * 3.0 + 2.094) * 0.5 + 0.5;
    let b = sin(modulated * 3.0 + 4.188) * 0.5 + 0.5;

    var color = vec3<f32>(r, g, b);

    // Add some glow
    color += 0.1 / (1.0 + dist * 5.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}