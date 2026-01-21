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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Map pixel to complex plane
    let aspect = resolution.x / resolution.y;
    var z = (uv - 0.5) * vec2<f32>(2.5 * aspect, 2.5);

    // Mouse controls Julia constant
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let julia_c = (mouse - 0.5) * vec2<f32>(2.0, 2.0);

    // Gentle animation
    let animated_c = julia_c + vec2<f32>(sin(time * 0.1) * 0.1, cos(time * 0.15) * 0.1);

    // Julia iteration
    var iter = 0;
    let max_iter = 120;

    for (iter = 0; iter < max_iter; iter++) {
        if (dot(z, z) > 4.0) { break; }
        z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + animated_c;
    }

    // Smooth coloring
    let smooth_iter = f32(iter) - log2(log2(dot(z, z))) + 4.0;
    let t = smooth_iter / f32(max_iter);

    // Deep space to electric blue gradient
    let color = mix(
        vec3<f32>(0.05, 0.05, 0.1),
        mix(vec3<f32>(0.1, 0.3, 0.8), vec3<f32>(1.0, 0.95, 0.8), t),
        t * 0.8
    );

    // Glow for points in the set
    let glow = select(0.0, 1.0, iter == max_iter);
    let final_color = color + vec3<f32>(0.3, 0.2, 0.5) * glow * 0.5;

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(t, glow, 0.0, 1.0));
}
