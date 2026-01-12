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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let gridSize = u.zoom_params.x * 50.0 + 5.0; // Cells per axis
    let shiftAmt = u.zoom_params.y * 0.05;
    let falloff = u.zoom_params.z;
    let angleParam = u.zoom_params.w * 6.28;

    let aspect = resolution.x / resolution.y;

    // Grid coordinates
    let gridUV = floor(uv * gridSize);
    // Center of grid cell in UV space
    let cellCenter = (gridUV + 0.5) / gridSize;

    // Distance from cell center to mouse
    let distVec = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Effect strength falls off with distance
    // Invert falloff param so 1.0 = large radius
    let radius = falloff * 1.5;
    let strength = smoothstep(radius, max(0.0, radius - 0.5), dist);

    // Shift vector
    let shiftVec = vec2<f32>(cos(angleParam), sin(angleParam)) * shiftAmt * strength;

    // Chromatic aberration
    let r = textureSampleLevel(readTexture, u_sampler, uv - shiftVec, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + shiftVec, 0.0).b;
    let a = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

    var color = vec4<f32>(r, g, b, a);

    // Optional: Grid overlay for style, fades out with strength too?
    // Or just subtle everywhere
    let f = fract(uv * gridSize);
    let border = step(0.95, f.x) + step(0.95, f.y);

    // Darken borders slightly where effect is active
    color = color * (1.0 - border * 0.2 * strength);

    textureStore(writeTexture, global_id.xy, color);
}
