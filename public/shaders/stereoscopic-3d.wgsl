// ═══════════════════════════════════════════════════════════════════
//  Stereoscopic 3D
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, depth-aware,
//            upgraded-rgba, anaglyph, 16x16-workgroup, early-exit,
//            branchless-channel-compositing
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-07-08, 2026-11-19
//  Ideas: anaglyph crosstalk; vertical vergence; focal defocus
//  A packing: raw state (envBass, smoothMouse.xy, trailIntensity)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Tuning constants (replaces inline magic numbers) ──────────────
const MAX_SEPARATION_SCALE: f32 = 0.05;
const FOCAL_WARP_RANGE: f32     = 0.3;
const MOUSE_BIAS_RANGE: f32     = 2.0;
const LENS_ROTATION_RANGE: f32  = 0.4;
const MOUSE_ROT_NUDGE: f32      = 0.15;
const MOUSE_ROT_TILT: f32       = 0.1;
const AUDIO_PULSE_GAIN: f32     = 0.4;
const GLITCH_AMP: f32           = 0.02;
const GHOST_AMP: f32            = 0.003;
const TRAIL_BLEND: f32          = 0.12;
const INTENSITY_GLITCH_W: f32   = 0.5;
const EARLY_EXIT_THRESH: f32    = 0.001;

// ── Branchless anaglyph channel masks ─────────────────────────────
const RED_MASK:  vec3<f32> = vec3<f32>(1.0, 0.0, 0.0);
const CYAN_MASK: vec3<f32> = vec3<f32>(0.0, 1.0, 1.0);

// ── Helpers ───────────────────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn aces(x_in: vec3<f32>) -> vec3<f32> {
    let x = max(x_in, vec3<f32>(0.0));
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Attack/release envelope for bass to eliminate raw strobe
fn bass_env(prev: f32, raw: f32) -> f32 {
    let k = select(0.15, 0.8, raw > prev);
    return mix(prev, raw, k);
}

