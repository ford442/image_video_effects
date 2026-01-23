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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// 2D Noise
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Procedural Glyph drawing
fn draw_glyph(uv: vec2<f32>, index: i32) -> f32 {
    // uv is 0.0 to 1.0 inside the cell
    let c = uv - 0.5;
    var d = 1.0;

    // 0: Dot
    if (index == 0) {
        d = length(c) - 0.2;
    }
    // 1: Vertical Line
    else if (index == 1) {
        d = abs(c.x) - 0.1;
    }
    // 2: Horizontal Line
    else if (index == 2) {
        d = abs(c.y) - 0.1;
    }
    // 3: Plus
    else if (index == 3) {
        d = min(abs(c.x), abs(c.y)) - 0.08;
    }
    // 4: Diagonal /
    else if (index == 4) {
        d = abs(c.x + c.y) - 0.1;
    }
    // 5: Diagonal \
    else if (index == 5) {
        d = abs(c.x - c.y) - 0.1;
    }
    // 6: X
    else if (index == 6) {
        d = min(abs(c.x + c.y), abs(c.x - c.y)) - 0.08;
    }
    // 7: Box
    else {
        d = max(abs(c.x), abs(c.y)) - 0.4;
        d = abs(d) - 0.05; // Outline
    }

    return 1.0 - smoothstep(0.0, 0.05, d);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    // Grid Setup
    let grid_dims = vec2<f32>(80.0, 45.0); // Characters
    let cell_uv = fract(uv * grid_dims);
    let cell_id = floor(uv * grid_dims);

    // Flow Field
    let noise = hash22(cell_id * 0.1 + vec2<f32>(time * 0.1));
    var flow = (noise - 0.5) * 2.0; // Direction

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let cell_center_uv = (cell_id + 0.5) / grid_dims;
    let to_mouse = cell_center_uv - mouse;
    let dist_mouse = length(to_mouse);

    // Repel from mouse
    let repel = normalize(to_mouse) * smoothstep(0.3, 0.0, dist_mouse);
    flow += repel * 2.0;

    // Sample texture at offset position (simulate flow source)
    // We sample 'upstream'
    let sample_pos = cell_center_uv - flow * 0.05;
    let color = textureSampleLevel(readTexture, u_sampler, clamp(sample_pos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let gray = dot(color, vec3<f32>(0.299, 0.587, 0.114));

    // Determine Glyph based on brightness
    let num_glyphs = 8;
    let glyph_idx = i32(gray * f32(num_glyphs));

    let shape = draw_glyph(cell_uv, glyph_idx);

    // Green phosphor look or keep original color?
    // Let's do a mix: Tint green but keep some hue.
    let tint = vec3<f32>(0.2, 1.0, 0.4);
    let final_color = mix(color, tint, 0.7) * shape;

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(final_color, 1.0));
}
