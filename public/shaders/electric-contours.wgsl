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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Correct aspect ratio for mouse interaction
    let aspect = resolution.x / resolution.y;
    let mouse_uv = u.zoom_config.yz; // Mouse is already in 0-1 range from renderer? Usually yes.

    // Sobel kernels
    let texel = 1.0 / resolution;
    let t = u.zoom_config.x;

    let c00 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, -1.0), 0.0).rgb);
    let c10 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 0.0, -1.0), 0.0).rgb);
    let c20 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 1.0, -1.0), 0.0).rgb);
    let c01 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0,  0.0), 0.0).rgb);
    let c21 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 1.0,  0.0), 0.0).rgb);
    let c02 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0,  1.0), 0.0).rgb);
    let c12 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 0.0,  1.0), 0.0).rgb);
    let c22 = luminance(textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>( 1.0,  1.0), 0.0).rgb);

    let sx = -1.0 * c00 - 2.0 * c10 - 1.0 * c20 + 1.0 * c02 + 2.0 * c12 + 1.0 * c22;
    let sy = -1.0 * c00 - 2.0 * c01 - 1.0 * c02 + 1.0 * c20 + 2.0 * c21 + 1.0 * c22;

    let edge = sqrt(sx*sx + sy*sy);

    // Mouse influence
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse_uv * vec2<f32>(aspect, 1.0));
    let mouse_influence = smoothstep(0.5, 0.0, dist); // Stronger near mouse

    // Electric noise
    let noise = hash12(uv * 50.0 + vec2<f32>(t * 2.0));
    let spark = smoothstep(0.9, 1.0, noise * mouse_influence);

    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Dynamic palette
    let color_a = vec3<f32>(0.2, 0.8, 1.0); // Cyan
    let color_b = vec3<f32>(1.0, 0.2, 0.8); // Magenta
    let mix_factor = 0.5 + 0.5 * sin(t * 3.0 + dist * 10.0);
    let edge_color = mix(color_a, color_b, mix_factor);

    // Combine
    // If edge is strong, use edge color + spark. Otherwise base image dimmed.
    let final_edge = smoothstep(0.1, 0.4, edge);
    let result = mix(base_color * 0.2, edge_color + vec3<f32>(spark), final_edge);

    // Add extra glow near mouse
    let glow = mouse_influence * 0.3 * edge_color;

    textureStore(writeTexture, global_id.xy, vec4<f32>(result + glow, 1.0));
}