fn rot2(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn audio_boost(envBass: f32, mids: f32) -> f32 {
    return 1.0 + envBass * 0.25 + mids * 0.1;
}

fn sparkle_tint(treble: f32, mids: f32) -> vec3<f32> {
    return vec3<f32>(
        treble * 0.08 + mids * 0.03,
        treble * 0.04 + mids * 0.02,
        treble * 0.12
    );
}

fn compute_alpha(trailIntensity: f32, lum: f32, envBass: f32) -> f32 {
    return clamp(mix(0.6, 1.0, trailIntensity * 0.5 + lum * 0.3 + envBass * 0.2), 0.0, 1.0);
}

// ── Main ──────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Previous frame state: r=envBass, g=smoothMouse.x, b=smoothMouse.y, a=trailIntensity
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Audio envelope + spring-damped mouse follow
    let envBass     = bass_env(prev.r, bass);
    let rawMouse    = u.zoom_config.yz;
    let mouseDown   = u.zoom_config.w;
    let snap        = select(0.06, 0.3, mouseDown > 0.5);
    let smoothMouse = mix(prev.gb, rawMouse, vec2<f32>(snap));

    // User params
    let maxSep      = u.zoom_params.x * MAX_SEPARATION_SCALE;
    let focusOffset = u.zoom_params.y;
    let glitchStr   = u.zoom_params.z;
    let lensRot     = (u.zoom_params.w - 0.5) * LENS_ROTATION_RANGE;

    // Depth pass-through (textureLoad avoids an extra sampler sample)
    let depth = textureLoad(readDepthTexture, pixel, 0).r;

    // Convergence bias and focal plane
    let mouseBias = (smoothMouse.x - 0.5) * MOUSE_BIAS_RANGE;
    let focalWarp = (smoothMouse.y - 0.5) * FOCAL_WARP_RANGE;
    let sceneDepth = (uv01.y - focusOffset + focalWarp) + mouseBias;

    // Beat-reactive separation
    let clickBoost = select(1.0, 1.3, mouseDown > 0.5);
    let audioPulse = 1.0 + envBass * AUDIO_PULSE_GAIN * clickBoost;
    var sepOffset  = vec2<f32>(sceneDepth * maxSep * audioPulse, 0.0);

    // Envelope-driven glitch
    let jitter     = sin(uv01.y * 200.0 + time * 30.0) * cos(time * 15.0);
    let block      = floor(uv01.y * 20.0);
    let blockNoise = fract(sin(block * 12.9898 + time) * 43758.5453);
    let glitchFactor = (jitter * 0.5 + blockNoise * 0.5) * (1.0 + envBass * 3.0);
    sepOffset.x = sepOffset.x + glitchFactor * glitchStr * GLITCH_AMP;

    // Rotation: param + mouse nudge
    let rot = lensRot + smoothMouse.x * MOUSE_ROT_NUDGE + (smoothMouse.y - 0.5) * MOUSE_ROT_TILT;
    sepOffset = rot2(rot) * sepOffset;

    // ── Idea 2: vertical vergence ─────────────────────────────────
    // A rotated cardboard mount slips the eyes vertically with depth.
    // Lens Rotation is 0 at the saved default, so the slip is 0 there.
    let vergence = sceneDepth * lensRot * 0.035;
    sepOffset = vec2<f32>(sepOffset.x, sepOffset.y + vergence);

    // Temporal ghost trails from previous intensity
    let prevIntensity = prev.a;
    let ghost = prevIntensity * GHOST_AMP;
    let redUV  = clamp(uv01 - sepOffset - vec2<f32>(ghost, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let cyanUV = clamp(uv01 + sepOffset + vec2<f32>(ghost, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    // ── Idea 3: focal defocus ─────────────────────────────────────
    // sceneDepth is already the distance to the focal plane. Off that
    // plane the photo softens. Focus Offset still places the plane.
    let blurMix = smoothstep(0.08, 0.55, abs(sceneDepth));
    let blurOff = vec2<f32>(blurMix * 0.0045, blurMix * 0.0012);

    // Early exit when disparity is effectively zero: one sample, no eye split.
    let disparity = length(sepOffset) + ghost;
    var color: vec3<f32>;
    if (disparity < EARLY_EXIT_THRESH) {
        let sharp = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
        let soft = textureSampleLevel(readTexture, u_sampler, clamp(uv01 + blurOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        color = mix(sharp.rgb, soft.rgb, blurMix);
    } else {
        // Branchless channel compositing: red from left eye, green+blue from right eye
        let leftSharp  = textureSampleLevel(readTexture, u_sampler, redUV,  0.0);
        let rightSharp = textureSampleLevel(readTexture, u_sampler, cyanUV, 0.0);
        let leftSoft  = textureSampleLevel(readTexture, u_sampler, clamp(redUV + blurOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        let rightSoft = textureSampleLevel(readTexture, u_sampler, clamp(cyanUV + blurOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        let leftEye = mix(leftSharp, leftSoft, blurMix);
        let rightEye = mix(rightSharp, rightSoft, blurMix);
        color = leftEye.rgb * RED_MASK + rightEye.rgb * CYAN_MASK;
        // ── Idea 1: anaglyph crosstalk ────────────────────────────
        // Cheap glasses leak the other eye. Glitch Jitter owns the leak.
        let leak = glitchStr * 0.55;
        let redLeak = dot(rightEye.rgb, vec3<f32>(0.2126, 0.7152, 0.0722)) * leak;
        let cyanLeak = dot(leftEye.rgb, vec3<f32>(0.2126, 0.7152, 0.0722)) * leak;
        color = color + vec3<f32>(redLeak * 0.45, cyanLeak * 0.28, cyanLeak * 0.28);
    }

    // Treble sparkle + mids warmth
    color += sparkle_tint(treble, mids);

    // Intensity for trails and semantic alpha
    let currentIntensity = clamp(abs(sceneDepth) * 2.0 + length(sepOffset) * 20.0 + glitchStr * INTENSITY_GLITCH_W, 0.0, 1.0);
    let trailIntensity   = mix(prevIntensity, currentIntensity, TRAIL_BLEND);

    // Audio-reactive color boost
    color *= audio_boost(envBass, mids);

    // Pack state for next frame. A is the raw tuple C reads next frame.
    // Do not tone-map it.
    let state = vec4<f32>(envBass, smoothMouse.x, smoothMouse.y, trailIntensity);
    textureStore(dataTextureA, pixel, state);

    // Semantic alpha encodes interaction intensity / bloom weight
    let alpha = compute_alpha(trailIntensity, luma(color), envBass);
    textureStore(writeTexture, pixel, vec4<f32>(aces(color), alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
