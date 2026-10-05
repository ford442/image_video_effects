// ═══════════════════════════════════════════════════════════════════
//  X-Ray Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, click-reactive, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: Beer-Lambert density / bone window; collimator blades with penumbra + crosshair; dose-dependent quantum mottle
//  A packing: ACES display RGBA (C not read; A mirrors writeTexture)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    // Raw pointer: the old extraBuffer[133..138] spring was re-zeroed by the CPU every frame,
    // so it only ever snapped to the mouse (or raced thread (0,0)).
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

    // Audio: bass widens the lens, mids boosts edges, treble raises contrast
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let lensRadius = u.zoom_params.x * 0.5 * (1.0 + bass * 0.3); // 0.0 to 0.5
    let edgeStrength = u.zoom_params.y * 5.0 * (1.0 + mids * 0.6);
    let contrast = u.zoom_params.z + 0.5 + treble * 0.3; // 0.5 to 1.5
    let blur = max(u.zoom_params.w, 0.001);

    // Distance to the lens centre, aspect-corrected so the lens is circular
    let rel = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(rel);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // X-Ray: invert + cyan tint
    var xray = max(vec3<f32>(1.0) - baseColor, vec3<f32>(0.0));
    xray = xray * mix(vec3<f32>(0.2, 0.8, 1.0), vec3<f32>(0.45, 0.95, 1.0), depth * 0.35);

    // Idea 1: density attenuation / bone window — Beer-Lambert: plate brightness = 1 - exp(-mu * t),
    // thickness t from inverted luma plus nearer depth. Soft tissue goes translucent, dense
    // structures saturate toward bone-white instead of reading as a flat negative.
    let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));
    let density = clamp((1.0 - luma) * 0.75 + depth * 0.35, 0.0, 1.2);
    let plate = 1.0 - exp(-density * 2.2);
    let bone = smoothstep(0.62, 0.88, plate);
    xray = xray * (0.55 + 0.75 * plate);
    xray = mix(xray, vec3<f32>(0.88, 0.97, 1.0) * plate, bone * 0.7);

    // Edge detection (Sobel-ish, clamped taps)
    let offset = 1.0 / resolution;
    let left = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let right = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    let gx = length(right - left);
    let gy = length(down - up);
    let edges = sqrt(gx * gx + gy * gy);
    // 0.8 = HEAD's factor with its dead plasmaBuffer[1..8] "FFT edge" reads at zero.
    xray += vec3<f32>(edges * edgeStrength * 0.8);

    // Apply contrast
    xray = pow(max(xray, vec3<f32>(0.0)), vec3<f32>(max(contrast, 0.05)));

    // Idea 3: quantum mottle — mono plate noise with amplitude ~ 1/sqrt(dose), where dose is the
    // fraction of photons reaching the plate (1 - plate brightness): bright attenuated regions mottle,
    // open-beam dark regions stay clean. Re-seeded at 24 Hz like a fluoroscopy feed.
    let dose = clamp(1.0 - dot(xray, vec3<f32>(0.299, 0.587, 0.114)), 0.04, 1.0);
    let mottleAmp = min(0.02 * inverseSqrt(dose), 0.07);
    // Wrapped so the hash input stays small: unwrapped, frameSeed * 17.13 passes 1e6 after ~40 min
    // and f32 precision turns the per-pixel mottle into blocky / striped patterns.
    let frameSeed = floor(time * 24.0) % 4096.0;
    let px = vec2<f32>(global_id.xy);
    let n = hash12(px + frameSeed * 17.13) + hash12(px * 1.37 + frameSeed * 5.71 + 41.0) - 1.0;
    xray = max(xray + vec3<f32>(n * mottleAmp), vec3<f32>(0.0));

    // Idea 2: collimator blades — four lead blades at 0.88 r clip the round field to circle ∩ square,
    // with a penumbra as wide as Lens Edge Softness; field SDF drives mask and rim alike.
    let bladeDist = max(abs(rel.x), abs(rel.y)) - lensRadius * 0.88;
    let fieldSdf = max(dist - lensRadius, bladeDist);
    let lensMask = 1.0 - smoothstep(0.0, blur, fieldSdf);

    var clickMask = 0.0;
    var clickRing = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let radius = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            let waveRadius = age * 0.20;
            let ringPulse = exp(-abs(radius - waveRadius) * 75.0) * exp(-age * 1.4);
            clickRing = max(clickRing, ringPulse);
            clickMask = max(clickMask, (1.0 - smoothstep(0.0, max(waveRadius, 0.015), radius)) * exp(-age * 0.8));
        }
    }
    let mask = clamp(max(lensMask, clickMask * 0.8), 0.0, 1.0);

    // Composite: x-ray inside the field, dimmed photo outside
    let dimmedBase = baseColor * 0.8;
    var finalColor = mix(dimmedBase, xray, mask);

    // Idea 2 (cont.): light-field crosshair centring the collimated field
    let crossLine = 1.0 - smoothstep(0.0, 0.0018, min(abs(rel.x), abs(rel.y)));
    let crossGap = smoothstep(0.01, 0.025, dist);
    finalColor += vec3<f32>(0.6, 0.95, 1.0) * crossLine * crossGap * lensMask * 0.22;

    let d = abs(fieldSdf);
    let ringMag = (1.0 - smoothstep(0.0, 0.005, d)) + clickRing;
    let ringColor = vec3<f32>(0.5, 0.9, 1.0) * ringMag;

    // ACES on display (0.75 exposure keeps HEAD's soft-ceiling brightness and the dimmed surround)
    let result = aces(max(finalColor + ringColor, vec3<f32>(0.0)) * 0.75);

    // Reveal-mask alpha: field interior and ring opaque, dimmed surround recedes
    let alpha = clamp(mask * 0.7 + ringMag + dot(result, vec3<f32>(0.299, 0.587, 0.114)) * 0.3 + 0.1, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(result, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(result, alpha));

    let reliefDepth = clamp(depth + mask * min(edges * 0.08, 0.12) + min(ringMag * 0.04, 0.08), 0.0, 1.0);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(reliefDepth, 0.0, 0.0, 0.0));
}
