// --- GAMMA RAY BURST ---
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

    // Mouse is the source
    let mouse = u.zoom_config.yz;

    // Params
    let intensity = u.zoom_params.x * 2.0 + 0.5;
    let decay = u.zoom_params.y * 0.1 + 0.9; // Blur decay
    let rayDensity = u.zoom_params.z * 50.0 + 10.0;
    let exposure = u.zoom_params.w * 2.0 + 1.0;

    let dir = (uv - mouse); // Direction from source to pixel
    let dist = length(dir * vec2<f32>(aspect, 1.0));

    // 1. Radial Blur
    // Sample N times along the vector to mouse
    let samples = 20;
    var acc = vec3<f32>(0.0);
    var weightSum = 0.0;

    // Dither step to break banding
    let dither = hash12(uv * u.config.x);

    for (var i = 0; i < samples; i++) {
        let t = (f32(i) + dither) / f32(samples);
        // Sample closer to mouse as i increases?
        // Or sample from UV towards Mouse.
        // We want to pull light FROM the source.
        // So we sample towards the mouse.
        // P = uv + (mouse - uv) * t * strength?
        // Actually zoom blur samples along the line.

        // P = mix(uv, mouse, t * intensity * 0.2);
        let sampleUV = mix(uv, mouse, t * 0.3 * intensity);

        let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

        // Weight falls off with distance from source sample?
        // Or exponential decay.
        let w = pow(decay, f32(i));

        // Boost bright parts (bloom)
        let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
        let boost = smoothstep(0.5, 1.0, luma) * 2.0;

        acc += col * w * (1.0 + boost);
        weightSum += w;
    }

    var finalColor = acc / weightSum;

    // 2. Rays
    // Angle from mouse
    let angle = atan2(dir.y, dir.x);
    // Noise based on angle
    let ray = sin(angle * rayDensity + u.config.x * 2.0)
            + 0.5 * sin(angle * rayDensity * 2.3 - u.config.x);

    let rayMask = smoothstep(0.0, 1.0, ray);

    // Add rays
    finalColor += vec3<f32>(0.5, 0.8, 1.0) * rayMask * 0.1 * intensity / (dist + 0.1);

    // 3. Central Overexposure / Glare
    let glare = 1.0 / (dist * 10.0 + 0.1);
    finalColor += vec3<f32>(1.0, 0.95, 0.8) * glare * exposure * 0.5;

    // Vignette
    finalColor *= smoothstep(1.5, 0.0, dist);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
