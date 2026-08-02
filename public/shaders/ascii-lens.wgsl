// ═══════════════════════════════════════════════════════════════════
//  ascii-lens
//  Category: interactive-mouse
//  Features: upgraded-rgba, depth-aware, spring-lens, audio-reactive
//  Upgraded: 2026-03-22
//  Swarm upgrade: 2026-08-02 — frame contract (dataTextureA), spring lens,
//  click glyph scrambles, per-cell FFT flicker, bass radius breath.
// ═══════════════════════════════════════════════════════════════════

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

// ASCII Lens
// Param 1: Lens Radius (0.0 to 1.0)
// Param 2: Grid Density (High values = smaller chars)
// Param 3: Glyph Line Width
// Param 4: Brightness Threshold Bias
//
// extraBuffer layout (persistent shader state, [133..255] only):
//   [133..134] spring lens position   [135..136] spring lens velocity
//   [137]      initialized flag       [138]      last frame time

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // Critically-damped spring: the lens glides toward the raw cursor.
    // The raw mouse (with the negative-coord center fallback) stays the target.
    var rawMouse = u.zoom_config.yz;
    if (rawMouse.x < 0.0) { rawMouse = vec2<f32>(0.5, 0.5); }

    var mouse = vec2<f32>(extraBuffer[133u], extraBuffer[134u]);
    var mouseVel = vec2<f32>(extraBuffer[135u], extraBuffer[136u]);
    let springInit = extraBuffer[137u] >= 0.5;
    if (!springInit) {
        mouse = rawMouse;
        mouseVel = vec2<f32>(0.0, 0.0);
    }
    let springDt = select(0.0, clamp(time - extraBuffer[138u], 0.0005, 0.05), springInit);
    let springOmega = 8.0;
    let springAccel = springOmega * springOmega * (rawMouse - mouse)
        - 2.0 * springOmega * mouseVel;
    mouseVel += springAccel * springDt;
    mouse = clamp(mouse + mouseVel * springDt, vec2<f32>(-0.2), vec2<f32>(1.2));
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133u] = mouse.x;
        extraBuffer[134u] = mouse.y;
        extraBuffer[135u] = mouseVel.x;
        extraBuffer[136u] = mouseVel.y;
        extraBuffer[137u] = 1.0;
        extraBuffer[138u] = time;
    }

    // Bass breathes the lens radius.
    let bass = plasmaBuffer[1u].x;

    let lensRadius = u.zoom_params.x * (1.0 + bass * 0.15); // Default 0.3
    let density = 50.0 + u.zoom_params.y * 150.0; // 50 to 200 grid cells vertical

    // Calculate distance to mouse for lens effect
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

    // Sample depth for alpha calculation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Click scrambles: each live ripple jitters glyphs near its click point.
    // Aspect-corrected ~0.2 radius, decays as exp(-age * 2.5) over ~1s.
    var scramble = 0.0;
    var scrambleSeed = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.2) {
            let clickDist = distance(
                vec2<f32>(uv.x * aspect, uv.y),
                vec2<f32>(ripple.x * aspect, ripple.y)
            );
            let falloff = 1.0 - smoothstep(0.0, 0.2, clickDist);
            let weight = falloff * exp(-age * 2.5);
            if (weight > scramble) {
                scramble = weight;
                scrambleSeed = f32(ri) * 17.13 + ripple.z;
            }
        }
    }

    var finalColor: vec3<f32>;
    var finalAlpha: f32;

    if (dist < lensRadius) {
        // Inside Lens: ASCII Effect

        // Define grid
        let grid = vec2<f32>(density * aspect, density); // Adjust X for aspect to make square cells
        let cellUV = floor(uv * grid) / grid;
        let localUV = fract(uv * grid);

        // Sample color at cell center (pixelated look)
        // Add half pixel offset to sample center of block
        let sampleUV = cellUV + (vec2<f32>(0.5) / grid);
        var col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

        // Per-cell audio flicker: each glyph cell shimmers by its own FFT bin.
        let cellHash = hash21(cellUV * 251.0);
        let flicker = plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x * 0.4;

        // Click scramble: decaying hash jitter added to the luma tier selection.
        let jitter = (hash21(cellUV * 97.0 + vec2<f32>(scrambleSeed)) - 0.5) * scramble;

        var luma = dot(col, vec3<f32>(0.299, 0.587, 0.114)) + (u.zoom_params.w - 0.5) * 0.4;
        luma = clamp(luma + jitter + (flicker - 0.2) * 0.25, 0.0, 1.0);

        var charVal = 0.0;
        var center = vec2<f32>(0.5, 0.5);
        let distCenter = length(localUV - center);

        // Line width proportional to density? Constant is better for pixel crispness.
        // In UV space (0-1), 1 pixel width is roughly 1.0 / (res.y / density * 8.0).
        // Let's use a fixed relative width.
        let width = mix(0.02, 0.25, u.zoom_params.z);

        // Procedural Glyphs
        // Sorted by brightness
        if (luma > 0.8) {
            // # Block / Full
            charVal = 1.0;
        } else if (luma > 0.6) {
            // @ Square Frame + Dot
            if (abs(localUV.x - 0.5) > 0.2 || abs(localUV.y - 0.5) > 0.2) { charVal = 1.0; }
            if (distCenter < 0.1) { charVal = 1.0; }
        } else if (luma > 0.4) {
            // + Plus
            if (abs(localUV.x - 0.5) < width || abs(localUV.y - 0.5) < width) { charVal = 1.0; }
        } else if (luma > 0.25) {
            // - Minus
             if (abs(localUV.y - 0.5) < width) { charVal = 1.0; }
        } else if (luma > 0.1) {
            // . Dot
            if (distCenter < 0.15) { charVal = 1.0; }
        }

        // Audio shimmer: charVal dances with the cell's own FFT bin.
        charVal = charVal * (0.8 + flicker);

        finalColor = col * charVal;

        // Calculate luminance-based alpha
        let lumaFinal = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
        let alpha = mix(0.7, 1.0, lumaFinal);
        finalAlpha = mix(alpha * 0.8, alpha, depth);

    } else {
        // Outside Lens: Normal
        var col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        finalColor = col.rgb;
        finalAlpha = col.a;

        // Brief RGB split flicker marks the click outside the lens.
        if (scramble > 0.01) {
            let splitDir = vec2<f32>(hash21(vec2<f32>(scrambleSeed, 1.7)) - 0.5, 0.5) * 0.02 * scramble;
            let rUv = clamp(uv + splitDir, vec2<f32>(0.0), vec2<f32>(1.0));
            let bUv = clamp(uv - splitDir, vec2<f32>(0.0), vec2<f32>(1.0));
            let rCol = textureSampleLevel(readTexture, u_sampler, rUv, 0.0).r;
            let bCol = textureSampleLevel(readTexture, u_sampler, bUv, 0.0).b;
            finalColor = vec3<f32>(rCol, finalColor.g, bCol);
        }
    }

    let displayColor = vec4<f32>(finalColor, finalAlpha);
    textureStore(writeTexture, vec2<i32>(global_id.xy), displayColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), displayColor);

    // Pass depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
