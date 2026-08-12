// ═══════════════════════════════════════════════════════════════════
//  Alpha Luminance History
//  Category: visual-effects
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: Medium
//  RGBA Channels:
//    R = Current frame red
//    G = Current frame green
//    B = Current frame blue
//    A = Rolling average luminance (memory of brightness)
//  Why f32: Rolling average requires accumulation of tiny increments
//  per frame; 8-bit would quantize to zero and never update.
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

fn historyAt(coord: vec2<i32>, res: vec2<f32>) -> vec4<f32> {
    let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxCoord), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;

    // Read current frame
    let currentColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let currentLuma = dot(currentColor, vec3<f32>(0.299, 0.587, 0.114));

    // Read a directionally advected history texel with exact clamped loads.
    let diffusion = clamp(u.zoom_params.w, 0.0, 1.0);
    let mouseVector = u.zoom_config.yz - uv;
    let mouseDirection = mouseVector / max(length(mouseVector), 0.0001);
    let flowDirection = normalize(mouseDirection * 0.65 + vec2<f32>(cos(time * 0.7), sin(time * 0.9)) * 0.35);
    let historyOffset = vec2<i32>(round(flowDirection * (1.0 + diffusion * 6.0)));
    let prevState = historyAt(coord - historyOffset, res);
    let prevAvgLuma = prevState.a;

    // === PARAMETERS ===
    // decay: 0.01 = long memory, 0.5 = short memory
    let decay = mix(0.005, 0.3, u.zoom_params.x);
    let glowIntensity = u.zoom_params.y * 3.0 * (1.0 + audio.y * 0.25);
    let colorShift = u.zoom_params.z; // Hue shift based on history

    // === UPDATE ROLLING AVERAGE ===
    let newAvgLuma = mix(prevAvgLuma, currentLuma, decay);

    // === GLOW COMPUTATION ===
    // Glow where it WAS bright (newAvg > current)
    let glowAmount = max(0.0, newAvgLuma - currentLuma);

    // Warm glow color
    let glowColor = vec3<f32>(1.0, 0.85, 0.6) * glowAmount * glowIntensity;

    // === COLOR SHIFT BASED ON HISTORY ===
    var displayColor = currentColor + glowColor;

    // If area has high historical brightness, shift hue
    let historyTint = vec3<f32>(
        1.0 + colorShift * 0.3,
        1.0 - colorShift * 0.1,
        1.0 - colorShift * 0.2
    );
    displayColor *= mix(vec3<f32>(1.0), historyTint, smoothstep(0.0, 0.5, newAvgLuma));

    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(2.0));

    // === MOUSE TRAIL ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.15, 0.0, mouseDist) * mouseDown;
    // Mouse leaves a bright trail in the history
    let boostedAvg = mix(newAvgLuma, 1.0, mouseInfluence * 0.5);

    // === RIPPLE FLASH ===
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleBoost = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.8) {
            let radius = age * (0.16 + audio.x * 0.08);
            let ringDist = abs(length(uv - ripple.xy) - radius);
            rippleBoost += (1.0 - smoothstep(0.0, 0.022, ringDist)) * (1.0 - age / 2.8);
        }
    }
    let finalAvgLuma = mix(boostedAvg, 1.0, rippleBoost * 0.3);

    // === SPATIAL DIFFUSION OF HISTORY ===
    // Let the history bleed slightly for light-painting effect
    let left = historyAt(coord + vec2<i32>(-1, 0), res);
    let right = historyAt(coord + vec2<i32>(1, 0), res);
    let down = historyAt(coord + vec2<i32>(0, -1), res);
    let up = historyAt(coord + vec2<i32>(0, 1), res);
    let neighborAvg = (left.a + right.a + down.a + up.a) * 0.25;
    let diffusedAvg = mix(finalAvgLuma, neighborAvg, mix(0.0, 0.48, diffusion));

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(currentColor, diffusedAvg));

    // === TONE MAP AND WRITE ===
    displayColor = displayColor / (1.0 + displayColor * 0.3);
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, diffusedAvg));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
