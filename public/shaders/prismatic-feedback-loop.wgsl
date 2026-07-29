// ═══════════════════════════════════════════════════════════════════
//  Prismatic Feedback Loop
//  Category: interactive-mouse
//  Features: advanced-alpha, prismatic, feedback, chromatic, multi-pass,
//            mouse-driven, audio-reactive, depth-aware
//  Complexity: High
//  Upgraded: 2026-07-30 (Batch 18 - Algorithmist: honest slider rewiring,
//            click prism bursts, glow term, feedback blowout guard)
//  upgraded-rgba
//
//  Slider contract (ids/defaults are the saved-preset contract - the WGSL
//  now honors the LABELS, not the legacy mislabeled roles):
//    x = "Feedback"         -> temporal feedback mix amount
//    y = "Blur Radius"      -> prism tap spread magnitude (soften/blur)
//    z = "Glow Intensity"   -> glow lift on the accumulated trails
//    w = "Chromatic Spread" -> r/b separation angle fan-out
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Feedback, y=BlurRadius, z=GlowIntensity, w=ChromaticSpread
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// Ripple burst lifetime (seconds) - clicks shatter the prism locally.
const RIPPLE_LIFE: f32 = 1.5;

// Fixed trail accumulation rate for accumulativeAlpha() (the x slider
// now honestly drives the feedback mix, per its "Feedback" label).
const ACCUM_RATE: f32 = 0.5;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.1) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

// Rotate a 2D vector by `angle` radians.
fn rot2(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Honest slider wiring (labels now match behavior) ─────────────
    // x "Feedback": temporal mix toward the previous frame. Guarded to
    // [0,1] so the feedback loop can never blow out.
    let feedbackMix = clamp(u.zoom_params.x, 0.0, 1.0);
    // y "Blur Radius": prism tap spread magnitude. Default 1 reproduces
    // the legacy ~0.1 offset scale; reads as a chromatic soften/blur.
    let prismSpread = u.zoom_params.y * 0.1 * (1.0 + bass * 0.4 + treble * 0.3);
    // z "Glow Intensity": brightness lift applied to the accumulated
    // trails on output. Exactly 0 when the slider is 0.
    let glowIntensity = max(u.zoom_params.z, 0.0) * (1.0 + mids * 0.3);
    // w "Chromatic Spread": angular fan-out between the r and b taps.
    // Tiny default (0.02) = subtle fringe, matching its default.
    let chromaFan = clamp(u.zoom_params.w, 0.0, 0.2) * PI;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ── Prismatic chromatic separation ───────────────────────────────
    // The legacy z-slider rotation is now a slow constant drift so the
    // prism keeps breathing without stealing a slider.
    let centered = uv - 0.5;
    let drift = rot2(centered, time * 0.1);

    // Chromatic fan-out: r and b taps rotate apart by ±chromaFan.
    let rDir = rot2(drift, chromaFan);
    let bDir = rot2(drift, -chromaFan);

    // Depth-aware attenuation: distant pixels smear less.
    let depthScale = mix(1.0, 0.35, clamp(depth, 0.0, 1.0));

    var rOffset = rDir * prismSpread * depthScale;
    var bOffset = bDir * prismSpread * depthScale;

    // ── Click prism bursts ───────────────────────────────────────────
    // Each live ripple adds a decaying radial chromatic kick centered on
    // its click point, fading over ~RIPPLE_LIFE seconds.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < RIPPLE_LIFE) {
            let toPixel = uv - ripple.xy;
            let dist = length(toPixel);
            // Radial falloff around the click, exponential time decay.
            let falloff = exp(-dist * 9.0) * exp(-age * (3.0 / RIPPLE_LIFE));
            // Kick direction points radially outward from the click.
            let kickDir = toPixel / max(dist, 1e-4);
            let kick = kickDir * falloff * 0.06;
            rOffset = rOffset + kick;
            bOffset = bOffset - kick;
        }
    }

    let rUV = clamp(uv + rOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - bOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    let prismColor = vec3<f32>(r, g, b);

    // ── Guarded temporal feedback ────────────────────────────────────
    // x slider mixes toward the previous frame; result clamped to [0,1]
    // so runaway feedback blowout is impossible.
    let blended = clamp(
        mix(prev.rgb, prismColor, feedbackMix),
        vec3<f32>(0.0), vec3<f32>(1.0)
    );

    let brightness = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
    let newAlpha = clamp(mix(baseColor.a, brightness, feedbackMix), 0.0, 1.0);

    // dataTextureA is accumulation state: store the raw accumulated
    // value (capped only by accumulativeAlpha itself) - no tonemap, no
    // glow baked in - so the A-write / C-read loop stays symmetric and
    // stable across frames.
    let accumulated = accumulativeAlpha(blended, newAlpha, prev.rgb, prev.a, ACCUM_RATE);
    textureStore(dataTextureA, coord, accumulated);

    // ── Glow term (output only) ──────────────────────────────────────
    // Brightness lift of the accumulated trails: soft-knee luminance of
    // the trail feeds back as an additive halo. Exactly 0 at glow 0.
    let trailLum = max(dot(accumulated.rgb, vec3<f32>(0.299, 0.587, 0.114)) - 0.25, 0.0);
    let glow = trailLum * trailLum * glowIntensity * 0.6;
    let outColor = clamp(accumulated.rgb + accumulated.rgb * glow, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, global_id.xy, vec4<f32>(outColor, accumulated.a));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
