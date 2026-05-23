// ═══════════════════════════════════════════════════════════════════
//  Cymatic Sand — Phase A Upgrade
//  Category: simulation
//  Features: mouse-driven, audio-reactive, temporal
//  Complexity: Medium
//  Chunks From: original cymatic-sand.wgsl
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: frequency_mode    — primary harmonic mode index (1–20)
//  Param2: harmonic_mix      — blend of audio-driven secondary harmonics
//  Param3: grain_density     — sand accumulation density
//  Param4: audio_sensitivity — how strongly audio reshapes nodal pattern
//
//  Mouse XY: selects sub-mode within the harmonic space
//  State: dataTextureC.r = accumulated sand density (persists across frames)

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=FreqMode, y=HarmonicMix, z=GrainDensity, w=AudioSensitivity
  ripples: array<vec4<f32>, 50>,
};

// ─── Helpers ──────────────────────────────────────────────────────

fn hash2d(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// 2D value noise for grain texture
fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2d(i),                   hash2d(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash2d(i + vec2<f32>(0.0, 1.0)), hash2d(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Chladni wave function: cos(n*pi*x)*cos(m*pi*y) - cos(m*pi*x)*cos(n*pi*y)
fn chladni(p: vec2<f32>, n: f32, m: f32) -> f32 {
    let pi = 3.14159265;
    return cos(n * pi * p.x) * cos(m * pi * p.y)
         - cos(m * pi * p.x) * cos(n * pi * p.y);
}

// SDF circle for rounded grain rendering
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// ─── Main ─────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let aspect = resolution.x / resolution.y;
    let mouse  = u.zoom_config.yz;

    // Params
    let freqMode      = floor(u.zoom_params.x * 18.0) + 1.0;  // 1–19
    let harmonicMix   = u.zoom_params.y;
    let grainDensity  = u.zoom_params.z * 0.85 + 0.1;
    let audioSens     = u.zoom_params.w;

    // Audio bands
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass   = select(0.0, plasmaBuffer[0].x, hasAudio);
    let mids   = select(0.0, plasmaBuffer[0].y, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

    // UV in [-1, 1] space, corrected for aspect
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    // Primary mode: mouse selects within harmonic space
    let mxn = select(freqMode,     floor(mouse.x * 18.0) + 1.0, mouse.x >= 0.0);
    let mxm = select(freqMode + 2.0, floor(mouse.y * 18.0) + 1.0, mouse.y >= 0.0);

    // Secondary modes driven by audio
    let bassN   = freqMode + 1.0 + bass   * audioSens * 6.0;
    let midsN   = freqMode + 3.0 + mids   * audioSens * 4.0;
    let trebleN = freqMode + 5.0 + treble * audioSens * 8.0;

    // Slow temporal drift for ambient animation when no audio
    let driftN = freqMode + sin(time * 0.07) * 1.5;
    let driftM = mxm      + cos(time * 0.05) * 1.5;

    // Multi-harmonic superposition
    let w0 = chladni(p, mxn, mxm);                     // primary
    let w1 = chladni(p, bassN,   mxm + 1.0);            // bass harmonic
    let w2 = chladni(p, midsN,   midsN + 2.0);          // mids harmonic
    let w3 = chladni(p, trebleN, freqMode + 4.0);       // treble harmonic
    let w4 = chladni(p, driftN,  driftM);               // drift

    // Blend: primary always dominant, harmonics blend in via param + audio
    let audioBlend = clamp(harmonicMix + (bass + mids + treble) * audioSens * 0.2, 0.0, 1.0);
    let combined = w0 * (1.0 - audioBlend)
                 + (w1 * 0.5 + w2 * 0.3 + w3 * 0.15 + w4 * 0.05) * audioBlend;

    // Nodal lines: sand accumulates where |wave| ≈ 0
    let vibration = abs(combined);
    let lineWidth = 0.06 + harmonicMix * 0.04 + bass * audioSens * 0.03;
    let targetDensity = 1.0 - smoothstep(0.0, lineWidth, vibration);

    // Sand persistence — smooth temporal accumulation
    let prevDensity = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Check for ripple reset (mouse click clears the canvas locally)
    var resetStrength = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let r = u.ripples[ri];
        let elapsed = time - r.z;
        if (elapsed >= 0.0 && elapsed < 0.3) {
            let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
            resetStrength = max(resetStrength, exp(-rDist * 8.0) * (1.0 - elapsed / 0.3));
        }
    }

    // Blend speed: faster when audio is strong (pattern shifts quicker)
    let blendSpeed = 0.04 + bass * audioSens * 0.08;
    var newDensity = mix(prevDensity, targetDensity, blendSpeed);
    newDensity = mix(newDensity, 0.0, resetStrength);  // ripple clears

    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newDensity, 0.0, 0.0, 1.0));

    // ── Render ───────────────────────────────────────────────────
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let baseAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

    // Rounded grain texture via fine noise SDF
    let grainScale = 300.0 + treble * audioSens * 200.0;
    let grainCell  = floor(uv * grainScale);
    let grainFrac  = fract(uv * grainScale) - 0.5;
    let grainRng   = hash2d(grainCell);
    let grainJitter = (vec2<f32>(hash2d(grainCell + 0.1), hash2d(grainCell + 0.2)) - 0.5) * 0.3;
    let grainSDF   = sdCircle(grainFrac - grainJitter, 0.25 + grainRng * 0.15);
    let grainMask  = 1.0 - smoothstep(-0.05, 0.05, grainSDF);

    // Threshold: draw grain where accumulated density is high enough
    let sandVisible = step(1.0 - newDensity * grainDensity, grainRng) * grainMask;

    // Sand colour: warm beige with subtle hue shift from audio
    let sandHue    = vec3<f32>(0.9 + bass * 0.1, 0.82 + mids * 0.1, 0.62 - treble * 0.15);
    let bgDarken   = mix(baseColor * 0.45, baseColor * 0.6, newDensity);
    let finalColor = mix(bgDarken, sandHue, sandVisible);

    // RGBA alpha: sand pixels opaque, gaps semi-transparent
    let alpha = mix(baseAlpha * 0.5, 1.0, sandVisible * grainDensity);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

    // Depth: sand grains are slightly raised
    let heightDepth = newDensity * 0.7 + 0.1;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy),
                 vec4<f32>(heightDepth, 0.0, 0.0, 1.0));
}
