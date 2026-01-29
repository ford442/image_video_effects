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

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

fn noise1(p: f32) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(hash11(i), hash11(i + 1.0), u);
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
    let time = u.config.x;

    // Params
    let blurStrength = u.zoom_params.x * 0.1; // 0 to 0.1
    let lineDensity = u.zoom_params.y * 50.0 + 10.0;
    let lineSpeed = u.zoom_params.z * 10.0 + 2.0;
    let contrast = u.zoom_params.w + 0.5;

    // Center on mouse
    let uvCenter = uv - mouse;
    let uvCenterAspect = vec2<f32>(uvCenter.x * aspect, uvCenter.y);
    let dist = length(uvCenterAspect);
    let angle = atan2(uvCenterAspect.y, uvCenterAspect.x);

    // 1. Zoom Blur
    var blurColor = vec3<f32>(0.0);
    let samples = 16;
    for (var i = 0; i < samples; i++) {
        let t = f32(i) / f32(samples - 1);
        let scale = 1.0 - t * blurStrength * dist; // Blur increases with distance
        let sampleUV = mouse + uvCenter * scale;
        blurColor += textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    }
    blurColor = blurColor / f32(samples);

    // 2. Speed Lines
    // Noise based on angle and time
    // We want the lines to streak outwards

    // Animate lines moving outward? Or just flickering?
    // Usually speed lines are static radial streaks that jitter.

    let n = noise1(angle * lineDensity + time * lineSpeed);

    // Threshold to create sharp lines
    let lines = smoothstep(0.6, 0.8, n);

    // Mask: No lines in center
    let centerMask = smoothstep(0.2, 0.5, dist);

    let lineEffect = lines * centerMask * contrast;

    // Composite
    // Add white lines
    // Or invert color?
    // Let's do Multiply (Dark lines) and Add (Bright lines)
    // Classic is Black lines on white, or White on dark.

    // Let's add bright lines
    var finalColor = blurColor + vec3<f32>(lineEffect);

    // Optional: Darken edges (Vignette)
    finalColor *= (1.0 - dist * 0.5);

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
