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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=MosaicSize, y=RevealRadius, z=EdgeSoftness, w=Unused
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Params
    let mosaicSize = mix(20.0, 200.0, u.zoom_params.x);
    let radius = u.zoom_params.y * 0.5;
    let softness = u.zoom_params.z;

    let mouse = u.zoom_config.yz;
    let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

    // Calculate Mosaic UV
    // Blocks
    let uvPix = floor(uv * mosaicSize) / mosaicSize;
    // Center of block
    let uvCenter = uvPix + (0.5 / mosaicSize);

    // Sample Mosaic
    let colMosaic = textureSampleLevel(readTexture, non_filtering_sampler, uvCenter, 0.0);

    // Sample Full Res
    let colFull = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mask
    // 0 = Mosaic, 1 = Full
    // If dist < radius, show Full.
    let mask = 1.0 - smoothstep(radius, radius + 0.1 + softness * 0.2, dist);

    let finalColor = mix(colMosaic, colFull, mask);

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
