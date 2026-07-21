// ═══════════════════════════════════════════════════════════════════
//  Anaglyph 3D — Cinematic Post-Processing Edition
//  Category: visual-effects
//  Features: depth-aware, upgraded-rgba, red-cyan, stereoscopic, audio-reactive,
//            temporal-ghosting, chromatic-separation, mouse-focal-depth,
//            film-grain, chromatic-aberration, vignette, scanlines, crt-barrel,
//            color-grading, anamorphic-streaks, lens-dirt
//  Complexity: High
//  Upgraded: 2026-06-28
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

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn random(gid: vec2<f32>, time: f32) -> f32 {
    return hash21(gid + time * 0.01);
}

// Temporal grain: coherent over time, not static
fn temporalGrain(gid: vec2<f32>, time: f32, treble: f32) -> f32 {
    let t1 = hash21(gid + fract(time * 0.7) * 100.0);
    let t2 = hash21(gid + fract(time * 0.3) * 100.0 + 50.0);
    // Blend two time-offset samples for temporal coherence
    let grain = mix(t1, t2, 0.5) - 0.5;
    return grain * (1.0 + treble * 0.3);
}

// Radial chromatic aberration
fn radialChromatic(uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec2<f32> {
    let dir = uv - center;
    let r2 = dot(dir, dir);
    return dir * r2 * strength;
}

// Vignette: darkening at corners
fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let center = uv - vec2<f32>(0.5);
    let r = length(center) * 1.4142;
    return pow(1.0 - r * strength, 2.0);
}

// Scanlines: horizontal lines with varying intensity
fn scanlines(y: f32, time: f32, intensity: f32) -> f32 {
    let freq = 800.0;
    let scan = sin(y * freq) * 0.5 + 0.5;
    let fade = sin(y * freq * 0.5 + time * 2.0) * 0.3 + 0.7;
    return 1.0 - scan * intensity * fade;
}

// CRT barrel distortion
fn crtDistort(uv: vec2<f32>, k: f32) -> vec2<f32> {
    let center = uv - vec2<f32>(0.5);
    let r2 = dot(center, center);
    let distort = 1.0 + k * r2 + k * k * r2 * r2;
    return center * distort + vec2<f32>(0.5);
}

// Color grading: lift/gamma/gain
fn colorGrade(color: vec3<f32>, lift: vec3<f32>, gamma: vec3<f32>, gain: vec3<f32>) -> vec3<f32> {
    var c = color;
    // Lift (shadows)
    c = c + lift * (1.0 - c);
    // Gamma (midtones)
    c = pow(max(c, vec3<f32>(0.0)), gamma);
    // Gain (highlights)
    c = c * gain;
    return c;
}

// Anamorphic streaks: horizontal light streaks from bright points
fn anamorphicStreaks(uv: vec2<f32>, center: vec2<f32>, brightness: f32, strength: f32) -> vec3<f32> {
    let dx = abs(uv.x - center.x);
    let streak = exp(-dx * dx * 2000.0) * brightness * strength;
    return vec3<f32>(streak * 1.0, streak * 0.9, streak * 0.7);
}

