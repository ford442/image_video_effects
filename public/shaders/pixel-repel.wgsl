// Pixel Repeller - Pushes pixels away from mouse with chromatic aberration
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let radius = max(u.zoom_params.x, 0.05);
    let strength = u.zoom_params.y;
    let aberration = u.zoom_params.z;
    let smoothing = u.zoom_params.w;

    var displacement = vec2<f32>(0.0);

    if (mousePos.x >= 0.0 && mousePos.y >= 0.0) {
        let aspect = resolution.x / resolution.y;
        let dVec = uv - mousePos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        // Repel force: stronger when closer
        let t = smoothstep(radius, radius * (1.0 - smoothing * 0.5), dist);
        let dir = normalize(dVec);
        displacement = dir * t * strength * 0.3;
    }

    // Chromatic aberration based on displacement
    let rUV = clamp(uv - displacement * (1.0 + aberration), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv - displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - displacement * (1.0 - aberration), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    let color = vec4<f32>(r, g, b, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
