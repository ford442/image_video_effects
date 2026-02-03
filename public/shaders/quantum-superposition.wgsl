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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=ChaosSpeed, y=ChaosAmount, z=StabilityRadius, w=RGBSplit
  ripples: array<vec4<f32>, 50>,
};

fn hash13(p: vec3<f32>) -> f32 {
    var p3  = fract(p * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn random2(p: vec2<f32>) -> vec2<f32> {
    return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let chaosSpeed = u.zoom_params.x * 20.0;
    let chaosAmount = u.zoom_params.y; // 0.0 to 1.0
    let stabilityRadius = u.zoom_params.z; // 0.0 to 1.0
    let rgbSplitStr = u.zoom_params.w * 0.05;

    // Calculate stability field (mouse influence)
    let aspect = resolution.x / resolution.y;
    let mouseVec = (uv - mousePos);
    let dist = length(vec2<f32>(mouseVec.x * aspect, mouseVec.y));

    // Smoothstep creates a soft boundary for stability
    // Closer to mouse = 0.0 (stable), Further = 1.0 (unstable)
    let stability = smoothstep(stabilityRadius, stabilityRadius + 0.2, dist);

    // If mouse is offscreen (-1.0), everything is unstable
    let effectiveStability = select(stability, 1.0, mousePos.x < 0.0);

    // Chaos time modulation
    let chaosTime = floor(time * chaosSpeed);

    // Random offset for glitch
    // We use floor(uv * blocks) to create blocky artifacts
    let blockSize = 20.0 + (1.0 - effectiveStability) * 50.0;
    let blockUV = floor(uv * blockSize) / blockSize;

    // Random value per block per time step
    let rnd = hash13(vec3<f32>(blockUV, chaosTime));

    // Determine if this pixel is glitching
    // It glitches if the random value is less than the chaos amount masked by stability
    let isGlitch = select(0.0, 1.0, rnd < (chaosAmount * effectiveStability));

    var finalColor = vec4<f32>(0.0);

    if (isGlitch > 0.5) {
        // Glitch Mode:
        // 1. Color Inversion or Shift
        // 2. Spatial Displacement
        // 3. RGB Split

        let shift = (random2(blockUV + vec2<f32>(chaosTime)) - vec2<f32>(0.5)) * 0.1 * effectiveStability;

        let rUV = clamp(uv + shift + vec2<f32>(rgbSplitStr, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
        let gUV = clamp(uv + shift, vec2<f32>(0.0), vec2<f32>(1.0));
        let bUV = clamp(uv + shift - vec2<f32>(rgbSplitStr, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

        let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

        // Occasional color inversion
        if (rnd < 0.2) {
            finalColor = vec4<f32>(1.0 - r, 1.0 - g, 1.0 - b, 1.0);
        } else {
            finalColor = vec4<f32>(r, g, b, 1.0);
        }

        // Add some noise overlay
        finalColor = finalColor + vec4<f32>((rnd - 0.5) * 0.2);

    } else {
        // Stable Mode (Clean Image)
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    }

    // Pass-through depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    textureStore(writeTexture, global_id.xy, finalColor);
}
