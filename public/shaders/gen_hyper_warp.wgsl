// ═══════════════════════════════════════════════════════════════════
//  Hyper Warp
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, depth-aware,
//            upgraded-rgba, aces-tone-map, chromatic-aberration
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
//  Optimized: 2026-07-22 — feedback stabilization + real slider wiring
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic Hyper-Warp
// Advanced WGSL shader with domain warping, fractal noise, and reaction-diffusion feedback.

// 2D random function for noise generation
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// 2D noise function
fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let a = rand(i);
    let b = rand(i + vec2<f32>(1.0, 0.0));
    let c = rand(i + vec2<f32>(0.0, 1.0));
    let d = rand(i + vec2<f32>(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion (fBm) for detailed patterns
fn fbm(p: vec2<f32>, octaves: i32, persistence: f32) -> f32 {
    var total = 0.0;
    var frequency = 1.0;
    var amplitude = 1.0;
    var maxValue = 0.0;
    for (var i = 0; i < octaves; i++) {
        total += noise(p * frequency) * amplitude;
        maxValue += amplitude;
        amplitude *= persistence;
        frequency *= 2.0;
    }
    return total / maxValue;
}

// Function to create a vibrant color palette
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// Rec.601 luma — used by the feedback stabilizer's soft-knee
fn lumaOf(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Stabilize the sharpened feedback history before it is re-injected:
//   1. hard pre-tint ceiling at 1.2 (luma-echo-warp lesson) so the
//      sharpen stage (history * 1.1 - 0.05) can never run away,
//   2. luma soft-knee above 0.9 that desaturates overshooting highlights
//      toward grey instead of clipping them into flat color,
//   3. tiny 0.995 decay so the closed loop is strictly dissipative.
fn stabilizeHistory(h: vec3<f32>) -> vec3<f32> {
    let preTinted = clamp(h, vec3<f32>(0.0), vec3<f32>(1.2));
    let luma = lumaOf(preTinted);
    let knee = smoothstep(0.9, 1.2, luma);
    return mix(preTinted, vec3<f32>(luma), knee * 0.5) * 0.995;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let px = vec2<i32>(global_id.xy);
    if (px.x >= i32(resolution.x) || px.y >= i32(resolution.y)) { return; }
    var uv = (vec2<f32>(px) + vec2<f32>(0.5)) / resolution;

    // --- Audio Reactivity ---
    // bass drives the radial-burst pulse and chromatic aberration,
    // mid adds a slow hue drift, treble adds a faint sparkle to the warp.
    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ═══ SLIDER WIRING (saved-preset contract: zoom_params.x/y/z/w) ═══
    // Intensity -> warp amplitude (q weight driving the r warp layer)
    // Speed     -> global time multiplier (replaces the old fixed 0.2)
    // Scale     -> palette frequency + hue offset
    // Detail    -> reaction-diffusion feedback mix (0.85 - 0.98)
    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speedCtl = clamp(u.zoom_params.y, 0.0, 1.0);
    let scaleCtl = clamp(u.zoom_params.z, 0.0, 1.0);
    let detailCtl = clamp(u.zoom_params.w, 0.0, 1.0);

    let warpAmp = mix(1.0, 3.2, intensity);
    let time = u.config.x * mix(0.05, 0.45, speedCtl);
    let palFreq = mix(0.6, 1.6, scaleCtl);
    let hueShift = mix(0.0, 0.33, scaleCtl);
    let feedbackMix = mix(0.85, 0.98, detailCtl);

    let aspect = resolution.x / resolution.y;
    var p = uv - 0.5;
    p.x *= aspect;

    // --- Mouse Interaction ---
    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) - 0.5;
    mouse.x *= aspect;
    let mouse_dist = length(p - mouse);
    let mouse_warp = pow(1.0 - smoothstep(0.0, 0.32, mouse_dist), 2.0) * clamp(u.zoom_config.w, 0.0, 1.0);

    // --- Domain Warping ---
    // Warp the coordinate space using multiple layers of fBm for a liquid-like distortion
    var q = vec2<f32>(
        fbm(p + vec2<f32>(0.0, time * 0.4), 3, 0.5),
        fbm(p + vec2<f32>(5.2, time * 0.3), 3, 0.5)
    );
    // Add mouse influence to the domain warp
    let mouseDelta = p - mouse;
    if (length(mouseDelta) > 0.001) {
         q += mouse_warp * normalize(mouseDelta) * 0.5;
    }

    // Intensity slider scales the q weight that feeds the r warp layer.
    // Treble nudges the second warp layer for a subtle audio shimmer.
    var r = vec2<f32>(
        fbm(p + q * warpAmp + vec2<f32>(1.7, 9.2) + 0.1 * time, 4, 0.6),
        fbm(p + q * warpAmp + vec2<f32>(8.3, 2.8) + 0.1 * time + treble * 0.05, 4, 0.6)
    );

    // --- Flow-Advected History (feedback) ---
    // Offset the dataTextureC sample by the r warp vector so the feedback
    // smears along the liquid flow instead of sharpening a static frame.
    let flowVec = (r - vec2<f32>(0.5)) * (2.0 + 6.0 * intensity);
    let maxPx = vec2<i32>(resolution) - vec2<i32>(1, 1);
    let histPx = clamp(px + vec2<i32>(flowVec), vec2<i32>(0, 0), maxPx);
    let history = textureLoad(dataTextureC, histPx, 0).rgb;

    // --- Final Pattern Generation ---
    // The final value is a mix of warped coordinates and a radial component
    let val = fbm((p + r) * 2.0, 5, 0.5);
    // Bass gives the centered burst a gentle pulse.
    let radial_burst = pow(1.0 - smoothstep(0.0, 0.5, length(p)), 2.0);
    let final_val = val + radial_burst * (0.2 + 0.1 * bass);

    // --- Advanced Color Mapping ---
    // Blend between two psychedelic palettes based on the pattern value.
    // Scale slider drives palette frequency and a hue offset between the two.
    let palT = final_val * palFreq + time + mid * 0.08;
    let color1 = palette(palT, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.0, 0.1, 0.2));
    let color2 = palette(palT + hueShift, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 1.0, 0.5), vec3<f32>(0.8, 0.9, 0.3));
    var color = mix(color1, color2, smoothstep(0.4, 0.6, final_val));

    // Boost brightness and contrast for intensity
    color = pow(color, vec3<f32>(0.8)) * 1.5;

    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Opacity control
    let opacity = 0.85;

    // --- Stabilized Feedback and Output ---
    // Reaction-diffusion style feedback: sharpen, then clamp hard.
    // STABILIZATION (priority 1): the sharpened history can exceed 1.0, so it
    // gets an explicit 1.2 pre-tint ceiling (luma-echo-warp lesson), a luma
    // soft-knee that pulls overshooting highlights back toward grey, and a
    // tiny decay so the loop can never amplify itself to blowout.
    let sharpened = history * 1.1 - 0.05;
    let safeHistory = stabilizeHistory(sharpened);
    // Cold-start guard: while history is still black (first frames), fall
    // back toward the freshly generated color so the loop seeds itself
    // instead of damping the pattern to black.
    let histEnergy = smoothstep(0.0, 0.05, lumaOf(history));
    let seededHistory = mix(color, safeHistory, histEnergy);
    let generatedColor = clamp(mix(color, seededHistory, feedbackMix), vec3<f32>(0.0), vec3<f32>(1.0));

    // ═══ BLEND WITH INPUT ═══
    let finalColor = mix(inputColor.rgb, generatedColor, opacity);
    let effectCoverage = clamp(0.12 + lumaOf(generatedColor) * 0.82 + mouse_warp * 0.2, 0.08, 0.97);
    let finalAlpha = max(inputColor.a, effectCoverage);

    let caStr = 0.003 * (1.0 + bass) + inputDepth * 0.001;
    let chromaticColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);

    // Gentle vignette keeps the radial burst composition focused on center
    let vignette = 1.0 - 0.25 * smoothstep(0.45, 0.95, length(p));
    let acesColor = acesToneMap(chromaticColor * 1.1 * vignette);

    let rawHistory = clamp(chromaticColor * vignette, vec3<f32>(0.0), vec3<f32>(6.0));
    let generatedDepth = clamp(0.18 + length(flowVec) * 0.045 + radial_burst * 0.45 + mouse_warp * 0.25, 0.0, 1.0);
    textureStore(writeTexture, px, vec4<f32>(acesColor, finalAlpha));
    textureStore(dataTextureA, px, vec4<f32>(rawHistory, finalAlpha));
    textureStore(writeDepthTexture, px, vec4<f32>(max(inputDepth, generatedDepth), 0.0, 0.0, 0.0));
}
