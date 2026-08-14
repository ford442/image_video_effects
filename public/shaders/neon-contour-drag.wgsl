// ═══════════════════════════════════════════════════════════════
//  Neon Contour Drag - Warped Edge Detection with Alpha Emission
//  Category: lighting-effects
//  Physics: Emissive edges with UV warp and alpha occlusion
//  Alpha: Core edge = 0.3, Glow = 0.0 (additive)
// ═══════════════════════════════════════════════════════════════

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
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn sobel(uv: vec2<f32>, step: vec2<f32>) -> f32 {
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -step.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, step.y), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, 0.0), 0.0).rgb;
    let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, -step.y), 0.0).rgb;
    let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, -step.y), 0.0).rgb;
    let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-step.x, step.y), 0.0).rgb;
    let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(step.x, step.y), 0.0).rgb;
    let gx = -tl + tr - 2.0 * l + 2.0 * r - bl + br;
    let gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
    return length(gx) + length(gy);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    var p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    return mix(0.0, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / dims;
    let aspect = dims.x / dims.y;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held = step(0.5, u.zoom_config.w);

    let edgeStrength = u.zoom_params.x * 5.0 * (1.0 + bass * 0.5);
    let dragRadius = u.zoom_params.y;
    let glowIntensity = u.zoom_params.z * 2.0 * (1.0 + mids * 0.6) * mix(1.0, 1.35, held);
    let colorShift = u.zoom_params.w + treble * 0.2;
    let occlusionBalance = 0.5;

    let mousePos = u.zoom_config.yz;
    let uv_c = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_c = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = distance(uv_c, mouse_c);

    let warpAmount = smoothstep(dragRadius, 0.0, dist) * mix(0.2, 0.38, held);
    var dir = normalize(uv_c - mouse_c);
    let safeDir = select(vec2<f32>(0.0), dir, dist > 0.001);
    let warpUV = uv - safeDir * warpAmount;

    let stepFine = 1.0 / dims;
    let stepCoarse = stepFine * 3.0;
    let edgeFine = sobel(warpUV, stepFine);
    let edgeCoarse = sobel(warpUV, stepCoarse);
    let edgeBlend = mix(edgeCoarse, edgeFine, u.zoom_params.x);
    let edge = edgeBlend * (1.0 + edgeStrength * 0.15);

    let contourRunner = pow(max(0.0, sin(edge * 28.0 - time * (14.0 + bass * 6.0))), 12.0);
    let hueConveyor = pow(max(0.0, sin(dot(warpUV, vec2<f32>(1.2, 0.7)) * 40.0 - time * (18.0 + treble * 8.0))), 14.0);

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            clickFront += smoothstep(0.02, 0.0, abs(length(delta) - age * 0.35)) * exp(-age * 1.5);
        }
    }

    let hue = fract(time * 0.2 + dist * 2.0 + colorShift + hueConveyor * 0.12);
    let neonColor = hsv2rgb(vec3<f32>(hue, 0.8, 1.0));

    let glow = edge * edgeStrength * glowIntensity * smoothstep(1.0, 0.0, dist * 0.5);
    var emission = neonColor * glow * (1.0 + contourRunner * 0.35 + clickFront * 0.4);

    let hotCore = smoothstep(0.05, 0.0, dist);
    emission = mix(emission, vec3<f32>(1.0) - emission, hotCore * 0.5);

    let glowStrength = length(emission);
    let finalAlpha = calculateEmissiveAlpha(glowStrength, occlusionBalance);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
