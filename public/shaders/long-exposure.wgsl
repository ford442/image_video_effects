// ═══════════════════════════════════════════════════════════════════
//  Long Exposure Light Painting
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Description: Simulates an open camera shutter accumulating light over
//    time. Bright regions of each frame persist and blend into a glowing
//    exposure buffer; darker regions fade slowly, leaving luminous trails.
//    Mouse click resets the exposure. Bass brightens incoming frames for
//    punchier accumulation; mids control the glow bloom radius; treble
//    adds fine sparkle to the brightest traces.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=accumulation_speed, y=decay_rate, z=glow_radius, w=threshold
//
//  Upgrade notes (Batch 20):
//    - Glow Radius is REAL: bloom taps step +/- gStep texels derived from
//      the slider (was a dead gOff with a fixed 3x3 +/-1 blur).
//    - Mouse click is a POSITIONAL eraser brush: full-strength reset near
//      the cursor (aspect-corrected ~0.25 radius), gentle global reset
//      stays at 10% base strength while the button is held.
//    - Live ripples stamp decaying warm exposure flashes at their click
//      points (~1.5 s fade), so single clicks paint light.
//    - Decay drifts per vertical band via FFT bins, so trails linger
//      differently across the spectrum.

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=accum_speed, y=decay, z=glow_r, w=threshold
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / res;

    // Audio bands: bass drives input gain, mids the halo, treble the sparkle
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let time   = u.config.x;
    let aspect = res.x / max(res.y, 1.0);

    // Current camera frame
    let current  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let curRGB   = current.rgb * (1.0 + bass * 0.4);  // bass brightens incoming

    // Accumulated exposure from previous frame (stored in dataTextureC)
    let prevAccum = textureLoad(dataTextureC, coord, 0);
    let prevRGB   = prevAccum.rgb;

    // Threshold: only pixels brighter than threshold contribute
    let threshold  = 0.05 + u.zoom_params.w * 0.35;
    let luma       = luminance(curRGB);
    let aboveThresh = clamp((luma - threshold) / max(1.0 - threshold, 0.001), 0.0, 1.0);

    // Contribution: bright pixels accumulate; dim ones don't add
    let accumSpeed = 0.04 + u.zoom_params.x * 0.20;
    let contribution = curRGB * aboveThresh * accumSpeed * (1.0 + treble * 0.25);

    // Decay: accumulated buffer slowly fades. Per-band drift lets FFT bins
    // modulate how long trails linger in each of 8 vertical bands, so the
    // spectrum paints its own rhythm into the exposure.
    let bandIdx   = clamp(u32(uv.y * 8.0), 0u, 7u) + 1u;
    let bandDrift = plasmaBuffer[bandIdx].x * 0.002;
    let decayRate = 0.97 + u.zoom_params.y * 0.029 + bandDrift;  // 0.97–0.999 + drift
    let decayed   = prevRGB * clamp(decayRate, 0.95, 0.999);

    // Positional click reset: holding the button is an ERASER BRUSH.
    // Full-strength reset inside an aspect-corrected ~0.25-radius disc
    // around the cursor, fading to zero outside it; a gentle global reset
    // at 10% of the old strength stays on as a base fade while held.
    let mouseDown  = u.zoom_config.w;
    let mUV        = u.zoom_config.yz;
    let brushDist  = length(vec2<f32>((uv.x - mUV.x) * aspect, uv.y - mUV.y));
    let brush      = 1.0 - smoothstep(0.0, 0.25, brushDist);
    let resetMix   = clamp(mouseDown * (0.015 + brush * 0.985), 0.0, 1.0);
    let afterReset = mix(decayed, vec3<f32>(0.0), resetMix);

    // Accumulate new contribution; clamp to avoid runaway brightness
    var accumulated = clamp(afterReset + contribution, vec3<f32>(0.0), vec3<f32>(1.5));

    // Ripple flashes: each live ripple stamps a bright, decaying warm blob
    // into the exposure at its click point (~1.5 s fade), so a single
    // click paints a burst of light that lingers like everything else.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple  = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 1.5) {
            let rDist = length(vec2<f32>((uv.x - ripple.x) * aspect, uv.y - ripple.y));
            let blob  = smoothstep(0.25, 0.0, rDist) * exp(-elapsed * 2.0);
            let warm  = vec3<f32>(1.0, 0.9, 0.75);
            accumulated = clamp(accumulated + warm * blob * 0.6, vec3<f32>(0.0), vec3<f32>(1.5));
        }
    }

    // Glow bloom: 4-tap cross blur of the accumulated buffer. The tap
    // distance gStep is derived from the Glow Radius slider (clamped to
    // [1, 64] texels), so the halo genuinely widens with the slider —
    // default 0.3 maps to ~5 px at 2048 width.
    let glowR  = max(0.002, u.zoom_params.z * 0.008) * res.x;
    let gStep  = clamp(i32(glowR), 1, 64);
    let gMax   = vec2<i32>(res) - vec2<i32>(1);
    var glow   = accumulated;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(gStep, 0), vec2<i32>(0), gMax), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(-gStep, 0), vec2<i32>(0), gMax), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, gStep), vec2<i32>(0), gMax), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -gStep), vec2<i32>(0), gMax), 0).rgb;
    let glowAmt  = (0.1 + mids * 0.3) * u.zoom_params.z;
    let glowBlend = glow * (1.0 / 5.0) * glowAmt;
    accumulated   = clamp(accumulated + glowBlend, vec3<f32>(0.0), vec3<f32>(1.5));

    // Treble sparkle: only the hottest traces shimmer, modulated by a
    // cheap spatial phase pattern so the brightest trails twinkle with
    // high-frequency energy instead of the whole buffer pulsing.
    let sparkleMask = smoothstep(0.9, 1.4, luminance(accumulated));
    let shimmer     = 0.5 + 0.5 * sin(time * 9.0 + uv.x * 61.0 + uv.y * 47.0);
    accumulated     = clamp(accumulated + accumulated * sparkleMask * shimmer * treble * 0.15, vec3<f32>(0.0), vec3<f32>(1.5));

    // Final output: tone-map accumulation back to [0,1] (Reinhard)
    let finalRGB = accumulated / (accumulated + vec3<f32>(1.0));

    // Alpha: bright trails are opaque; fresh dark areas stay transparent
    let accumLuma = luminance(finalRGB);
    let alpha     = clamp(accumLuma * 1.4 + bass * 0.08, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(accumulated, 1.0));  // store raw HDR for next frame
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
