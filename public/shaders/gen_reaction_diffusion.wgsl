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
    let px = vec2<i32>(global_id.xy);

    // Gray-Scott parameters - tweak for different patterns
    var feed_rate = 0.055;      // Food supply for A (try 0.02-0.08)
    let kill_rate = 0.062;      // Removal rate for B (try 0.05-0.07)
    let diffusion_a = 0.2097;   // Diffusion rate of A
    let diffusion_b = 0.105;    // Diffusion rate of B

    // Read chemical concentrations (A in R, B in G)
    var state = textureLoad(dataTextureC, px, 0).rg;

    // Initialize: A = 1, B = 0
    if (state.r < 0.01 && state.g < 0.01) {
        state = vec2<f32>(1.0, 0.0);
    }

    // Sample neighbors for Laplacian
    let n  = textureLoad(dataTextureC, px + vec2<i32>( 0,  1), 0).rg;
    let s  = textureLoad(dataTextureC, px + vec2<i32>( 0, -1), 0).rg;
    let e  = textureLoad(dataTextureC, px + vec2<i32>( 1,  0), 0).rg;
    let w  = textureLoad(dataTextureC, px + vec2<i32>(-1,  0), 0).rg;
    let ne = textureLoad(dataTextureC, px + vec2<i32>( 1,  1), 0).rg;
    let nw = textureLoad(dataTextureC, px + vec2<i32>(-1,  1), 0).rg;
    let se = textureLoad(dataTextureC, px + vec2<i32>( 1, -1), 0).rg;
    let sw = textureLoad(dataTextureC, px + vec2<i32>(-1, -1), 0).rg;

    let laplacian = (n + s + e + w + 0.25 * (ne + nw + se + sw)) - 3.0 * state;

    // Mouse injects B chemical
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // FIX: Use inverted smoothstep to avoid undefined behavior if edge0 > edge1
    // Original intent: smoothstep(0.1, 0.0, distance) -> 1 near center, 0 far
    // New: 1.0 - smoothstep(0.0, 0.1, distance)
    let mouse_influence = (1.0 - smoothstep(0.0, 0.1, distance(uv, mouse))) * u.zoom_config.w * 0.5;

    // Reaction-diffusion
    let a = state.r;
    let b = state.g;
    let reaction = a * b * b;

    let da = diffusion_a * laplacian.r - reaction + feed_rate * (1.0 - a);
    let db = diffusion_b * laplacian.g + reaction - (kill_rate + feed_rate) * b;

    var new_a = a + da * 0.5;
    var new_b = b + db * 0.5 + mouse_influence;

    // Visualize: warm orange (A) vs cool cyan (B)
    let color = mix(
        vec3<f32>(1.0, 0.3, 0.1),
        vec3<f32>(0.1, 0.6, 1.0),
        new_b
    ) + vec3<f32>(1.0, 0.8, 0.5) * reaction * 10.0;

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(new_a, new_b, 0.0, 1.0));
}
