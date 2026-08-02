// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Decay, y=Glow, z=HueShift, w=BrushSize
  ripples: array<vec4<f32>, 50>,
};

// Helper function for HSL to RGB conversion
fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
    var t_clamped = t;
    if (t_clamped < 0.0) { t_clamped = t_clamped + 1.0; }
    if (t_clamped > 1.0) { t_clamped = t_clamped - 1.0; }
    if (t_clamped < 1.0/6.0) { return p + (q - p) * 6.0 * t_clamped; }
    if (t_clamped < 1.0/2.0) { return q; }
    if (t_clamped < 2.0/3.0) { return p + (q - p) * (2.0/3.0 - t_clamped) * 6.0; }
    return p;
}

fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    var r: f32;
    var g: f32;
    var b: f32;

    if (s == 0.0) {
        r = l;
        g = l;
        b = l;
    } else {
        var q: f32;
        if (l < 0.5) {
            q = l * (1.0 + s);
        } else {
            q = l + s - l * s;
        }
        var p = 2.0 * l - q;
        r = hue2rgb(p, q, h + 1.0/3.0);
        g = hue2rgb(p, q, h);
        b = hue2rgb(p, q, h - 1.0/3.0);
    }
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    // Params
    let decaySpeed = u.zoom_params.x; // 0.90 to 0.99
    let glowIntensity = u.zoom_params.y; // 0.5 to 3.0
    let hueShift = u.zoom_params.z; // 0.0 to 1.0
    let brushSize = u.zoom_params.w; // 0.01 to 0.1

    let time = u.config.x;

    // Mouse Interaction
    // Correct for aspect ratio to make brush circular
    let aspect = f32(dims.x) / f32(dims.y);
    let rawMouse = u.zoom_config.yz;

    // Spring-damper brush: the trace ribbons behind the cursor.
    // Persistent state lives in extraBuffer[133..136] (pos.xy, vel.xy),
    // [137] = last integration time, [138] = init flag.
    // [0..4] reserved, [5..132] = engine FFT bins - never touched here.
    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mousePos = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
        mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
        var springPos = mousePos;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            // First frame: snap the spring onto the raw cursor, zero velocity.
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            // Critically-damped spring toward the raw mouse (zeta = 1).
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

    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Brush
    var brush = 0.0;
    // Always active or only when mouse down?
    // u.zoom_config.w is 1.0 if mouse is down.
    // Let's make it always trace but stronger when down.
    let isMouseDown = u.zoom_config.w > 0.5;

    let baseBrush = smoothstep(brushSize, brushSize * 0.5, dist);
    brush = baseBrush * (select(0.5, 1.0, isMouseDown));

    // Click stamp blooms: each live ripple paints a soft round bloom into the
    // history through the same drawColor pipeline, so clicks leave stars
    // without dragging. Radius ~ brushSize * 1.5, decaying over ~1.5s of age.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 1.5) {
            continue;
        }
        let stampDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
        let stampRadius = brushSize * 1.5;
        let stampFade = 1.0 - clamp(age / 1.5, 0.0, 1.0);
        brush += smoothstep(stampRadius, stampRadius * 0.5, stampDist) * stampFade;
    }

    // Audio bands (engine truth: plasmaBuffer[0].xyz = bass/mids/treble,
    // plasmaBuffer[1..8] = 8 FFT band energies for per-band shimmer).
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // History (Read from C, Write to A)
    let historyColor = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Calculate new color to add
    // Mids drive the hue cycle speed: the trace hue spins faster on vocals.
    let colorTick = time * 0.2 * (1.0 + mids * 0.8) + hueShift;
    let drawColor = hslToRgb(fract(colorTick), 1.0, 0.5);

    // Add brush to history
    // SACRED history contract: A is written RAW - decayed history plus the
    // raw draw color, clamped to 2.0. Never tonemap this write; all audio
    // glow modulation happens at the composite stage only.
    let newHistory = clamp(historyColor.rgb * decaySpeed + drawColor * brush, vec3<f32>(0.0), vec3<f32>(2.0));

    // Write State
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newHistory, 1.0));

    // Composition
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Composite-only audio modulation: bass pulses the glow, and each of the
    // 8 vertical screen bands shimmers with its own FFT band energy.
    // History stays raw - this never feeds back into dataTextureA.
    let band = min(u32(uv.x * 8.0), 7u);
    let bandShimmer = plasmaBuffer[(band % 8u) + 1u].x * 0.3;
    let audioGlow = glowIntensity * (1.0 + bass * 0.5) * (1.0 + bandShimmer);

    // Mix input with glowing trail
    // Additive blending for the glow
    let rawComposite = inputColor + newHistory * audioGlow;
    let peak = max(max(rawComposite.r, rawComposite.g), rawComposite.b);
    let excess = max(peak - 1.0, 0.0);
    let mappedPeak = select(peak, 1.0 + excess / (1.0 + excess * 0.5), peak > 1.0);
    let finalColor = rawComposite * (mappedPeak / max(peak, 1e-4));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
