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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
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

    // --- Persistence Logic (Corruption Map) ---
    // Read previous frame's state from dataTextureC
    let oldState = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    var corruption = oldState.r;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    var dist = 10.0; // Default far away
    if (mouse.x >= 0.0) {
        let p = (uv - mouse);
        dist = length(vec2<f32>(p.x * aspect, p.y));
    }

    // Parameters
    let streamSpeed = mix(2.0, 20.0, u.zoom_params.x);
    let brushRadius = mix(0.02, 0.4, u.zoom_params.y);
    let maxCorruption = mix(0.0, 1.0, u.zoom_params.z);
    let persistence = mix(0.8, 0.995, u.zoom_params.w);

    // Add corruption if mouse is close
    if (dist < brushRadius) {
        // Soft brush edge
        let strength = smoothstep(brushRadius, brushRadius * 0.5, dist);
        corruption += strength * 0.5;
    }

    // Decay
    corruption = clamp(corruption * persistence, 0.0, 1.0);

    // Store updated corruption state for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(corruption, 0.0, 0.0, 1.0));

    // --- Render Logic ---

    // Matrix Rain Columns
    let numColumns = 80.0;
    let colIndex = floor(uv.x * numColumns);
    let colRandom = hash12(vec2<f32>(colIndex, 42.0));
    let rainSpeed = streamSpeed * (0.5 + 0.5 * colRandom);
    let rainY = uv.y + time * rainSpeed * 0.1;

    // Generate characters/blocks
    let numRows = 40.0 * (resolution.y / resolution.x); // Maintain aspect roughly
    let rowIndex = floor(rainY * numRows);
    let charRandom = hash12(vec2<f32>(colIndex, rowIndex));
    let isChar = step(0.4, charRandom); // 60% density

    // Glitch Displacement based on corruption
    let effectiveCorruption = corruption * maxCorruption;

    var sampleUV = uv;
    var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    if (effectiveCorruption > 0.01) {
        // Blocky displacement
        let blockSize = 0.05;
        let blockX = floor(uv.x / blockSize) * blockSize;
        let blockRandom = hash12(vec2<f32>(blockX, floor(time * 10.0)));

        let displaceY = (blockRandom - 0.5) * 0.1 * effectiveCorruption;
        sampleUV.y += displaceY;

        // Channel Split
        let rgbSplit = 0.02 * effectiveCorruption;
        let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(rgbSplit, 0.0), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(rgbSplit, 0.0), 0.0).b;

        finalColor = vec4<f32>(r, g, b, 1.0);

        // Apply "Digital Stream" overlay
        let streamColor = vec3<f32>(0.2, 1.0, 0.4); // Matrix green
        let streamIntensity = isChar * effectiveCorruption * colRandom;

        // Brighten characters, darken background
        finalColor = mix(finalColor, vec4<f32>(streamColor, 1.0), streamIntensity * 0.8);

        // Darken non-character areas heavily if corrupted
        if (isChar < 0.5) {
             finalColor = mix(finalColor, vec4<f32>(0.0, 0.0, 0.0, 1.0), effectiveCorruption * 0.5);
        }
    }

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
