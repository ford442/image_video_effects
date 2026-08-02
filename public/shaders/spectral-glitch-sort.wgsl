// ═══════════════════════════════════════════════════════════════════
//  Spectral Glitch Sort
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17, 2026-07-31 (Optimizer: aspect-corrected
//            spring-damped sort epicenter, click sort tears,
//            per-block FFT voices)
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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // y=MouseX, z=MouseY
  zoom_params: vec4<f32>,  // x=Strength, y=Threshold, z=Angle, w=Noise
  ripples: array<vec4<f32>, 50>,
};

fn getLuma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = u.config.zw;
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / dims;
    let time = u.config.x;

    // Aspect ratio: correcting both uv and mouse by (aspect, 1.0) keeps
    // the influence zone circular instead of elliptical on wide canvases.
    let aspect = dims.x / max(dims.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Sliders (saved-preset contract: u.zoom_params.x/y/z/w) ──────
    // x = Sort Length:    max displacement, bass amplifies sort strength
    // y = Luma Threshold: brightness floor for sortable pixels
    // z = Direction:      sort axis angle (default 0 = 0 radians)
    // w = Digital Noise:  per-block hash modulation of the sort length
    let strength    = mix(0.0, 0.5, u.zoom_params.x) * (1.0 + bass * 0.4);
    let threshold   = u.zoom_params.y;
    let angleParam  = u.zoom_params.z * 6.28;
    let noiseAmt    = u.zoom_params.w;

    // ── Spring-damped sort epicenter ─────────────────────────────────
    // Persistent eased-mouse state lives in extraBuffer[133..136]
    // (safe zone; [0..4] engine-reserved, [5..132] engine FFT bins):
    //   [133..134] = eased mouse position (uv)
    //   [135..136] = eased mouse velocity
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    // First frames: snap to the cursor — no fly-in from origin.
    if (mousePos.x == 0.0 && mousePos.y == 0.0 && time < 2.0) {
        mousePos = rawMouse;
        mouseVel = vec2<f32>(0.0);
    }
    // Critically-damped semi-implicit spring: the epicenter glides
    // behind the raw cursor instead of snapping to it.
    let springK = 0.16;
    let damping = 0.74;
    mouseVel = (mouseVel + (rawMouse - mousePos) * springK) * damping;
    mousePos = mousePos + mouseVel;
    extraBuffer[133] = mousePos.x;
    extraBuffer[134] = mousePos.y;
    extraBuffer[135] = mouseVel.x;
    extraBuffer[136] = mouseVel.y;

    // Aspect-corrected distance to the eased epicenter.
    let mouseDist = distance(uv * aspectVec, mousePos * aspectVec);

    // ── Click sort tears ─────────────────────────────────────────────
    // Each live ripple rips the sort: a decaying directional tear at its
    // click point (local strength spike + brief angle perturbation,
    // ~0.8s fade). Fully branchless: masks, no early exits.
    let rippleCount = min(u32(u.config.y), 50u);
    var tearBoost = 0.0;
    var tearAngle = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i]; // xy = click pos (uv), z = birth time
        let age = time - ripple.z;
        // Live-window mask with a ~0.8s linear fade.
        let liveMask = f32(age >= 0.0 && age < 0.8);
        let fade = max(0.0, 1.0 - age * 1.25) * liveMask;
        // Aspect-corrected distance to the tear epicenter.
        let tearDist = distance(uv * aspectVec, ripple.xy * aspectVec);
        let tearMask = smoothstep(0.35, 0.0, tearDist) * fade;
        // Stable per-click tear direction from the click point hash.
        let tearSeed = hash12(ripple.xy + vec2<f32>(ripple.z));
        tearAngle = tearAngle + tearMask * (tearSeed - 0.5) * 2.4;
        tearBoost = tearBoost + tearMask * 1.5;
    }

    // Direction slider sets the base axis; click tears perturb it locally.
    let sortAngle = angleParam + tearAngle;
    let dir = vec2<f32>(cos(sortAngle), sin(sortAngle));

    let cSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let c = cSample.rgb;
    let luma = getLuma(c);

    let dispFactor = smoothstep(threshold, threshold + 0.2, luma);

    // Glitch noise block
    let blockUV  = floor(uv * 20.0) / 20.0;
    let noiseVal = hash12(blockUV + u.config.x * 0.1);

    // Per-block FFT voices: each column of glitch blocks listens to its
    // own spectrum bin (plasmaBuffer[1..8] = engine FFT bins), so the
    // blocks flicker with the spectrum instead of uniformly.
    let binIndex = (u32(blockUV.x * 8.0) % 8u) + 1u;
    let blockVoice = plasmaBuffer[binIndex].x;
    let noiseVoiced = noiseVal * (1.0 + blockVoice * 1.5);

    // Mouse proximity increases strength
    let influence = 1.0 - smoothstep(0.0, 0.5, mouseDist);
    var finalStrength = strength * (1.0 + influence * 2.0);

    // Click tears spike the local sort strength on top of the proximity.
    finalStrength = finalStrength + tearBoost * strength;

    // Branchless noise modulation — now voiced per-block by the FFT.
    finalStrength *= mix(1.0, noiseVoiced * 2.0, noiseAmt);

    let offset  = -dir * finalStrength * dispFactor;
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));

    var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // Chromatic aberration — branchless, scaled by offset magnitude
    let aberScale = smoothstep(0.005, 0.03, length(offset));
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.002, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(0.002, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    finalColor.r = mix(finalColor.r, rSample, aberScale);
    finalColor.b = mix(finalColor.b, bSample, aberScale);

    // Treble adds subtle high-freq shimmer
    finalColor += vec3<f32>(0.05) * treble * noiseVal;
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: sort displacement + luma + audio + tear energy
    let alpha = clamp(dispFactor * 0.5 + aberScale * 0.3 + bass * 0.1 + clamp(tearBoost, 0.0, 1.0) * 0.1 + cSample.a * 0.15, 0.0, 1.0);
    let fc = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
