// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
// ═══════════════════════════════════════════════════════════════════
//  Kaleido Portal Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, spring-portal,
//            click-spin-bursts, hdr-tamed
//  Complexity: Medium
//  Chunks From: kaleido-portal-interactive
//  Created: 2026-05-30
//  By: Copilot CLI
//  Upgraded: 2026-07-30 (Batch 17, Visualist)
//    - Priority 1: HDR border glow soft-knee + clamped (was up to ~7.0 raw)
//    - Critically-damped spring on portal center (extraBuffer[133..138])
//    - Click counter-rotation bursts kick the mandala into a spin
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=Segments, z=Rotation, w=Hardness
  ripples: array<vec4<f32>, 50>,
};

// Persistent shader state in extraBuffer ([133..255] only; 0..132 are reserved/engine):
//   [133..134] = springed portal center (xy)
//   [135]      = last frame time (for dt)
//   [136..137] = spring velocity (xy)
//   [138]      = init flag (0.0 => uninitialized)
//   [139]      = spin phase accumulated from click bursts
// All invocations compute identical values, so the racy-but-identical writes are benign.

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // --- Slider mapping (shader-specific constants of THIS algorithm) ---
    let radius = mix(0.1, 0.5, u.zoom_params.x) * (1.0 + bass * 0.12);
    let segments = floor(mix(3.0, 16.0, u.zoom_params.y) + treble * 2.0);
    let rotationSpeed = u.zoom_params.z * (0.5 + mids * 0.6);
    let hardness = mix(0.01, 0.2, u.zoom_params.w);

    // --- Frame dt (clamped so tab-switch pauses don't explode the spring) ---
    let dt = clamp(time - extraBuffer[135], 0.0, 0.05);
    extraBuffer[135] = time;

    // --- Technique 2: critically-damped spring on the portal center -------
    // Raw mouse is the spring target; the kaleidoscope glides toward it.
    let rawMouse = u.zoom_config.yz;
    var springCenter = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var springVel = vec2<f32>(extraBuffer[136], extraBuffer[137]);
    if (extraBuffer[138] < 0.5) {
        springCenter = rawMouse;
        springVel = vec2<f32>(0.0, 0.0);
        extraBuffer[138] = 1.0;
    }
    let springK = 90.0;                      // stiffness
    let springC = 2.0 * sqrt(springK);       // critical damping ratio = 1.0
    let springAccel = (rawMouse - springCenter) * springK - springVel * springC;
    springVel = springVel + springAccel * dt;
    springCenter = clamp(springCenter + springVel * dt, vec2<f32>(-0.1, -0.1), vec2<f32>(1.1, 1.1));
    extraBuffer[133] = springCenter.x;
    extraBuffer[134] = springCenter.y;
    extraBuffer[136] = springVel.x;
    extraBuffer[137] = springVel.y;

    // --- Technique 3: click counter-rotation bursts -----------------------
    // Each live ripple contributes a decaying angular velocity spike; the sign
    // alternates per ripple index so successive clicks spin opposite ways.
    var burstVel = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 2.0) {
            let dirSign = select(1.0, -1.0, (i & 1u) == 1u);
            // Sharp attack, ~2s exponential decay => a visible spin kick.
            let decay = exp(-age * 2.5) * (1.0 - age * 0.5);
            burstVel = burstVel + dirSign * decay * 6.0;
        }
    }
    // Integrate the burst velocity into a persistent spin phase so the mandala
    // winds down smoothly instead of snapping back when the burst ends.
    let spinPhase = extraBuffer[139] + burstVel * dt;
    extraBuffer[139] = spinPhase;

    // The springed center drives the portal; downstream fold math is verbatim.
    var mouse = springCenter;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let mask = 1.0 - smoothstep(radius, radius + hardness, dist);

    var finalUV = uv;

    if (mask > 0.0) {
        let rel = uv - mouse;
        let relCorrected = rel * vec2<f32>(aspect, 1.0);
        var angle = atan2(relCorrected.y, relCorrected.x);
        let rad = length(relCorrected);
        let segmentAngle = 6.2831853 / max(segments, 1.0);

        angle = angle + time * rotationSpeed + spinPhase;
        if (angle < 0.0) {
            angle = angle + 6.2831853;
        }

        var a = angle % segmentAngle;
        if (a > segmentAngle * 0.5) {
            a = segmentAngle - a;
        }

        let newDir = vec2<f32>(cos(a), sin(a));
        let newRelCorrected = newDir * rad;
        let newRel = vec2<f32>(newRelCorrected.x / aspect, newRelCorrected.y);
        let kaleidoUV = clamp(mouse + newRel, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
        finalUV = mix(uv, kaleidoUV, mask);
    }

    let border = smoothstep(radius, radius + 0.01, dist) * (1.0 - smoothstep(radius + 0.01, radius + 0.02 + hardness, dist));

    // --- Technique 1 (PRIORITY): tame the HDR border glow ------------------
    // Was: border * (5.0 + bass * 2.0) added raw => up to ~7.0 in rgba32float.
    // Now: soft-knee compresses the hot core, then a hue-preserving cap at 1.5
    // keeps the border legal while bass still visibly pumps it.
    let borderGlowRaw = border * (5.0 + bass * 2.0);
    let borderGlowSoft = borderGlowRaw / (1.0 + borderGlowRaw * 0.35);
    let borderGlow = min(borderGlowSoft, 1.5);
    let borderColor = vec3<f32>(0.5 + treble * 0.2, 0.8 + mids * 0.15, 1.0);

    let base = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    var finalColor = base.rgb + borderColor * borderGlow;
    // Safety net: gentle reinhard on the combined result so nothing leaves
    // the portal above ~1.7 even if a future edit re-heats the border.
    finalColor = finalColor / (1.0 + max(finalColor - vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.0, 0.0, 0.0)) * 0.3);

    let finalAlpha = clamp(base.a * (1.0 - mask * 0.25) + border * (0.32 + bass * 0.16) + mask * 0.18, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r + mask * 0.04, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(mask, border, segments / 16.0, finalAlpha));
}