// Lens dirt: subtle dust/grime overlay on bright areas
fn lensDirt(uv: vec2<f32>, time: f32, brightness: f32) -> f32 {
    let dirt1 = hash21(uv * 3.0 + time * 0.01);
    let dirt2 = hash21(uv * 7.0 - time * 0.015);
    let dirt = mix(dirt1, dirt2, 0.5);
    return smoothstep(0.6, 0.9, dirt) * brightness * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let separation = u.zoom_params.x * 0.04 * (1.0 + bass * 0.15);
    let depthCurve = u.zoom_params.y;
    let ghostAmount = u.zoom_params.z;
    let grainAmount = u.zoom_params.w;

    // ── Cinematic post-processing params (derived from controls) ──
    let caStrength = 0.02 + treble * 0.03;       // chromatic aberration
    let vignetteStrength = 0.6 + bass * 0.2;    // vignette
    let scanlineIntensity = 0.08 + mids * 0.05;  // scanlines
    let crtK = -0.08;                             // CRT barrel (negative = pincushion)
    let anamorphicStrength = 0.3 + bass * 0.3;   // anamorphic streaks
    let lensDirtAmount = 0.2 + treble * 0.15;    // lens dirt

    // Apply CRT barrel distortion to UV
    let distortedUV = crtDistort(uv, crtK);
    let validUV = clamp(distortedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, validUV, 0.0).r;
    let mouse = u.zoom_config.yz;
    let mouseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, mouse, 0.0).r;

    // Mouse focal depth curve refinement
    let focalDepth = mix(mouseDepth, 0.5, 0.3);
    let depthOffset = depthCurve * (depth - focalDepth) * 2.0;
    let shift = separation * depthOffset;

    // Radial chromatic aberration offset
    let caOffset = radialChromatic(validUV, vec2<f32>(0.5), caStrength * (1.0 + bass * 0.5));

    let rUV = clamp(validUV + vec2<f32>(shift, 0.0) + caOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let cUV = clamp(validUV - vec2<f32>(shift, 0.0) - caOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    var color = vec3<f32>(0.0);
    color.r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    color.g = textureSampleLevel(readTexture, u_sampler, cUV, 0.0).g;
    color.b = textureSampleLevel(readTexture, u_sampler, cUV, 0.0).b;

    // Ghost fringing: R/C offset residual trails
    let ghostShift = separation * depthOffset * 0.5;
    let ghostR = textureSampleLevel(readTexture, u_sampler, clamp(rUV + vec2<f32>(ghostShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r * 0.5;
    let ghostC = textureSampleLevel(readTexture, u_sampler, clamp(cUV - vec2<f32>(ghostShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g * 0.5;
    color.r = color.r + ghostR * ghostAmount;
    color.g = color.g + ghostC * ghostAmount;

    // Chromatic separation enhancement per depth
    let chromaBoost = smoothstep(0.0, 1.0, abs(depth - focalDepth)) * treble * 0.2;
    color.r = color.r * (1.0 + chromaBoost);
    color.g = color.g * (1.0 - chromaBoost * 0.3);
    color.b = color.b * (1.0 - chromaBoost * 0.1);

    // ── Temporal film grain ──
    let grain = temporalGrain(vec2<f32>(global_id.xy), time, treble);
    color = color + grain * grainAmount * 0.1;

    // ── Scanlines ──
    let scan = scanlines(uv.y, time, scanlineIntensity);
    color = color * scan;

    // ── Vignette ──
    let vig = vignette(validUV, vignetteStrength * 0.7);
    color = color * mix(0.4, 1.0, vig);

    // ── Color grading (lift/gamma/gain) ──
    let lift = vec3<f32>(0.02, 0.01, -0.01) * (1.0 + bass * 0.1);
    let gamma = vec3<f32>(0.95, 0.98, 1.05) - mids * 0.05;
    let gain = vec3<f32>(1.05, 1.0, 0.95) * (1.0 + treble * 0.05);
    color = colorGrade(color, lift, gamma, gain);

    // ── Anamorphic streaks from bright points ──
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let brightMask = smoothstep(0.6, 0.95, luma);
    let streaks = anamorphicStreaks(validUV, vec2<f32>(0.5), brightMask, anamorphicStrength);
    color = color + streaks;

    // ── Lens dirt on bright areas ──
    let dirt = lensDirt(validUV, time, brightMask * lensDirtAmount);
    let dirtColor = vec3<f32>(0.9, 0.85, 0.7) * dirt;
    color = color + dirtColor;

    // Temporal ghost persistence
    let prev = textureSampleLevel(dataTextureC, u_sampler, validUV, 0.0).rgb;
    color = mix(color, prev * 0.9, 0.04 + mids * 0.01);

    let baseAlpha = textureSampleLevel(readTexture, u_sampler, validUV, 0.0).a;
    let finalAlpha = mix(baseAlpha, 1.0, separation * 0.3 + brightMask * 0.2);

    // Clamp and premultiply alpha
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.5));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color * finalAlpha, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color * finalAlpha, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}