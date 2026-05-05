// ----------------------------------------------------------------
// Magnetic Field Warp
// Category: generative
// ----------------------------------------------------------------

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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=DiffusionA, y=DiffusionB, z=Feed, w=Kill
    ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(u.config.z, u.config.w);

    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let time = u.config.x;
    let audio = u.config.y;

    // Mouse dipole
    let mouse = u.zoom_config.yz;
    let delta = uv - mouse;
    let dist = length(delta);
    let warp_strength = u.zoom_params.x * 2.0;

    // Quadratic distortion based on mouse and audio
    let field = normalize(delta) * (warp_strength / (dist * dist + 0.1)) * audio;
    let warped_uv = uv + field * 0.05;

    // Fetch image
    let read_coords = vec2<i32>(warped_uv * vec2<f32>(res));
    let color = textureLoad(readTexture, read_coords, 0);

    // Spectral remapping
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let spectral_idx = u32(clamp(luma + audio * 0.5, 0.0, 1.0) * 255.0) % 256u;
    let plasma = plasmaBuffer[spectral_idx];

    let final_color = mix(color, plasma, u.zoom_params.y);

    textureStore(writeTexture, coords, final_color);
}
