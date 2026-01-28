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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let threshold = u.zoom_params.x; // 0.5 to 0.95
    let flareIntensity = u.zoom_params.y * 5.0;
    let stretch = u.zoom_params.z * 0.1; // Horizontal stretch factor
    let colorShift = u.zoom_params.w;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Calculate Mouse Influence Mask
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));
    let influence = smoothstep(0.5, 0.0, dist); // Only generate flares near mouse (0.5 radius)

    if (influence <= 0.01) {
        textureStore(writeTexture, global_id.xy, baseColor);
        let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
        return;
    }

    // Generate Flares
    // We want to sample bright pixels that are horizontally aligned with current pixel,
    // but within the mouse radius.

    // Instead of gathering samples *for* the flare, we are simulating the flare *at* the pixel.
    // So we need to look at neighbors horizontally.

    var flareAccum = vec3<f32>(0.0);
    let samples = 10;

    // Anamorphic lens flares are horizontal streaks.
    // So if I am at pixel P, I am affected by bright pixels P_left and P_right.
    // The influence decays with distance.

    for (var i = -samples; i <= samples; i++) {
        if (i == 0) { continue; }

        // Offset in UV space
        // Large offset to simulate long streaks
        let offset = f32(i) * stretch;
        let sampleUV = uv + vec2<f32>(offset, 0.0);

        if (sampleUV.x < 0.0 || sampleUV.x > 1.0) { continue; }

        let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));

        if (lum > threshold) {
             // Calculate weight based on distance
             let weight = 1.0 / (abs(f32(i)) + 1.0);

             // Tint
             // Anamorphic is usually blue
             let tint = mix(vec3<f32>(0.5, 0.7, 1.0), vec3<f32>(1.0, 0.8, 0.5), colorShift);

             // Additional mask: The source pixel must also be near the mouse?
             // The prompt says "Generate flares from bright pixels near the mouse".
             // So sampleUV must be near mouse.
             let sourceDist = distance(vec2<f32>(sampleUV.x * aspect, sampleUV.y), vec2<f32>(mouse.x * aspect, mouse.y));
             let sourceInfluence = smoothstep(0.5, 0.0, sourceDist);

             flareAccum += col * weight * tint * sourceInfluence;
        }
    }

    let finalColor = baseColor.rgb + flareAccum * flareIntensity * influence;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
