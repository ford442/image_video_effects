// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
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
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // Params
    let rainIntensity = u.zoom_params.x;
    let blurStrength = u.zoom_params.y * 0.1; // Scale down for texture offset
    let bloomThreshold = u.zoom_params.z;
    let wiperSize = u.zoom_params.w * 0.5;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Wiper / Shield Effect
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let wiper = smoothstep(wiperSize, wiperSize * 0.8, dist); // 1.0 inside, 0.0 outside

    // 1. Vertical Blur (Wet Ground Reflection)
    // Sample a few points below the current pixel
    var blurredColor = vec4<f32>(0.0);
    let samples = 5;
    for (var i = 0; i < samples; i++) {
        let offset = f32(i) * blurStrength * (1.0 - wiper); // Wiper reduces blur
        // Mirror uv.y for reflection if we want ground reflection, but vertical blur is simpler "wet glass"
        // Let's do bidirectional vertical blur for "wet lens"
        let sampleUV = uv + vec2<f32>(0.0, offset - blurStrength * 2.0); // Center it? No, rain falls down
        let col = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

        // Bloom accumulation
        let brightness = max(col.r, max(col.g, col.b));
        let bloom = smoothstep(bloomThreshold, 1.0, brightness);
        blurredColor += col * (1.0 + bloom * 2.0); // Boost bright spots
    }
    blurredColor = blurredColor / f32(samples);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mix base and blur based on rain intensity (more rain = more wet/blur)
    var finalColor = mix(baseColor, blurredColor, rainIntensity * 0.8);

    // 2. Rain Drops
    // Skew UV for rain
    let rainUV = uv * vec2<f32>(20.0, 2.0) + vec2<f32>(0.0, time * 10.0 * rainIntensity);
    let rainNoise = hash12(floor(rainUV));
    let drop = smoothstep(0.9, 0.95, rainNoise) * rainIntensity;

    // Wiper clears rain
    let rainMask = 1.0 - wiper;

    // Add rain drops as blue/white overlay
    finalColor += vec4<f32>(0.5, 0.7, 1.0, 0.0) * drop * rainMask;

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
