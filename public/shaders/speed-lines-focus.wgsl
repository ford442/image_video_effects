// ═══════════════════════════════════════════════════════════════════
//  Speed Lines Focus
//  Category: artistic
//  Features: [mouse-driven, audio-reactive, upgraded-rgba]
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  Batch-21: spring-damped focus point, click action bursts,
//            angular FFT voices, normalized depth write
//  upgraded-rgba
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
  zoom_params: vec4<f32>,  // x=BlurStrength, y=LineDensity, z=LineSpeed, w=Contrast
  ripples: array<vec4<f32>, 50>,
};

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

fn noise1(p: f32) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(hash11(i), hash11(i + 1.0), u);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let aspect = resolution.x / resolution.y;
    let rawMouse = u.zoom_config.yz;  // raw cursor stays the spring target

    // ── Spring-damped focus point ────────────────────────────────────
    // Persistent state in extraBuffer[133..137] ([0..4] reserved,
    // [5..132] = engine FFT bins): 133/134 = sprung focus (uv space),
    // 135/136 = spring velocity, 137 = last update time. Only thread
    // (0,0) integrates; every other thread reads last frame's state.
    var mouse = rawMouse;
    let hasState = arrayLength(&extraBuffer) > 137u;
    if (hasState) {
        mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasState) {
        let prevTime = extraBuffer[137];
        let dt = clamp(time - prevTime, 0.001, 0.05);
        var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (prevTime <= 0.0) {
            // First touch: seed the spring at the cursor so it never snaps.
            sPos = rawMouse;
            sVel = vec2<f32>(0.0, 0.0);
        }
        // Critically damped spring: stiffness = omega^2, damping = 2*omega.
        let omega = 9.0;
        let accel = (rawMouse - sPos) * (omega * omega) - sVel * (2.0 * omega);
        sVel = sVel + accel * dt;
        sPos = sPos + sVel * dt;
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = time;
    }

    // Params (zoom_params contract: same ids/defaults as the JSON params)
    let blurStrength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.2);
    let lineDensity = u.zoom_params.y * 50.0 + 10.0;
    let lineSpeed = u.zoom_params.z * 10.0 + 2.0;
    let contrast = (u.zoom_params.w + 0.5) * (1.0 + treble * 0.2);

    // Center on the SPRUNG mouse so the vortex trails the cursor with
    // momentum; the 16-tap blur then smears naturally on fast moves.
    let uvCenter = uv - mouse;
    let uvCenterAspect = vec2<f32>(uvCenter.x * aspect, uvCenter.y);
    let dist = length(uvCenterAspect);
    let angle = atan2(uvCenterAspect.y, uvCenterAspect.x);

    // 1. Zoom Blur
    var blurColor = vec3<f32>(0.0);
    let samples = 16;
    for (var i = 0; i < samples; i++) {
        let t = f32(i) / f32(samples - 1);
        let scale = 1.0 - t * blurStrength * dist;
        let sampleUV = mouse + uvCenter * scale;
        blurColor += textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    }
    blurColor = blurColor / f32(samples);

    // Angular FFT voices: 8 sectors around the focus, each sector's line
    // intensity rides its own spectrum bin so the speed lines pulse
    // around the spectrum instead of flashing uniformly.
    let sector = u32((angle / 6.28318 + 0.5) * 8.0);
    let sectorVoice = plasmaBuffer[(sector % 8u) + 1u].x;
    let voiceGain = 1.0 + clamp(sectorVoice, 0.0, 1.0) * 1.5;

    // 2. Speed Lines
    let n = noise1(angle * lineDensity + time * lineSpeed);
    let lines = smoothstep(0.6, 0.8, n);
    let centerMask = smoothstep(0.2, 0.5, dist);
    let lineEffectBase = lines * centerMask * contrast;
    var lineEffect = lineEffectBase * voiceGain;

    // ── Click action bursts ──────────────────────────────────────────
    // Each live ripple flashes a radial speed-line burst at its click
    // point: an expanding ring of angular streaks emanating from the
    // click angle with a ~1.0s fade — a manga impact frame per click.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age > 1.0) { continue; }
        let rpCenter = uv - rp.xy;
        let rpAspect = vec2<f32>(rpCenter.x * aspect, rpCenter.y);
        let rpDist = length(rpAspect);
        let rpAngle = atan2(rpAspect.y, rpAspect.x);
        // Expanding burst ring traveling outward from the click point.
        let burstRadius = age * 0.9;
        let burstRing = 1.0 - smoothstep(0.0, 0.25, abs(rpDist - burstRadius));
        // Angular streaks spinning out of the click angle.
        let burstNoise = noise1(rpAngle * (lineDensity * 0.5) - age * 12.0);
        let burstLines = smoothstep(0.45, 0.75, burstNoise);
        let fade = 1.0 - age;  // ~1.0s fade
        lineEffect = lineEffect + burstRing * burstLines * fade * contrast;
    }

    // Composite
    var finalColor = blurColor + vec3<f32>(lineEffect);

    // Optional: Darken edges (Vignette)
    finalColor *= (1.0 - dist * 0.5);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Alpha: preserve input transparency, blend to opaque based on effect intensity
    let effectIntensity = clamp(blurStrength * dist * 2.0 + lineEffect, 0.0, 1.0);
    let finalAlpha = mix(baseColor.a, 1.0, effectIntensity);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, finalAlpha));
}
