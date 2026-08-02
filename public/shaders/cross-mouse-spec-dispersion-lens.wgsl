// ═══════════════════════════════════════════════════════════════════
//  Crossover: Mouse + Spectral — Prismatic Lens
//  Category: interactive-mouse
//  Features: crossover, mouse-driven, spectral-rendering, audio-reactive, upgraded-rgba
//  Crosses: mouse-wormhole-lens (2C) + spec-prismatic-dispersion (3C)
//  Complexity: High
//  Created: 2026-04-19
//  By: Agent 5C — Phase C Crossover Integration
//  Upgraded: 2026-08-02 — Algorithmist swarm pass (aspect-correct lens,
//            critically-damped spring mouse, treble sparkle, click bursts)
// ═══════════════════════════════════════════════════════════════════
//
//  The mouse cursor becomes a prismatic lens that spectrally disperses
//  the input image. Moving the mouse changes the lens focal point;
//  clicking increases the dispersion intensity. The lens uses physical
//  refraction with Cauchy's equation for wavelength-dependent IOR.
//
//  Upgrade notes:
//   - The lens is now aspect-corrected: both uv and the (spring-smoothed)
//     mouse position are scaled by (aspect, 1.0) before the distance is
//     measured, so the lens stays circular on any canvas. The same
//     corrected vector drives the refraction normal so dispersion stays
//     radial, and the rim gaussian uses the corrected distance.
//   - The cursor glides on a critically-damped spring; persistent state
//     lives in extraBuffer[133..138] ([0..4] reserved, [5..132] = FFT).
//   - Treble now twinkles the fringes: dispR/dispB shimmer with
//     plasmaBuffer[6].x / plasmaBuffer[8].x respectively.
//   - Click ripples fire decaying dispersion bursts plus a brief spectral
//     ring at the burst edge, scattering rainbows on every click.
//
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

fn cauchyIOR(lambda: f32, n0: f32, B: f32) -> f32 {
    return n0 + B / (lambda * lambda);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let rawMouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let trebleLo = plasmaBuffer[6].x;
    let trebleHi = plasmaBuffer[8].x;

    // Bass breathes the lens aperture; mids widen spectral dispersion
    let lensRadius = mix(0.05, 0.3, u.zoom_params.x) * (1.0 + bass * 0.4);
    let dispersionScale = mix(0.0, 0.03, u.zoom_params.y) * (1.0 + mids * 0.5);
    let lensStrength = mix(0.5, 2.0, u.zoom_params.z);
    let rotationSpeed = mix(-1.0, 1.0, u.zoom_params.w);

    // Critically-damped spring: the prism glides toward the raw cursor.
    // Persistent state in extraBuffer[133..138]:
    //   [133..134] spring position, [135..136] spring velocity,
    //   [137] last integration time, [138] initialized flag.
    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mousePos = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
        mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
        var springPos = mousePos;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 8.0;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    let clickBoost = select(1.0, 2.0, mouseDown);
    var localDispersion = dispersionScale * clickBoost;

    // Aspect-corrected space: the lens stays circular on any canvas.
    let aspect = res.x / max(res.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);
    let uvC = uv * aspectVec;
    let mouseC = mousePos * aspectVec;
    let toMouse = uvC - mouseC;
    let mouseDist = length(toMouse);

    // Click spectrum flares: each live ripple fires a decaying dispersion
    // burst at its click point plus a brief spectral ring at the burst edge.
    var spectralRing = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge >= 0.0 && rippleAge < 1.2) {
            let rippleC = ripple.xy * aspectVec;
            let rippleDist = length(uvC - rippleC);
            let decay = exp(-rippleAge * 2.0);
            let burstMask = 1.0 - smoothstep(0.0, 0.25, rippleDist);
            localDispersion = localDispersion + decay * 1.5 * burstMask * dispersionScale;
            let ringEdge = exp(-pow((rippleDist / 0.25) - 1.0, 2.0) * 40.0);
            spectralRing = spectralRing + ringEdge * decay;
        }
    }

    // Lens profile: parabolic thickness
    let lensProfile = max(0.0, 1.0 - (mouseDist * mouseDist) / (lensRadius * lensRadius));
    let lensFactor = lensProfile * lensStrength;

    // Rotation over time
    let angle = time * rotationSpeed * 0.2 + lensProfile * 3.14159;
    let ca = cos(angle);
    let sa = sin(angle);
    let rotDir = vec2<f32>(toMouse.x * ca - toMouse.y * sa, toMouse.x * sa + toMouse.y * ca);

    // Wavelengths for RGB
    let lambdaR = 650.0;
    let lambdaG = 530.0;
    let lambdaB = 460.0;
    let n0 = 1.4;
    let B = 3000.0;

    let iorR = cauchyIOR(lambdaR, n0, B);
    let iorG = cauchyIOR(lambdaG, n0, B);
    let iorB = cauchyIOR(lambdaB, n0, B);

    // Refraction displacement (computed in aspect-corrected space, mapped
    // back to uv space for sampling so the split stays radial).
    let normal = normalize(rotDir + vec2<f32>(0.0001));
    let shimmerR = 1.0 + trebleLo * 0.3;
    let shimmerB = 1.0 + trebleHi * 0.3;
    let dispC_R = normal * (iorR - iorG) * localDispersion * lensFactor * shimmerR;
    let dispC_B = normal * (iorB - iorG) * localDispersion * lensFactor * shimmerB;
    let dispR = dispC_R / aspectVec;
    let dispB = dispC_B / aspectVec;

    let sampleR = textureSampleLevel(readTexture, u_sampler, uv - dispR, 0.0).r;
    let sampleG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let sampleB = textureSampleLevel(readTexture, u_sampler, uv - dispB, 0.0).b;

    var finalColor = vec3<f32>(sampleR, sampleG, sampleB);

    // Add chromatic aberration glow inside lens
    let glow = lensProfile * 0.15 * clickBoost * (1.0 + bass * 0.6);
    finalColor = finalColor + vec3<f32>(glow * 0.8, glow * 0.5, glow * 1.0);

    // Bass rings the lens rim with a caustic flare
    let rim = exp(-pow((mouseDist / max(lensRadius, 0.001)) - 1.0, 2.0) * 30.0) * bass;
    finalColor = finalColor + vec3<f32>(1.0, 0.7, 0.35) * rim * 0.6;

    // Click bursts scatter a brief spectral ring at the burst edge
    finalColor = finalColor + vec3<f32>(0.9, 0.4, 1.0) * spectralRing * 0.5;

    // Alpha represents lens intensity
    let alpha = clamp(mix(1.0, 0.9, lensProfile * 0.3) + rim * 0.3, 0.0, 1.0);

    let outColor = vec4<f32>(finalColor, alpha);
    textureStore(writeTexture, global_id.xy, outColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
