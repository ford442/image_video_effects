// ═══════════════════════════════════════════════════════════════════
//  Neon Ripple Split - Alpha Translucency Edition
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Transform: Replaced per-channel RGB sampling with unified
//             displacement field + spectral tint via mix().
//             Alpha encodes ripple displacement * bass pulse.
//             Added gravityWell mouse attraction and temporal feedback.
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
  zoom_params: vec4<f32>,  // x=SplitAmount, y=RippleSpeed, z=Intensity, w=SplitCount
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

// Fast approximate sin via parabolic min-max.
fn fastSin(x: f32) -> f32 {
    let x_red = x - TAU * floor((x + 3.14159265) / TAU);
    let xa = abs(x_red);
    return x_red * (1.0 - 0.21 * xa) - 0.063 * x_red * xa;
}

// ═══ Audio envelope (smooth attack/release) ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// ═══ Gravity well (mouse attraction) ═══
fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.01;
    return normalize(d) * strength / dist2;
}

// ═══ Tent alpha curve ═══
fn tentAlpha(x: f32) -> f32 {
    return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

// Spectral tint for mix-based color variation.
fn wavelengthToRGB(offset: f32) -> vec3<f32> {
    let t = fract(offset);
    let r = smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.5, 0.8, t));
    let g = smoothstep(0.2, 0.5, t) * (1.0 - smoothstep(0.7, 1.0, t));
    let b = smoothstep(0.5, 0.8, t) * (1.0 - smoothstep(0.9, 1.0, t) + smoothstep(0.0, 0.2, t));
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    let bass = plasmaBuffer[0].x;

    // ─── Audio envelope with attack/release, persisted in dataTextureA ───
    var prevEnv = 0.0;
    if (global_id.x == 0u && global_id.y == 0u) {
        prevEnv = textureSampleLevel(dataTextureC, u_sampler, vec2<f32>(0.0), 0.0).r;
    }
    let env = bass_env(prevEnv, bass, 0.8, 0.15);

    // ─── Parameters ───
    let splitAmount = u.zoom_params.x * 0.1 * (1.0 + env * 0.3);
    let rippleSpeed = u.zoom_params.y * 5.0;
    let intensity   = u.zoom_params.z * 2.0;
    let splitCount  = u.zoom_params.w * 5.0 + 2.0;

    // Mouse X modulates ripple speed, Mouse Y drives spectral phase
    let mouseSpeedMod = 1.0 + mousePos.x * 0.5;
    let effectiveRippleSpeed = rippleSpeed * mouseSpeedMod;
    let mouseTintPhase = mousePos.y * TAU * 0.5;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ─── Gravity well attracts ripples when mouse is clicked ───
    let wellStrength = select(0.0, 0.05, isMouseDown) * (1.0 + env * 0.5);
    let gWell = gravityWell(uv, mousePos, wellStrength);
    let gravityOffset = gWell * 0.02;

    // ─── Ripple system integration ───
    var rippleSum = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = distance(uv, rPos);
            let rWave = fastSin(rDist * 40.0 - rElapsed * 8.0) * exp(-rElapsed * 1.5);
            rippleSum = rippleSum + rWave * smoothstep(0.3, 0.0, rDist);
        }
    }

    // ─── Single smooth displacement field (NO per-channel UVs) ───
    let baseRipple = fastSin(uv.y * 20.0 - time * effectiveRippleSpeed) * splitAmount;
    let dx = (baseRipple * splitCount + rippleSum) * (1.0 + depth * 0.5);
    let smoothOffset = vec2<f32>(dx, 0.0) + gravityOffset;
    let displacedUV = clamp(uv + smoothOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    // Single sample from unified UV
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // ─── Temporal feedback via dataTextureC ───
    let displacementMagnitude = length(smoothOffset);
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let feedbackMix = tentAlpha(displacementMagnitude * 2.0) * 0.12;
    let feedbackColor = mix(baseColor, prevColor, feedbackMix);

    // ─── Spectral tint via mix(), NOT per-channel sampling ───
    let wavelengthOffset = uv.x * 2.0 + time * 0.3 + abs(dx) * 10.0 + mouseTintPhase;
    let spectralTint = wavelengthToRGB(wavelengthOffset);
    let tintStrength = tentAlpha(abs(dx) * 5.0) * intensity * 0.5;
    let tintedColor = mix(feedbackColor, feedbackColor * spectralTint * 1.5, tintStrength);

    // Neon emission proportional to displacement magnitude
    let absRipple = abs(baseRipple) + abs(rippleSum) * 0.5;
    let neon = vec3<f32>(1.0, 0.5, 0.8) * absRipple * 10.0 * intensity;
    let finalColor = tintedColor + neon;

    // ─── Alpha = ripple displacement * bass pulse + neon emission ───
    let bassPulse = 0.3 + env * 0.7;
    let neonAlpha = absRipple * 0.4 * intensity;
    let alpha = clamp(displacementMagnitude * bassPulse * 3.0 + neonAlpha, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Persist env at (0,0), color everywhere else in dataTextureA
    if (coord.x == 0 && coord.y == 0) {
        textureStore(dataTextureA, coord, vec4<f32>(env, 0.0, 0.0, 0.0));
    } else {
        textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
    }
    textureStore(dataTextureB, coord, vec4<f32>(finalColor, alpha));
}
