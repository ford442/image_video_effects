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

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let aspectRatio = resolution.x / resolution.y;

    // Mouse is 0-1. UV is 0-1.
    // Distance needs aspect ratio correction if we want circular radius.
    // However, if we don't correct, it matches the screen shape (oval).
    // Let's correct for circular radius.
    let distVec = (uv - mousePos) * vec2<f32>(aspectRatio, 1.0);
    let dist = length(distVec);

    let radius = u.zoom_params.x * 0.5 + 0.1; // 0.1 to 0.6
    let blurStrength = u.zoom_params.y * 10.0;
    let glitchIntensity = u.zoom_params.z;
    let aberration = u.zoom_params.w * 0.05;

    // Smoothstep for focus transition
    let focusMask = smoothstep(radius, radius + 0.1, dist); // 0 inside, 1 outside (increases with distance)

    var finalColor = vec4<f32>(0.0);

    if (focusMask < 0.01) {
        // Inside focus - crisp
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    } else {
        // Outside focus - process

        // 1. Glitch Offset (Blocky)
        var offset = vec2<f32>(0.0);
        if (glitchIntensity > 0.0) {
            let blockSize = 20.0;
            let blockId = floor(uv * blockSize);
            let noise = hash21(blockId + u.config.x * 0.1);
            if (noise < glitchIntensity * 0.2) {
                offset = (vec2<f32>(hash21(blockId), hash21(blockId + 1.0)) - 0.5) * 0.1;
            }
        }

        // 2. Chromatic Aberration + Blur
        // We will sample a few points and average them
        var r_acc = 0.0;
        var g_acc = 0.0;
        var b_acc = 0.0;
        var weight_acc = 0.0;

        let blurSize = blurStrength * focusMask / resolution;

        // Simple 3x3 box blur with offset
        for (var i = -1.0; i <= 1.0; i += 1.0) {
            for (var j = -1.0; j <= 1.0; j += 1.0) {
                let jitter = vec2<f32>(i, j);
                let sampleUV = uv + offset + jitter * blurSize;

                // Chromatic Aberration: R and B are offset
                let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(aberration * focusMask, 0.0), 0.0).r;
                let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
                let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(aberration * focusMask, 0.0), 0.0).b;

                r_acc += r;
                g_acc += g;
                b_acc += b;
                weight_acc += 1.0;
            }
        }

        finalColor = vec4<f32>(r_acc / weight_acc, g_acc / weight_acc, b_acc / weight_acc, 1.0);

        // Blend based on mask (soft edge for the focus area)
        let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        finalColor = mix(original, finalColor, focusMask);
    }

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
