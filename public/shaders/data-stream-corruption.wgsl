// ═══════════════════════════════════════════════════════════════════
//  Data Stream Corruption
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-27
//  Ideas: rain head and tail; dwell pressure (§12.2C)
//  A packing: raw (corruption, 0, 0, alphaHistory); ACES on display only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // --- Persistence Logic (Corruption Map with Alpha History) ---
    // Read previous frame's state from dataTextureC
    let oldState = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    var corruption = oldState.r;
    var alphaHistory = oldState.a;

    // Mouse Interaction
    var mouse = u.zoom_config.yz;
    var dist = 10.0; // Default far away
    if (mouse.x >= 0.0) {
        var p = (uv - mouse);
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
        // ── Idea 2: dwell pressure (§12.2C) ─────────────────────────
        // A held pointer climbs the corruption field toward full. A passing
        // pointer keeps the add above and does not pool.
        let heldBrush = select(0.0, 1.0, u.zoom_config.w > 0.5);
        corruption = mix(corruption, 1.0, heldBrush * strength * 0.4);
        // Corruption also affects alpha - creates ghosting
        alphaHistory = min(alphaHistory + strength * 0.3, 1.0);
    }

    // Decay
    corruption = clamp(corruption * persistence, 0.0, 1.0);
    alphaHistory = alphaHistory * persistence;

    // Store updated corruption state for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(corruption, 0.0, 0.0, alphaHistory));

    // --- Render Logic ---

    // Matrix Rain Columns
    let numColumns = 80.0;
    let colIndex = floor(uv.x * numColumns + 0.5);
    let colRandom = hash12(vec2<f32>(colIndex, 42.0));
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    let rainSpeed = streamSpeed * (0.5 + 0.5 * colRandom) * (1.0 + bass * 0.3);
    let rainY = uv.y + time * rainSpeed * 0.1;

    // Generate characters/blocks
    let numRows = 40.0 * (resolution.y / resolution.x); // Maintain aspect roughly
    let rowIndex = floor(rainY * numRows + 0.5);
    let charRandom = hash12(vec2<f32>(colIndex, rowIndex));
    let isChar = step(0.4 - treble * 0.06, charRandom); // 60% density, treble fills gaps

    // Glitch Displacement based on corruption
    let effectiveCorruption = corruption * maxCorruption;

    var sampleUV = uv;
    let inputSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    var finalColor = inputSample;

    if (effectiveCorruption > 0.01) {
        // Blocky displacement
        let blockSize = 0.05;
        let blockX = floor(uv.x / blockSize) * blockSize;
        let blockRandom = hash12(vec2<f32>(blockX, floor(time * 10.0)));

        let displaceY = (blockRandom - 0.5) * 0.1 * effectiveCorruption;
        sampleUV.y += displaceY;

        // Re-sample after displacement
        let displacedSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
        
        // Channel Split
        let rgbSplit = 0.02 * effectiveCorruption;
        let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(rgbSplit, 0.0), 0.0).r;
        let g = displacedSample.g;
        let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(rgbSplit, 0.0), 0.0).b;
        // Alpha corruption: displaced alpha is blended with ghost alpha
        let corruptedAlpha = mix(displacedSample.a, alphaHistory, effectiveCorruption * 0.5);

        finalColor = vec4<f32>(r, g, b, corruptedAlpha);

        // Apply "Digital Stream" overlay with alpha-aware blending
        // ── Idea 1: rain head and tail ──────────────────────────────
        // The head of the column is bright. Characters fade down the tail.
        // Stream Speed still sets how fast the column falls.
        let headDist = fract(rainY);
        let headGlow = exp(-headDist * 7.0);
        let tailFade = exp(-headDist * 1.4);
        let streamColor = mix(vec3<f32>(0.2, 1.0, 0.4), vec3<f32>(0.75, 1.0, 0.88), headGlow);
        let streamIntensity = isChar * effectiveCorruption * colRandom * mix(0.2, 1.0, tailFade);

        // Brighten characters, darken background with alpha modulation
        let streamBlend = streamIntensity * 0.8;
        let newRGB = mix(finalColor.rgb, streamColor, streamBlend);
        // Stream effect increases alpha for digital look
        let newA = mix(finalColor.a, 0.9 + streamIntensity * 0.1, streamBlend);
        finalColor = vec4<f32>(newRGB, newA);

        // Darken non-character areas heavily if corrupted
        if (isChar < 0.5) {
             finalColor = mix(finalColor, vec4<f32>(0.0, 0.0, 0.0, finalColor.a * 0.5), effectiveCorruption * 0.5);
        }
    }
    
    // Ensure alpha is valid
    let displayRgb = acesToneMap(clamp(finalColor.rgb, vec3<f32>(0.0), vec3<f32>(4.0)));
    let displayA = clamp(finalColor.a, 0.0, 1.0);
    finalColor = vec4<f32>(displayRgb, displayA);

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
