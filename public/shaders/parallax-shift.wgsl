struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<f32, 20>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var u_sampler: sampler;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let coords = vec2<i32>(global_id.xy);

    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) {
        return;
    }

    let uv = vec2<f32>(coords) / dims;

    // Parameters
    let depth_strength = (u.zoom_params.x - 0.5) * 0.5; // -0.25 to 0.25
    let aberration = u.zoom_params.y * 0.05; // 0 to 0.05
    let edge_zoom = u.zoom_params.z; // 0 to 1
    let focus_plane = u.zoom_params.w; // 0 to 1

    let mouse_pos = u.zoom_config.yz;
    let aspect = dims.x / dims.y;

    // Depth estimation from luma
    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = dot(base_color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // View direction (Parallax vector)
    let view_vec = (mouse_pos - uv);
    let offset_vec = (uv - mouse_pos) * depth * depth_strength;

    // Apply some edge zoom to prevent seeing edges if we pull in
    let zoom_uv = (uv - 0.5) * (1.0 - edge_zoom * 0.2) + 0.5;

    // Combined UV
    let parallax_uv = zoom_uv + offset_vec;

    // Chromatic Aberration
    // Sample channels at slightly different offsets
    let r_uv = parallax_uv + offset_vec * aberration * 5.0;
    let g_uv = parallax_uv;
    let b_uv = parallax_uv - offset_vec * aberration * 5.0;

    let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    var final_color = vec3<f32>(r, g, b);

    textureStore(writeTexture, coords, vec4<f32>(final_color, 1.0));
}
