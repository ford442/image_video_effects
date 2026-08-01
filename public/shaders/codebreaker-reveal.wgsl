// ═══════════════════════════════════════════════════════════════════
//  Codebreaker Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
//  Swarm upgrade: 2026-07-31 (Batch 19, Interactivist)
//    - Spring-damper reveal center (extraBuffer[133..136])
//    - Click reveal bursts from ripples[] (max-combined with cursor disc)
//    - Per-column treble shimmer via plasmaBuffer FFT bins
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=Speed, z=Density, w=Glow
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let rawMouse = u.zoom_config.yz;
    let time = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Spring-damper reveal center ─────────────────────────────────
    // Persistent eased center + velocity live in extraBuffer[133..136]
    // ([0..4] engine-reserved, [5..132] engine FFT bins). The raw mouse
    // stays the spring TARGET; the reveal circle sweeps after the cursor
    // with momentum instead of snapping to it.
    var springCenter = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var springVel    = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if ((springCenter.x == 0.0 && springCenter.y == 0.0) && time < 2.0) {
        springCenter = rawMouse;            // first frames: snap, no fly-in
        springVel    = vec2<f32>(0.0, 0.0);
    }
    // Critically-damped spring, fixed-step semi-implicit Euler.
    let springDt    = 1.0 / 60.0;
    let springOmega = 9.0;                  // response speed of the chase
    let springAccel = (rawMouse - springCenter) * springOmega * springOmega
                    - springVel * 2.0 * springOmega;
    springVel    = springVel + springAccel * springDt;
    springCenter = springCenter + springVel * springDt;
    extraBuffer[133] = springCenter.x;
    extraBuffer[134] = springCenter.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    let mousePos = springCenter;

    // ── Slider-driven constants (u.zoom_params.x/y/z/w) ─────────────
    // param1 (Reveal Radius) -> base reveal disc size
    // param2 (Rain Speed)    -> matrix rain fall speed
    // param3 (Code Density)  -> rain column count
    // param4 (Glow Intensity)-> blink flash + edge ring brightness
    let baseRadius = max(0.01, u.zoom_params.x * 0.4);
    // Bass radius boost applied AFTER the spring so the punch stays instant.
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

    // ── Per-column treble shimmer ───────────────────────────────────
    // Each rain column glitters at a rate set by its own FFT bin instead
    // of blinking uniformly (colIndex is f32 -> cast via u32).
    let colBin  = plasmaBuffer[(u32(colIndex) % 8u) + 1u].x;
    let shimmer = step(0.93, fract(time * (2.0 + colBin * 9.0) + charRandom * 7.0)) * colBin;

    // Treble brightens the top of matrix characters
    var matrixColor = vec3<f32>(0.0, 1.0 + treble * 0.2, 0.4);
    matrixColor = mix(matrixColor, vec3<f32>(1.0), luminance * luminance);

    let codeBrightness = pixelCode * luminance;
    let finalMatrix    = matrixColor * codeBrightness * (1.0 + (blink + shimmer) * glow);

    var finalColor = mix(finalMatrix, videoColor, mask);

    // Edge ring glow
    let ring = 1.0 - smoothstep(0.0, 0.02, abs(dist - radius));
    finalColor += vec3<f32>(0.5, 1.0, 0.8) * ring * glow;
    // Click burst rims glow in the same code-green family.
    finalColor += vec3<f32>(0.4, 0.9, 0.7) * burstRing * glow * 0.5;
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: reveal mask blend + ring glow + click bursts + bass
    let alpha = clamp((1.0 - mask) * 0.5 + ring * 0.4 + burstRing * 0.2 + bass * 0.1 + videoSample.a * 0.1, 0.0, 1.0);
    let fc = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
