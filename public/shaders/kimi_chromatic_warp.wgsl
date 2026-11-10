// ═══════════════════════════════════════════════════════════════════
//  Kimi Chromatic Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-10
//  Ideas: (1) 5-tap spectral dispersion — yellow/cyan intermediate taps
//         between the existing R/G/B offsets; (2) Cauchy caustic fringe —
//         per-channel focus bands where the warp lens slope peaks;
//         (3) ACES on display RGB before the history max.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Kimi Chromatic Warp - RGB channel separation based on mouse distance
// Creates prismatic distortion effects that intensify near the cursor

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let mouse    = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let aspect = resolution.x / max(resolution.y, 0.001);
    var p      = uv;
    p.x       *= aspect;

    var mousePos = mouse;
    mousePos.x  *= aspect;

    let delta = p - mousePos;
    let dist  = length(delta);
    let dir   = delta / max(dist, 0.0001);

    // Parameters — bass widens warp radius, mids boost chromatic spread
    let warpRadius      = u.zoom_params.x * 0.8 + 0.05;
    let warpStrength    = u.zoom_params.y * 0.1 + 0.01;
    let chromaticSpread = u.zoom_params.z * 0.05 * (1.0 + mids * 0.4);
    let rotationSpeed   = u.zoom_params.w * 5.0;

    let falloff = smoothstep(warpRadius * (1.0 + bass * 0.15), 0.0, dist);

    // Rotating prismatic conveyor: a continuous radial/azimuthal transport field.
    let conveyor = sin(dist * 28.0 - time * (4.0 + rotationSpeed * 2.0));
    let angle  = dist * 10.0 - time * rotationSpeed + mouseDown * 2.0 + conveyor * 0.35;
    let rotDir = vec2<f32>(
        dir.x * cos(angle) - dir.y * sin(angle),
        dir.x * sin(angle) + dir.y * cos(angle)
    );

    let uvRotDir = vec2<f32>(rotDir.x / max(aspect, 0.001), rotDir.y);

    var clickShock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let rippleDelta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let front = abs(length(rippleDelta) - age * (0.32 + bass * 0.12));
            clickShock += (1.0 - smoothstep(0.0, 0.025, front)) * (1.0 - age * 0.5);
        }
    }

    let runnerPhase = fract(dist * (12.0 + warpRadius * 8.0) - time * (2.4 + rotationSpeed));
    let radialRunner = 1.0 - smoothstep(0.0, 0.09, abs(runnerPhase - 0.5));
    let shockWarp = clickShock * (0.012 + chromaticSpread * 0.10);
    let rOffset = uvRotDir * (warpStrength + chromaticSpread + shockWarp) * falloff;
    let gOffset = uvRotDir * (warpStrength + shockWarp * 0.5) * falloff;
    let bOffset = uvRotDir * (warpStrength - chromaticSpread - shockWarp) * falloff * 0.5;

    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv - rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv - gOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let origAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

    // Idea 1: spectral dispersion — intermediate yellow/cyan taps fill the gaps
    // between the three channel offsets so wide spreads smear like a prism.
    let yS = textureSampleLevel(readTexture, u_sampler, clamp(uv - (rOffset + gOffset) * 0.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let cS = textureSampleLevel(readTexture, u_sampler, clamp(uv - (gOffset + bOffset) * 0.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    var color = vec3<f32>(r * 0.62 + yS.r * 0.38, g * 0.5 + yS.g * 0.25 + cS.g * 0.25, b * 0.62 + cS.b * 0.38);

    // Idea 2: Cauchy caustic fringe — the lens focuses light where falloff slope
    // peaks; each wavelength focuses at a slightly different radius.
    let cw = 0.035 + chromaticSpread * 0.4;
    let focusR = warpRadius * 0.5;
    let cR = exp(-pow((dist - focusR * (1.0 + chromaticSpread * 2.0)) / cw, 2.0));
    let cG = exp(-pow((dist - focusR) / cw, 2.0));
    let cB = exp(-pow((dist - focusR * (1.0 - chromaticSpread * 2.0)) / cw, 2.0));
    color += vec3<f32>(cR, cG, cB) * warpStrength * 2.5 * (1.0 + treble * 0.3);

    // Prismatic ring glow
    let ringWidth = 0.02;
    let ringDist  = abs(dist - warpRadius * 0.7);
    let ring      = smoothstep(ringWidth, 0.0, ringDist) * falloff;
    let hue       = atan2(delta.y, delta.x) / 6.28318 + 0.5;
    let rainbow   = vec3<f32>(
        sin(hue * 6.28318) * 0.5 + 0.5,
        sin(hue * 6.28318 + 2.094) * 0.5 + 0.5,
        sin(hue * 6.28318 + 4.188) * 0.5 + 0.5
    );
    color = mix(color, rainbow, clamp(ring * 0.3 + radialRunner * falloff * 0.18 + clickShock * 0.22, 0.0, 0.75));

    // Vignette within warp
    let innerVignette = smoothstep(warpRadius * 0.3, warpRadius * 0.8, dist);
    color *= 0.7 + 0.3 * innerVignette;

    // Bass burst on click + treble sparkle
    let burst = mouseDown * exp(-dist * 3.0) * sin(dist * 30.0 - time * 15.0);
    color += vec3<f32>(burst * 0.2 + treble * ring * 0.1);

    // Spatial grain breathes continuously; time never enters the hash.
    let grainSeed = hash(floor(uv * resolution * 0.5));
    let grain = (grainSeed - 0.5) * (0.025 + 0.015 * sin(time * 5.0 + grainSeed * 6.28318));
    color += grain;

    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let historyOffset = vec2<i32>(round(uvRotDir * resolution * (0.006 + warpStrength * 0.04)));
    let history = textureLoad(dataTextureC, clamp(coord - historyOffset, vec2<i32>(0), maxCoord), 0);
    // Idea 3: ACES on display RGB.
    color = clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
    color = max(color, clamp(history.rgb, vec3<f32>(0.0), vec3<f32>(2.5)) * (0.62 + radialRunner * 0.12));

    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: warp zone + ring glow + audio energy + original alpha
    let alpha = clamp(falloff * 0.5 + ring * 0.4 + bass * 0.1 + origAlpha * 0.05, 0.0, 1.0);
    let fc = vec4<f32>(color, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
