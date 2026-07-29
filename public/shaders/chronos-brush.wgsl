// ═══════════════════════════════════════════════════════════════════
//  Chronos Brush
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-painting, depth-aware-opacity, chromatic-brush, upgraded-rgba
//  Complexity: High
//  Chunks From: chronos-brush, bass_env, temporal-feedback
//  Created: 2024-01-01
//  Upgraded: 2026-06-28
//  Rewired: 2026-07-30 (Batch 17 - honest slider semantics, click-stamp blooms, paint/erase mode)
// ═══════════════════════════════════════════════════════════════════
//  Slider contract (labels now tell the truth):
//    x = Brush Size         -> brush radius (audio-boosted via bass_env)
//    y = Freeze Decay       -> history persistence (default 0.9 == legacy fade)
//    z = Time Edge Distort  -> temporal sinusoid wobble of the history sample UV
//    w = Mode (Paint/Erase) -> <=0.5 paints tinted strokes, >0.5 erases to live
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BrushSize, y=FreezeDecay, z=TimeEdgeDistort, w=Mode
  ripples: array<vec4<f32>, 50>, // xy=click UV, z=click time, w=unused
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    // zoom_config.w = mouseDown (available, not needed by the legacy stroke).
    let clickCount = u.config.y;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOpacity = mix(0.7, 1.0, depth);

    // ── Honest slider wiring ────────────────────────────────────────
    // x: Brush Size (unchanged semantic, still audio-boosted).
    let brushSize = mix(0.0, 1.0, clamp(u.zoom_params.x, 0.0, 1.0)) * bass_env(bass, mids);
    // y: Freeze Decay -> history persistence. Default 0.9 maps to the legacy
    //    fade constant (decay = 0.975 at silence); y=1.0 freezes forever.
    let freezeDecay = clamp(u.zoom_params.y, 0.0, 1.0);
    // z: Time Edge Distort -> amplitude of the temporal UV wobble (0 = off).
    let timeDistort = clamp(u.zoom_params.z, 0.0, 1.0);
    // w: Mode -> 0..0.5 paint (Freeze), 0.5..1 erase (Unfreeze).
    let eraseMode = u.zoom_params.w > 0.5;

    let aspect = resolution.x / resolution.y;
    let aspectCorrection = vec2<f32>(aspect, 1.0);
    let diff = (uv - mousePos) * aspectCorrection;
    let dist = length(diff);

    let radius = 0.02 + brushSize * 0.15;
    let brush = 1.0 - smoothstep(radius * 0.8, radius, dist);

    // ── Temporal distortion: wobble the history fetch, not the live feed ──
    // Quadratic falloff keeps the low end (and the 0.5 default) gentle so the
    // painted look stays intact until the slider is pushed.
    let wobbleAmp = timeDistort * timeDistort * 0.012;
    let wobble = vec2<f32>(
        sin(uv.y * 23.0 + time * 1.7) + sin(uv.y * 7.0 - time * 0.9),
        cos(uv.x * 19.0 - time * 1.3) + cos(uv.x * 5.0 + time * 0.7)
    ) * wobbleAmp * 0.5;
    let historyUV = clamp(uv + wobble, vec2<f32>(0.0), vec2<f32>(1.0));

    let historyColor = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0);
    let liveColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Chromatic brush: cycle HSL hue per click via time (legacy 0.45 rate).
    let hue = fract(sin(clickCount * 0.5 + time * 0.45 + bass * 0.1) * 43758.5453);
    let sat = 0.8 + mids * 0.2;
    let val = 0.9 + treble * 0.1;

    // HSV to RGB inline
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
    let brushTint = clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let tintColor = vec3<f32>(sat * val) * mix(vec3<f32>(val), brushTint, sat);

    let tintedLive = vec4<f32>(liveColor.rgb * tintColor, liveColor.a);

    // ── Click-stamp blooms: every live ripple dabs a soft round bloom ──
    // so single clicks paint even without dragging. Radius ~ brush * 1.5,
    // strength decays exponentially with age over a ~1.5s usable life.
    var stamp = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 3.0) { continue; }
        let rDiff = (uv - ripple.xy) * aspectCorrection;
        let rDist = length(rDiff);
        let rRadius = radius * 1.5;
        let bloom = 1.0 - smoothstep(rRadius * 0.5, rRadius, rDist);
        stamp = max(stamp, bloom * exp(-age * 2.0));
    }

    // Click blooms merge with the drag stroke into one paint mask.
    let brushMask = max(brush, stamp);

    // ── History update (RAW feedback - never tonemapped) ────────────
    let decay = 1.0 - (1.0 - freezeDecay) * 0.25 * (1.0 - bass * 0.03);
    var newHistoryColor = historyColor * decay;

    let mixFactor = brushMask * depthOpacity * (1.0 + bass * 0.3);
    if (eraseMode) {
        // Unfreeze: brush strokes thaw history back toward the live frame.
        newHistoryColor = mix(newHistoryColor, liveColor, mixFactor);
    } else {
        // Freeze: brush strokes stamp chromatic tinted paint into history.
        newHistoryColor = mix(newHistoryColor, tintedLive, mixFactor);
    }

    let alpha = clamp(newHistoryColor.a + brushMask * 0.15 + bass * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(newHistoryColor.rgb, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
