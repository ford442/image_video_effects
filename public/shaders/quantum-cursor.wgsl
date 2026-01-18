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

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let radius = mix(0.05, 0.5, u.zoom_params.x);
    let mosaic_scale = mix(50.0, 5.0, u.zoom_params.y); // 50 = small blocks, 5 = huge blocks
    let aberration = u.zoom_params.z * 0.05;
    let chaos = u.zoom_params.w;

    let dist_vec = (uv - mouse);
    let dist = length(dist_vec * vec2(aspect, 1.0));

    var finalColor = vec4<f32>(0.0);

    // Soft edge for the effect
    let mask = smoothstep(radius, radius * 0.8, dist);

    // Sample Original
    let colOrig = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Sample Effect
    // 1. Mosaic UV
    let blocks = resolution / mosaic_scale;
    let blockUV = floor(uv * blocks) / blocks + (0.5 / blocks); // Center of block

    // Random jitter per block based on chaos
    let blockHash = hash12(blockUV + u.config.x * 0.01 * chaos);
    let jitter = (blockHash - 0.5) * 0.1 * chaos;
    let activeBlockUV = blockUV + jitter;

    // Aberration on Block UV
    let r = textureSampleLevel(readTexture, u_sampler, activeBlockUV + vec2(aberration, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, activeBlockUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, activeBlockUV - vec2(aberration, 0.0), 0.0).b;
    var colEffect = vec4<f32>(r, g, b, 1.0);

    if (chaos > 0.2) {
        // Color channel shuffle based on hash
         if (blockHash > 0.6) {
            colEffect = vec4(colEffect.g, colEffect.b, colEffect.r, 1.0);
         } else if (blockHash < 0.3) {
            colEffect = vec4(colEffect.b, colEffect.r, colEffect.g, 1.0);
         }

         // Inversion
         if (chaos > 0.7 && blockHash > 0.8) {
             colEffect = vec4(1.0 - colEffect.rgb, 1.0);
         }
    }

    finalColor = mix(colOrig, colEffect, mask);

    textureStore(writeTexture, global_id.xy, finalColor);

    // Depth pass
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
