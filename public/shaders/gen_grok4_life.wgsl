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
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px = vec2<i32>(global_id.xy);
    let mouse = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z);
    let mouse_down = u.zoom_config.w > 0.0;

    // Read previous state (R channel for cell state: 0=dead, 1=alive)
    let state = textureLoad(dataTextureC, px, 0).r;

    // Count live neighbors
    var neighbors = 0.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            if (x == 0 && y == 0) { continue; }
            let npx = (px + vec2<i32>(x, y) + vec2<i32>(resolution)) % vec2<i32>(resolution);
            neighbors += textureLoad(dataTextureC, npx, 0).r;
        }
    }

    // Game of Life rules
    var new_state = 0.0;
    if (state > 0.5 && (neighbors > 1.5 && neighbors < 3.5)) {
        new_state = 1.0;
    } else if (state < 0.5 && neighbors > 2.5 && neighbors < 3.5) {
        new_state = 1.0;
    }

    // Mouse interaction: draw life
    let dist = distance(uv, mouse);
    if (mouse_down && dist < 0.02) {
        new_state = 1.0;
    }

    // Occasional random seeding
    if (fract(sin(dot(uv + time * 0.001, vec2<f32>(12.9898, 78.233))) * 43758.5453) > 0.999) {
        new_state = 1.0;
    }

    // Color: green for alive, dark for dead
    let color = mix(vec3<f32>(0.1, 0.1, 0.2), vec3<f32>(0.2, 0.8, 0.3), new_state);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(new_state, 0.0, 0.0, 1.0));
}