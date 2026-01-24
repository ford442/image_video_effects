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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Params
    let sortThreshold = u.zoom_params.x;
    let radius = u.zoom_params.y;
    let direction = u.zoom_params.z; // 0=Vert, 1=Horiz
    let smoothness = u.zoom_params.w; // Defines how "blocky" the sort looks

    // Calculate mask
    let dVec = (uv - mouse) * vec2(aspect, 1.0);
    let dist = length(dVec);
    let mask = 1.0 - smoothstep(radius, radius + 0.1, dist);

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // If inside mask, apply effect
    if (mask > 0.01) {
        // Simplified Pixel Sort / Streak Effect
        // We look for a bright pixel nearby and extend it

        // Sampling loop to simulate sorting
        var bestVal = -1.0;
        var bestColor = color;

        let samples = 10;
        let stride = mix(0.001, 0.05, smoothness);

        var dirVec = vec2(0.0, 1.0);
        if (direction > 0.5) { dirVec = vec2(1.0, 0.0); }

        // Sample "behind" the current pixel (up or left)
        for (var i = 1; i <= samples; i++) {
             let offset = f32(i) * stride * dirVec;
             let sUV = uv - offset; // Look back

             // Check bounds
             if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) { continue; }

             let sColor = textureSampleLevel(readTexture, u_sampler, sUV, 0.0);
             let lum = dot(sColor.rgb, vec3(0.299, 0.587, 0.114));

             // Threshold logic: if neighbor is bright enough, it streaks down
             if (lum > sortThreshold) {
                  // We found a bright pixel above. It should cover this pixel.
                  // But only if this pixel is darker?
                  // Let's just take the max luma found in the streak path
                  if (lum > bestVal) {
                      bestVal = lum;
                      bestColor = sColor;
                  }
             }
        }

        // Mix original and sorted based on mask
        // Also maybe original pixel is brighter than the streak?
        let myLum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        if (bestVal > myLum) {
            color = mix(color, bestColor, mask);
        }
    }

    // Outside mask: maybe blur or dim?
    // User description said "Image is hidden/blurred".
    // Let's dim the outside.
    let outsideDim = mix(0.1, 1.0, mask);
    color = vec4(color.rgb * outsideDim, 1.0);

    textureStore(writeTexture, global_id.xy, color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
