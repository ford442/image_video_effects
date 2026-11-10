// ═══════════════════════════════════════════════════════════════════
//  Cyber Grid Pulse
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-10
//  Ideas: half-cell dual lattice dots; traveling X-line packet;
//         pulse-front cell capture (luma-quantised neon blocks);
//         field-line chromatic split inside the magnetic pull
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Cyber Grid Pulse
// A glowing grid that pulses with the music and distorts near the mouse.

fn get_luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let mouseDown = u.zoom_config.w;
    // Rescue: HEAD kept a spring cursor in extraBuffer[133..138], which the
    // host re-uploads (zeroes) every frame, and thread (0,0) wrote it while
    // other threads read it in the same dispatch. Raw cursor, no state.
    let mouse = u.zoom_config.yz;

    // Audio reactivity
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass   = select(0.0, plasmaBuffer[0].x, hasAudio);
    let mids   = select(0.0, plasmaBuffer[0].y, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

    // Parameters — bass drives pulse
    let gridSize = 20.0 + u.zoom_params.x * 50.0;
    let pulseSpeed = (2.0 + u.zoom_params.y * 5.0) * (1.0 + bass * 0.5);
    let distortionStrength = 0.1 + u.zoom_params.z * 0.4;
    let glowIntensity = (0.5 + u.zoom_params.w * 1.5) * (1.0 + mids * 0.3);

    // Distort UV based on mouse
    let aspect = resolution.x / max(resolution.y, 0.001);
    let dVec = uv - mouse;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Magnetic pull distortion — branchless
    let hasMouse = select(0.0, 1.0, mouse.x >= 0.0);
    let pull = smoothstep(0.4, 0.0, dist) * distortionStrength * hasMouse;
    let safeDVec = dVec + vec2<f32>(0.0001);

    // Clicks send magnetic shockwaves through the grid from normalized ripple
    // positions; each wave contributes a bounded radial displacement.
    var clickWarp = vec2<f32>(0.0);
    var clickGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        let safeAge = max(age, 0.0);
        let live = step(0.0, age) * (1.0 - step(1.7, age));
        let rv = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
        let rd = length(rv);
        let ring = 1.0 - smoothstep(0.015, 0.05, abs(rd - safeAge * 0.42));
        let wave = ring * exp(-safeAge * 1.8) * live;
        let radial = select(vec2<f32>(0.0), rv / max(rd, 0.0001), rd > 0.0001);
        clickWarp += vec2<f32>(radial.x / aspect, radial.y) * wave * 0.035 * distortionStrength;
        clickGlow = max(clickGlow, wave);
    }

    let distortedUV = clamp(
        uv - normalize(safeDVec) * pull * (0.5 + 0.5 * sin(time * 5.0)) + clickWarp,
        vec2<f32>(0.0),
        vec2<f32>(1.0)
    );

    let baseColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);
    let luma = get_luminance(baseColor.rgb);

    // Grid Calculation
    let gridUV = distortedUV * gridSize;
    let wave = sin(gridUV.y * 0.5 + time * pulseSpeed) * 0.1;
    let gridLineX = abs(fract(gridUV.x + wave) - 0.5);
    let gridLineY = abs(fract(gridUV.y) - 0.5);

    let thickness = 0.02 + luma * 0.1;
    let gridMask = 1.0 - smoothstep(thickness, thickness + 0.02, min(gridLineX, gridLineY));
    let dualX = abs(fract(gridUV.x + 0.5 + wave) - 0.5);
    let dualY = abs(fract(gridUV.y + 0.5) - 0.5);
    let vertexDot = (1.0 - smoothstep(0.0, 0.08, dualX)) * (1.0 - smoothstep(0.0, 0.08, dualY));
    // Idea: field-line chromatic split — inside the magnetic pull the bent
    // lines are re-evaluated with R/B pushed along the pull direction, so the
    // field visibly fringes the lattice red/blue in proportion to the pull.
    let pullDir = normalize(safeDVec);
    let splitAmt = pull * 0.6;
    let gR = gridUV + pullDir * splitAmt;
    let gB = gridUV - pullDir * splitAmt;
    let lineR = min(abs(fract(gR.x + wave) - 0.5), abs(fract(gR.y) - 0.5));
    let lineB = min(abs(fract(gB.x + wave) - 0.5), abs(fract(gB.y) - 0.5));
    let maskR = 1.0 - smoothstep(thickness, thickness + 0.02, lineR);
    let maskB = 1.0 - smoothstep(thickness, thickness + 0.02, lineB);
    // Only the displaced part of each copy fringes; the line itself stays cyan.
    let fringe = max(vec3<f32>(maskR - gridMask, 0.0, maskB - gridMask), vec3<f32>(0.0)) * smoothstep(0.0, 0.02, pull);

    let packet = exp(-pow((fract(gridUV.x * 0.15 - time * pulseSpeed * 0.12) - 0.5) / 0.08, 2.0)) * (1.0 - smoothstep(0.0, 0.06, gridLineY));

    // Pulse color — treble adds shimmer
    // Rescue: plasmaBuffer[1..8] is never uploaded (only [0] is), so HEAD's
    // per-cell FFT term was dead. Per-cell hash flicker driven by treble.
    let cellId = floor(gridUV);
    let cellHash = fract(sin(dot(cellId, vec2<f32>(127.1, 311.7))) * 43758.5453);
    let cellFlick = step(0.82 - treble * 0.3, fract(cellHash + time * 0.7 * (0.5 + cellHash)));
    let pulse = (0.5 + 0.5 * sin(time * pulseSpeed - dist * 10.0)) * (1.0 + treble * 0.15 + cellFlick * 0.18);

    // Idea: pulse-front cell capture — the radial pulse crest is sampled at
    // each cell centre; cells it passes fill solid with photo luma quantised
    // to 4 neon levels, then release as the crest moves on (Tron capture).
    let cellCentreUV = (cellId + 0.5) / gridSize;
    let cv = cellCentreUV - mouse;
    let cellDist = length(vec2<f32>(cv.x * aspect, cv.y));
    let crest = 0.5 + 0.5 * sin(time * pulseSpeed - cellDist * 10.0);
    let capture = smoothstep(0.88, 0.98, crest) * step(0.35, cellHash + bass * 0.3);
    let cellLuma = get_luminance(textureSampleLevel(readTexture, u_sampler, clamp(cellCentreUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
    let lumaLevel = floor(cellLuma * 4.0 + 0.5) / 4.0;
    let captureColor = vec3<f32>(0.0, 1.0, 0.8) * (0.25 + lumaLevel) * glowIntensity;
    let gridColor = vec3<f32>(0.0, 1.0, 0.8) * pulse * glowIntensity;

    var finalColor = baseColor.rgb;
    let scanline = sin(uv.y * resolution.y * 0.5 + time * 10.0) * 0.1;

    finalColor = mix(finalColor, captureColor + baseColor.rgb * 0.35, capture * 0.85);
    finalColor = mix(finalColor, gridColor + baseColor.rgb * 0.5, gridMask);
    finalColor += fringe * glowIntensity * 0.9;
    finalColor += gridColor * gridMask * pulse;
    finalColor += vec3<f32>(0.9, 1.0, 0.85) * vertexDot * glowIntensity * 0.55;
    finalColor += gridColor * packet * 0.85;
    finalColor += vec3<f32>(scanline);

    // Mouse highlight — branchless
    let highlight = smoothstep(0.2, 0.0, dist) * mouseDown * hasMouse;
    finalColor += vec3<f32>(0.2, 0.4, 1.0) * highlight;
    finalColor += vec3<f32>(0.15, 0.65, 1.0) * clickGlow * (0.35 + glowIntensity * 0.25);

    // Hue-preserving bounded HDR avoids channel clipping on stacked grid lines.
    finalColor = max(finalColor, vec3<f32>(0.0));
    let aa = 2.51; let bb = 0.03; let cc = 2.43; let dd = 0.59; let ee = 0.14;
    finalColor = clamp((finalColor * (aa * finalColor + bb)) / (finalColor * (cc * finalColor + dd) + ee), vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: grid edge presence + audio pulse + base image alpha
    let alpha = clamp(gridMask * 0.6 + capture * 0.3 + clickGlow * 0.2 + luma * 0.2 + bass * 0.15 + baseColor.a * 0.1, 0.0, 1.0);
    let fc = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
