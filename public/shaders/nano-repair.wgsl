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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Hash function for noise
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
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
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Params
    let radius = u.zoom_params.x;     // Repair Radius
    let decay = u.zoom_params.y;      // Decay Speed
    let glitchStr = u.zoom_params.z;  // Glitch Strength
    let scanlines = u.zoom_params.w;  // Scanline Opacity

    // Feedback Logic for "Health"
    // Read previous frame's health from dataTextureC (alpha channel of previous output or separate channel)
    // Here we use dataTextureC.r to store health.

    let oldData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var health = oldData.r;

    // Mouse Interaction
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    if (dist < radius) {
        // Repair
        health += 0.1;
    } else {
        // Decay
        health -= decay * 0.01;
    }
    health = clamp(health, 0.0, 1.0);

    // Store health for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(health, 0.0, 0.0, 1.0));

    // Render Logic
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Glitch Effect
    if (health < 1.0) {
        // Quantize UVs for blocky glitch
        let blockSize = max(1.0, 20.0 * glitchStr);
        let blockUV = floor(uv * resolution / blockSize) * blockSize / resolution;
        let noiseVal = hash12(blockUV + time);

        var glitchColor = color;

        // Random offset
        if (noiseVal > 0.8) {
             let offset = (noiseVal - 0.9) * 0.5 * glitchStr;
             glitchColor = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset, 0.0), 0.0).rgb;
             // Color shift
             glitchColor.r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset + 0.01, 0.0), 0.0).r;
             glitchColor.b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset - 0.01, 0.0), 0.0).b;
        }

        // Noise overlay
        let grain = hash12(uv * resolution + time) * glitchStr;
        glitchColor += vec3<f32>(grain);

        // Mix based on health
        // Use smoothstep for a cleaner transition
        let mask = smoothstep(0.2, 0.8, health);
        color = mix(glitchColor, color, mask);

        // Scanlines
        let sl = sin(uv.y * resolution.y * 0.5) * 0.5 + 0.5;
        color = mix(color, color * sl, scanlines * (1.0 - mask));
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
