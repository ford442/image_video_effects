// ═══════════════════════════════════════════════════════════════════
//  Pixel Sort Explorer
//  Category: image
//  Features: pixel-sort, interactive-mouse, upgraded-rgba
// ═══════════════════════════════════════════════════════════════════

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    var mouse = u.zoom_config.yz;
    let aspect = resolution.x / max(resolution.y, 0.001);

    // Params (normalized before use)
    let sortThreshold = clamp(u.zoom_params.x, 0.0, 1.0);
    let radius = clamp(u.zoom_params.y, 0.0, 1.0);
    let direction = clamp(u.zoom_params.z, 0.0, 1.0);
    let smoothness = clamp(u.zoom_params.w, 0.0, 1.0);

    // Calculate mask
    let dVec = (uv - mouse) * vec2(aspect, 1.0);
    let dist = length(dVec);
    let mask = 1.0 - smoothstep(radius, radius + 0.1, dist);

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let origAlpha = color.a;

    if (mask > 0.01) {
        var bestVal = -1.0;
        var bestColor = color;

        let samples = 10;
        let stride = mix(0.001, 0.05, smoothness);

        var dirVec = vec2(0.0, 1.0);
        if (direction > 0.5) { dirVec = vec2(1.0, 0.0); }

        for (var i = 1; i <= samples; i++) {
             let offset = f32(i) * stride * dirVec;
             let sUV = uv - offset;

             if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) { continue; }

             let sColor = textureSampleLevel(readTexture, u_sampler, sUV, 0.0);
             let lum = dot(sColor.rgb, vec3(0.299, 0.587, 0.114));

             if (lum > sortThreshold) {
                  if (lum > bestVal) {
                      bestVal = lum;
                      bestColor = sColor;
                  }
             }
        }

        let myLum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        if (bestVal > myLum) {
            color = mix(color, bestColor, mask);
        }
    }

    let outsideDim = mix(0.1, 1.0, mask);
    color = vec4(color.rgb * outsideDim, origAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
}
