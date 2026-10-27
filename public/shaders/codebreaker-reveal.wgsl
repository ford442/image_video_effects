// ═══════════════════════════════════════════════════════════════════
//  Codebreaker Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17, 2026-10-27
//  Ideas: glyph head and tail; decrypt persistence
//  A packing: ACES display RGB + decrypt mask in A.a (only C.a is read)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Radius, y=Speed, z=Density, w=Glow

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Slider-driven constants (u.zoom_params.x/y/z/w) ─────────────
    // param1 (Reveal Radius) -> base reveal disc size
    // param2 (Rain Speed)    -> matrix rain fall speed
    // param3 (Code Density)  -> rain column count
    // param4 (Glow Intensity)-> blink flash + edge ring brightness
    let baseRadius = max(0.01, u.zoom_params.x * 0.4);
    // Bass radius boost applied AFTER the spring so the punch stays instant.
    // Bass widens the disc immediately.
    let radius  = baseRadius * (1.0 + bass * 0.2);
    let speed   = u.zoom_params.y * 2.0 * (1.0 + mids * 0.3);
    let density = max(10.0, u.zoom_params.z * 150.0);
    let glow    = u.zoom_params.w * 2.0;

    let videoSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let videoColor  = videoSample.rgb;
    let luminance   = dot(videoColor, vec3<f32>(0.299, 0.587, 0.114));

    let aspect  = resolution.x / max(resolution.y, 0.001);
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist    = length(distVec);

    // Cursor reveal disc (center now spring-eased).
    var mask = 1.0 - smoothstep(max(0.0, radius - 0.05), radius, dist);

    // ── Click reveal bursts ─────────────────────────────────────────
    // Each live ripple opens a temporary second reveal disc at its click
    // point (same mask math as the cursor disc), radius growing then
    // collapsing over ~1.5s, combined with the cursor mask via max().
    var burstMask  = 0.0;
    var burstRing  = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 1.5) { continue; }
        let life = age / 1.5;                       // 0..1 over the burst
        // Grow then collapse: sin envelope peaks mid-life.
        let burstRadius = baseRadius * 1.6 * sin(3.14159265 * life);
        let burstDistVec = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
        let burstDist    = length(burstDistVec);
        let burstDisc    = 1.0 - smoothstep(max(0.0, burstRadius - 0.05), burstRadius, burstDist);
        burstMask = max(burstMask, burstDisc);
        // Faint expanding rim so the punched hole feels energetic.
        let rimRadius = age * 0.45;
        let rim = 1.0 - smoothstep(0.0, 0.02, abs(burstDist - rimRadius));
        burstRing = max(burstRing, rim * (1.0 - life));
    }
    mask = max(mask, burstMask);

    // Matrix rain
    let colIndex  = floor(uv.x * density);
    let colRandom = hash12(vec2<f32>(colIndex, 0.0));
    let fallSpeed = (0.5 + 0.5 * colRandom) * speed;
    let yFlow     = uv.y + time * fallSpeed;

    let rowDensity = density * aspect;
    let rowIndex   = floor(yFlow * rowDensity);
    let charRandom = hash12(vec2<f32>(colIndex, rowIndex));
    let cellUV     = fract(vec2<f32>(uv.x * density, yFlow * rowDensity));
    let pixelCode  = step(0.5, hash12(vec2<f32>(colIndex, rowIndex) + floor(cellUV * 3.0)));
    let blink      = step(0.95, fract(time * 5.0 + charRandom * 10.0));

    // Column shimmer from treble. plasmaBuffer[1..] is never uploaded.
    let shimmer = step(0.93, fract(time * (2.0 + treble * 9.0) + charRandom * 7.0 + colRandom)) * treble;

    // ── Idea: head and tail — the leading edge of the cell is white; glyphs behind it dim.
    let cellPhase = fract(yFlow * rowDensity);
    let head = smoothstep(0.22, 0.0, cellPhase);
    let tail = exp(-cellPhase * 3.2);

    var matrixColor = vec3<f32>(0.0, 1.0 + treble * 0.2, 0.4);
    matrixColor = mix(matrixColor, vec3<f32>(1.0), luminance * luminance);

    let codeBrightness = pixelCode * luminance * tail;
    var finalMatrix = matrixColor * codeBrightness * (1.0 + (blink + shimmer) * glow);
    finalMatrix = finalMatrix + vec3<f32>(0.78, 1.0, 0.86) * head * pixelCode * (0.55 + glow * 0.45);

    // ── Idea: decrypt persistence — the hole is stored in A.a and closes with Rain Speed.
    let prevA = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).a;
    let prevMask = select(0.0, prevA, prevA < 1.01);
    let cover = clamp(0.972 - u.zoom_params.y * 0.045, 0.88, 0.985);
    let linger = clamp(max(mask, prevMask * cover), 0.0, 1.0);

    var finalColor = mix(finalMatrix, videoColor, linger);

    // Edge ring glow
    let ring = 1.0 - smoothstep(0.0, 0.02, abs(dist - radius));
    finalColor += vec3<f32>(0.5, 1.0, 0.8) * ring * glow;
    // Click burst rims glow in the same code-green family.
    finalColor = finalColor + vec3<f32>(0.4, 0.9, 0.7) * burstRing * glow * 0.5;
    finalColor = aces(max(finalColor, vec3<f32>(0.0)));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let alpha = clamp((1.0 - linger) * 0.45 + ring * 0.35 + burstRing * 0.2 + head * 0.15 + videoSample.a * 0.1, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, linger));
}
