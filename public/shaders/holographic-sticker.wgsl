// ═══════════════════════════════════════════════════════════════════
//  Holographic Sticker
//  Category: visual-effects
//  Features: advanced-alpha, depth-aware, mouse-driven, audio-reactive, chromatic-view-angle,
//            temporal-foil-shimmer, audio-sticker-pulse, depth-layered-alpha,
//            spring-glide-center, click-foil-flashes, guarded-palette-read
//  Complexity: Medium
//  Upgraded: 2026-07-30 (Batch 18, Visualist)
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
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

    // ── Sliders (saved-preset contract: ids/defaults unchanged) ──────
    let radius = u.zoom_params.x;       // Sticker Radius
    let intensity = u.zoom_params.y;    // Foil Intensity
    let rainbowSpeed = u.zoom_params.z; // Rainbow Speed (hue drift)
    let depthWeight = u.zoom_params.w;  // Depth Weight (alpha blend)

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let aspect = resolution.x / resolution.y;

    // ── Critically-damped spring: the foil glides after the cursor ───
    // extraBuffer map (persistent state lives in [133..255] ONLY):
    //   [133..134] = spring position (uv), [135..136] = spring velocity,
    //   [137] = last frame time, [138] = init flag.
    //   [0..4] reserved, [5..132] engine FFT bins - untouched.
    // Raw mouse stays the spring target; every thread reads the last
    // integrated position, only thread (0,0) integrates and writes.
    let rawMouse = u.zoom_config.yz;
    let hasState = (arrayLength(&extraBuffer) > 138u);
    var mouse = vec2<f32>(0.5, 0.5);
    if (hasState) {
        if (extraBuffer[138] > 0.5) {
            mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        }
    }
    let isWriter = ((global_id.x == 0u) && (global_id.y == 0u));
    if (isWriter && hasState) {
        let lastTime = extraBuffer[137];
        let dt = clamp(time - lastTime, 0.0, 0.1);
        var sPos = mouse;
        var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] < 0.5) {
            sPos = rawMouse; // first frame: start on the cursor, no glide-in
            sVel = vec2<f32>(0.0, 0.0);
        }
        // Critical damping: c = 2 * sqrt(k) = 14 for k = 49 - snappy glide.
        let stiffness = 49.0;
        let damping = 14.0;
        let accel = (rawMouse - sPos) * stiffness - sVel * damping;
        sVel = sVel + accel * dt;
        sPos = sPos + sVel * dt;
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    let dM = length(uv - mouse);

    let inCircle = smoothstep(radius, radius * 0.9, dM);

    // Iridescent hue from the view angle around the (spring-smoothed) center.
    let viewAngle = atan2((uv.y - mouse.y) * aspect, uv.x - mouse.x);
    let hue = fract(viewAngle / TAU + time * rainbowSpeed * 0.5 + depth * 0.1 + bass * 0.05);

    // HSV foil construction (k-vec palette math) - preserved verbatim.
    let saturation = 0.9 + treble * 0.1;
    let value = 0.8 + mids * 0.2;
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(vec3<f32>(hue, hue, hue) + k.xyz) * 6.0 - k.www);
    var foil = value * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), saturation);

    // GUARDED palette read: `plasmaBuffer[palIdx % 256u]` could index past the
    // real FFT bin count (the engine publishes far fewer vec4 bins), and OOB
    // storage reads return zeros - a dead black palette. Wrap into the
    // always-live bins 1..8 so the modulation is always real audio data.
    let palIdx = u32(clamp(hue * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[(palIdx % 8u) + 1u].rgb;
    foil = mix(foil, foil * (0.7 + palette * 0.5), 0.3);

    // ── Click foil flashes: clicks scatter hue-cycling rainbow rings ──
    var flash = vec3<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 1.5) { continue; }
        let ringRadius = age * 0.55;        // expanding front
        let ringDist = abs(length(uv - ripple.xy) - ringRadius);
        let ringWidth = 0.015 + age * 0.03; // band widens as it fades
        let ringMask = smoothstep(ringWidth, 0.0, ringDist);
        let decay = 1.0 - age / 1.5;        // ~1.5s fade-out
        // Hue-cycling band built from the same foil k-vec palette math.
        let ringHue = fract(hue + age * 0.9 + f32(i) * 0.17);
        let rp = abs(fract(vec3<f32>(ringHue, ringHue, ringHue) + k.xyz) * 6.0 - k.www);
        let ringColor = mix(k.xxx, clamp(rp - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), saturation);
        flash += ringColor * ringMask * decay * decay;
    }
    foil += flash * (0.35 + intensity * 0.65);

    let edgeGlow = smoothstep(radius * 1.1, radius, dM);
    foil = mix(foil, foil * 1.3, edgeGlow);

    // Audio-driven sticker pulse: radius expands/contracts with bass
    let pulse = 1.0 + bass * 0.2 * sin(time * 4.0);
    let pulsedCircle = smoothstep(radius * pulse, radius * 0.9 * pulse, dM);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var finalColor = mix(baseColor.rgb, baseColor.rgb * 0.4 + foil * intensity, pulsedCircle * inCircle);

    // Let the click flashes bleed past the sticker edge: rainbows scatter.
    finalColor += flash * 0.25;

    // Temporal foil shimmer: slow phase drift for organic iridescence
    // (kept subtle and raw - the A write below is never tonemapped).
    let prevFoil = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let shimmer = mix(finalColor, prevFoil * 0.95, 0.04 + mids * 0.015);
    finalColor = mix(finalColor, shimmer, 0.4);

    let alpha = depthLayeredAlpha(finalColor, uv, depthWeight);
    let stickerAlpha = mix(baseColor.a, 1.0, inCircle * 0.8);
    let finalAlpha = mix(alpha, stickerAlpha, inCircle * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 0));
}
