// ═══════════════════════════════════════════════════════════════════
//  Chroma Kinetic
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, velocity-chromatic, directional-smear, upgraded-rgba
//  Complexity: High
//  Chunks From: chroma-kinetic, bass_env, temporal-feedback
//  Created: 2026-05-10
//  Upgraded: 2026-08-02
//  Notes: sprung effect center (critically-damped, extraBuffer[133..138]),
//         flick-speed strength bonus, click kinetic bursts (ripples),
//         per-sector FFT voices on the smear mix.
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
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=LumaInfluence, w=Rotation
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;   // raw cursor = spring TARGET
    let isMouseDown = u.zoom_config.w; // mouseDown flag

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = mix(0.5, 1.5, depth);

    // ── Spring-damper effect center (extraBuffer[133..138]) ─────────
    // [133..134] sprung position, [135..136] spring velocity,
    // [137] last integration time, [138] initialized flag.
    // Thread (0,0) integrates a critically-damped spring toward the raw
    // cursor so the distortion field glides instead of snapping.
    let hasState = arrayLength(&extraBuffer) > 138u;
    var center = mousePos;
    var springVel = vec2<f32>(0.0);
    if (hasState && extraBuffer[138] > 0.5) {
        center = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasState) {
        var springPos = center;
        var nextVel = springVel;
        if (extraBuffer[138] <= 0.5) {
            springPos = mousePos;
            nextVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 10.0;
            let accel = (mousePos - springPos) * (omega * omega) - nextVel * (2.0 * omega);
            nextVel += accel * dt;
            springPos += nextVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = nextVel.x;
        extraBuffer[136] = nextVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    // Kinetic flick bonus: fast cursor flicks smear harder.
    let springSpeed = length(springVel);
    var strength = u.zoom_params.x * 0.1 * bass_env(bass, mids) * depthMod;
    strength *= 1.0 + min(springSpeed * 3.0, 0.4);
    let radius = u.zoom_params.y;
    let lumaInf = u.zoom_params.z;
    let rotation = u.zoom_params.w * 6.28318;

    let diff = uv - center;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);
    let dir = diffAspect / max(dist, 0.001);

    let c = cos(rotation);
    let s = sin(rotation);
    let rotDir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
    let uvOffsetDir = vec2<f32>(rotDir.x / max(aspect, 0.001), rotDir.y);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let falloff = smoothstep(max(radius, 0.001), 0.0, dist);
    let modFactor = max(0.0, 1.0 + (luma - 0.5) * lumaInf * 2.0);

    // Velocity chromatic aberration: R leads, B lags based on motion direction
    var velocity = uvOffsetDir * strength * falloff * modFactor;

    // ── Click kinetic bursts ────────────────────────────────────────
    // Each live ripple fires a decaying directional smear pulse at its
    // click point: exp(-rippleAge * 2.0) boost, aspect-corrected ~0.25
    // radius, direction radial from the click, ~1.2s lifetime.
    let rippleTotal = min(u32(u.config.y), 50u);
    for (var ri: u32 = 0u; ri < rippleTotal; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let rippleAge = time - ripple.z;
        if (rippleAge >= 0.0 && rippleAge <= 1.2) {
            let toRipple = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let rippleDist = length(toRipple);
            let pulse = exp(-rippleAge * 2.0) * smoothstep(0.25, 0.0, rippleDist);
            let radialDir = toRipple / max(rippleDist, 0.001);
            let burstDir = vec2<f32>(radialDir.x / max(aspect, 0.001), radialDir.y);
            velocity += burstDir * pulse * strength * 2.0;
        }
    }

    let leadAmount = velocity * (1.0 + bass * 0.5);
    let lagAmount = velocity * (1.0 + mids * 0.3);

    let uvR = clamp(uv - leadAmount, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv - velocity * 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + lagAmount, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Directional smear: sample along velocity vector for motion trails
    let smearSamples = 3;
    var smearR = 0.0;
    var smearG = 0.0;
    var smearB = 0.0;
    for (var i = 1; i <= smearSamples; i = i + 1) {
        let t = f32(i) / f32(smearSamples);
        let smearUV = clamp(uv + velocity * t * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
        let smearColor = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
        smearR = smearR + smearColor.r * (1.0 - t);
        smearG = smearG + smearColor.g * (1.0 - t);
        smearB = smearB + smearColor.b * (1.0 - t);
    }
    smearR = smearR / f32(smearSamples);
    smearG = smearG / f32(smearSamples);
    smearB = smearB / f32(smearSamples);

    // ── Per-sector FFT voices ───────────────────────────────────────
    // The field splits into 8 angular sectors around the sprung center;
    // each sector's smear mix rides its own spectrum bin, so the
    // chromatic trail shimmers directionally with the audio.
    let angle = atan2(diffAspect.y, diffAspect.x);
    let sector = u32(clamp(floor((angle + 3.14159) * 8.0 / 6.28318), 0.0, 7.0));
    let sectorVoice = plasmaBuffer[(sector % 8u) + 1u].x * 0.25;

    let finalR = mix(r, smearR, bass * 0.3 + sectorVoice);
    let finalG = mix(g, smearG, mids * 0.2 + sectorVoice);
    let finalB = mix(b, smearB, treble * 0.2 + sectorVoice);
    let color = vec3<f32>(finalR, finalG, finalB);

    // Audio split: bass shifts hue globally, mids add glow
    let dispersion = length(velocity) / max(strength, 0.001);
    let alpha = clamp(falloff * modFactor * 0.6 + dispersion * 0.3 + 0.1 + treble * 0.05, 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalRGBA);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalRGBA);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
