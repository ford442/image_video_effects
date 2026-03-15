// ═══════════════════════════════════════════════════════════════
//  Neon Warp - Displacement Warp with Alpha Emission
//  Category: lighting-effects
//  Physics: Displacement field with emissive edge detection
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
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    var p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // Params
    // x: warpStrength, y: neonIntensity, z: colorSpeed, w: occlusionBalance
    let warpStrength = u.zoom_params.x * 2.0;
    let neonIntensity = u.zoom_params.y * 5.0;
    let colorSpeed = u.zoom_params.z;
    let decay = mix(0.9, 0.99, 0.5);
    let occlusionBalance = u.zoom_params.w;

    // Read previous displacement field
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).xy;

    // Mouse interaction
    var mousePos = u.zoom_config.yz;
    let dVec = uv - mousePos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    var displacement = prev * decay;

    // Create a repulsive field around mouse
    if (dist < 0.2) {
        let push = normalize(dVec) * (1.0 - dist / 0.2) * 0.01 * warpStrength;
        if (dist > 0.001) {
            displacement = displacement + push;
        }
    }

    // Write state
    textureStore(dataTextureA, global_id.xy, vec4<f32>(displacement, 0.0, 0.0));

    // Rendering
    let warpedUV = uv - displacement;
    let clampedUV = clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let centerColor = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0).rgb;

    // Edge detection (Sobel-ish) on warped coords
    let step = 1.0 / resolution;
    let c1 = textureSampleLevel(readTexture, u_sampler, clampedUV + vec2<f32>(step.x, 0.0), 0.0).rgb;
    let c2 = textureSampleLevel(readTexture, u_sampler, clampedUV + vec2<f32>(-step.x, 0.0), 0.0).rgb;
    let c3 = textureSampleLevel(readTexture, u_sampler, clampedUV + vec2<f32>(0.0, step.y), 0.0).rgb;
    let c4 = textureSampleLevel(readTexture, u_sampler, clampedUV + vec2<f32>(0.0, -step.y), 0.0).rgb;

    let edgeX = length(c1 - c2);
    let edgeY = length(c3 - c4);
    let edge = sqrt(edgeX*edgeX + edgeY*edgeY);

    // Neon color generation
    let hue = fract(time * colorSpeed + length(displacement) * 10.0);
    let neon = hsv2rgb(vec3<f32>(hue, 0.8, 1.0));

    // Emission calculation
    var emission = vec3<f32>(0.0);
    if (edge > 0.1) {
        emission = neon * edge * neonIntensity;
    }

    // Add some glow from displacement intensity
    emission += neon * length(displacement) * 5.0;

    // Calculate alpha based on emission intensity
    let glowStrength = length(emission);
    let finalAlpha = calculateEmissiveAlpha(glowStrength, occlusionBalance);

    // Output with emission alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));
}
