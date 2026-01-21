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

    let num_states = 24.0;
    let threshold = 2;

    // Read state (0-23)
    let current_state = i32(textureLoad(dataTextureC, px, 0).r * num_states);
    let next_state = (current_state + 1) % i32(num_states);

    // Count neighbors with next state
    var count = 0;
    let n  = i32(textureLoad(dataTextureC, px + vec2<i32>( 0,  1), 0).r * num_states);
    let s  = i32(textureLoad(dataTextureC, px + vec2<i32>( 0, -1), 0).r * num_states);
    let e  = i32(textureLoad(dataTextureC, px + vec2<i32>( 1,  0), 0).r * num_states);
    let w  = i32(textureLoad(dataTextureC, px + vec2<i32>(-1,  0), 0).r * num_states);
    let ne = i32(textureLoad(dataTextureC, px + vec2<i32>( 1,  1), 0).r * num_states);
    let nw = i32(textureLoad(dataTextureC, px + vec2<i32>(-1,  1), 0).r * num_states);
    let se = i32(textureLoad(dataTextureC, px + vec2<i32>( 1, -1), 0).r * num_states);
    let sw = i32(textureLoad(dataTextureC, px + vec2<i32>(-1, -1), 0).r * num_states);

    count += select(0, 1, n == next_state);
    count += select(0, 1, s == next_state);
    count += select(0, 1, e == next_state);
    count += select(0, 1, w == next_state);
    count += select(0, 1, ne == next_state);
    count += select(0, 1, nw == next_state);
    count += select(0, 1, se == next_state);
    count += select(0, 1, sw == next_state);

    // Advance state if enough neighbors
    var new_state = f32(current_state);
    if (count >= threshold) {
        new_state = f32(next_state);
    }

    // Mouse creates colorful disturbance
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // FIX: Inverted smoothstep
    // Original: smoothstep(0.2, 0.0, distance)
    let mouse_influence = (1.0 - smoothstep(0.0, 0.2, distance(uv, mouse))) * u.zoom_config.w;

    if (mouse_influence > 0.0) {
        let random = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + time) * 43758.5453);
        new_state = mix(new_state, random * num_states, mouse_influence);
    }

    // Color mapping - rainbow cycle
    let hue = new_state / num_states * 6.28318;
    let color = 0.5 + 0.5 * vec3<f32>(
        sin(hue),
        sin(hue + 2.094),
        sin(hue + 4.188)
    );

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(new_state / num_states, 0.0, 0.0, 1.0));
}
