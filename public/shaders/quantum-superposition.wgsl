#include "_prelude.wgsl"
// zoom_params: x=ChaosSpeed, y=ChaosAmount, z=StabilityRadius, w=RGBSplit

// ═══════════════════════════════════════════════════════════════
//  Quantum Superposition
//  Mouse-stabilised glitch field; bass collapses the wavefunction
//  into blocky chaos, mids widen the RGB split.
//  Features: glitch, block-displacement, mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-11-10
//  Ideas: (1) superposed ghost state — glitch blocks show two displaced
//         eigenstates blended by a per-block interference phase;
//         (2) decoherence fringe — interference bands ripple the image
//         along the observation-radius boundary; (3) ACES display.
// ═══════════════════════════════════════════════════════════════

fn hash13(p: vec3<f32>) -> f32 {
    var p3  = fract(p * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn random2(p: vec2<f32>) -> vec2<f32> {
    return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let treble = plasmaBuffer[0].z;

    // ═══ AUDIO REACTIVITY ═══
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let audioReactivity = 1.0 + bass * 0.3;
    var mousePos = u.zoom_config.yz;

    // Parameters
    let chaosSpeed = u.zoom_params.x * 20.0;
    let chaosAmount = u.zoom_params.y; // 0.0 to 1.0
    let stabilityRadius = u.zoom_params.z; // 0.0 to 1.0
    let rgbSplitStr = u.zoom_params.w * 0.05 * (1.0 + mids * 0.5);

    // Calculate stability field (mouse influence)
    let aspect = resolution.x / resolution.y;
    let mouseVec = (uv - mousePos);
    let dist = length(vec2<f32>(mouseVec.x * aspect, mouseVec.y));

    // Smoothstep creates a soft boundary for stability
    // Closer to mouse = 0.0 (stable), Further = 1.0 (unstable)
    let stability = smoothstep(stabilityRadius, stabilityRadius + 0.2, dist);

    // If mouse is offscreen (-1.0), everything is unstable
    let effectiveStability = select(stability, 1.0, mousePos.x < 0.0);

    // Chaos time modulation
    let chaosTime = floor(time * chaosSpeed * audioReactivity);

    // Random offset for glitch
    // We use floor(uv * blocks) to create blocky artifacts
    let blockSize = 20.0 + (1.0 - effectiveStability) * 50.0;
    let blockUV = floor(uv * blockSize) / blockSize;

    // Random value per block per time step
    let rnd = hash13(vec3<f32>(blockUV, chaosTime));

    // Determine if this pixel is glitching
    // It glitches if the random value is less than the chaos amount masked by stability
    // Bass widens the glitch probability — beats collapse more of the frame
    let audioChaos = clamp(chaosAmount * (1.0 + bass * 0.45), 0.0, 1.0);
    let isGlitch = select(0.0, 1.0, rnd < (audioChaos * effectiveStability));

    var finalColor = vec4<f32>(0.0);

    if (isGlitch > 0.5) {
        // Glitch Mode:
        // 1. Color Inversion or Shift
        // 2. Spatial Displacement
        // 3. RGB Split

        let shift = (random2(blockUV + vec2<f32>(chaosTime)) - vec2<f32>(0.5)) * 0.1 * effectiveStability;

        let rUV = clamp(uv + shift + vec2<f32>(rgbSplitStr, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
        let gUV = clamp(uv + shift, vec2<f32>(0.0), vec2<f32>(1.0));
        let bUV = clamp(uv + shift - vec2<f32>(rgbSplitStr, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

        let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

        // Idea 1: superposition — a second eigenstate with an independent
        // shift; the block's phase sets how much of each state is "observed".
        let shift2 = (random2(blockUV.yx + vec2<f32>(chaosTime * 1.37 + 7.0)) - vec2<f32>(0.5)) * 0.1 * effectiveStability;
        let ghost = textureSampleLevel(readTexture, u_sampler, clamp(uv + shift2, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let psi = 0.5 + 0.5 * cos(rnd * 6.2831853 + time * chaosSpeed * 0.15);
        let superposed = mix(vec3<f32>(r, g, b), ghost, psi * 0.5);

        // Occasional color inversion
        if (rnd < 0.2) {
            finalColor = vec4<f32>(vec3<f32>(1.0) - superposed, 1.0);
        } else {
            finalColor = vec4<f32>(superposed, 1.0);
        }

        // Add some noise overlay
        finalColor = finalColor + vec4<f32>((rnd - 0.5) * 0.2);

    } else {
        // Stable Mode (Clean Image)
        // Idea 2: decoherence fringe — near the observation boundary the
        // clean image wobbles with interference bands before it collapses.
        let edge = effectiveStability * (1.0 - effectiveStability) * 4.0;
        let fringe = sin(dist * 180.0 - time * (3.0 + chaosSpeed * 0.2));
        let fUV = clamp(uv + normalize(mouseVec + vec2<f32>(1e-5)) * fringe * edge * (0.003 + rgbSplitStr * 0.15), vec2<f32>(0.0), vec2<f32>(1.0));
        finalColor = textureSampleLevel(readTexture, u_sampler, fUV, 0.0);
        finalColor = vec4<f32>(finalColor.rgb * (1.0 + fringe * edge * 0.08), finalColor.a);
    }

    // Pass-through depth, nudged forward where the field has collapsed
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    // Alpha encodes coherence: glitched (collapsed) pixels are less opaque
    let alpha = clamp(1.0 - isGlitch * (0.25 + bass * 0.3), 0.0, 1.0);
    let outColor = vec4<f32>(finalColor.rgb, alpha);

    
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let screenUV = vec2<f32>(vec2<i32>(global_id.xy)) / vec2<f32>(u.config.z, u.config.w);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((screenUV - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(screenUV - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let rawRGB = max(outColor.rgb + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25), vec3<f32>(0.0));
    // Idea 3: ACES on display RGB.
    let finalRGB = clamp((rawRGB * (2.51 * rawRGB + 0.03)) / (rawRGB * (2.43 * rawRGB + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, outColor.a));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, outColor.a));
}
