struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>
};

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = textureDimensions(writeTexture);

    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let aspect = f32(res.x) / f32(res.y);
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    // Zoom config shifts
    p += u.zoom_config.yz;

    // Density
    let density = max(1.0, 5.0 + u.zoom_params.y * 5.0);
    let tile_uv = p * density;
    let tile_id = floor(tile_uv);
    var tile_local = fract(tile_uv) * 2.0 - 1.0;

    // Fractal logic
    var z = tile_local;
    let base_c = vec2<f32>(
        sin(tile_id.x * 0.1 + u.config.x * 0.5),
        cos(tile_id.y * 0.1 + u.config.x * 0.5)
    );

    // Iterations driven by u.config.y (audio) and u.zoom_params.x
    let iter = i32(max(5.0, 10.0 + u.zoom_params.x * 10.0 + u.config.y * 5.0));
    var n = 0;
    for (var i = 0; i < 20; i++) {
        if (i >= iter) { break; }
        z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + base_c;
        if (length(z) > 4.0) { break; }
        n++;
    }

    let f_val = f32(n) / f32(iter);
    let color_idx = u32(f_val * 255.0) % 256u;
    let col = plasmaBuffer[color_idx].rgb;

    // Store tile parameters in dataTextureA
    textureStore(dataTextureA, coords, vec4<f32>(tile_id, f_val, 1.0));

    // Write final color
    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}