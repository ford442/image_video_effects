// ═══════════════════════════════════════════════════════════════════
//  Magnetic Interference - Interactivist Upgrade
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, ripple-integration,
//            depth-aware, chromatic-aberration, aces-tone-map,
//            temporal-feedback, velocity-trails
//  Complexity: Medium
//  Upgraded: 2026-06-14
//  Transform: Added depth-aware compositing, ACES tone mapping,
//             chromatic aberration, and mouse-velocity trail drag.
//             Switched feedback reads to pixel-exact textureLoad.
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ═══ Audio envelope (smooth attack/release) ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// ═══ Gravity well (mouse attraction) ═══
fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.01;
    return normalize(d) * strength / dist2;
}

// ═══ Tent alpha curve ═══
fn tentAlpha(x: f32) -> f32 {
    return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

// ═══ ACES tone mapping ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ Chromatic shift for generative / displaced output ═══
fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;

    // ─── Audio envelope read from feedback pixel (0,0) ───
    let prevEnv = textureLoad(dataTextureC, vec2<i32>(0), 0).r;
    let env = bass_env(prevEnv, bass, 0.8, 0.15);

    // ─── Mouse velocity from persistent storage ───
    let prevMouse = vec2<f32>(extraBuffer[0], extraBuffer[1]);
    let mouseVel = select(mouse - prevMouse, vec2<f32>(0.0), length(prevMouse) < 0.001);
    let mouseSpeed = length(mouseVel);

    let strength = u.zoom_params.x;
    let radius = u.zoom_params.y;
    let aberration = u.zoom_params.z;
    let scanline_intensity = u.zoom_params.w;

    let aspect = res.x / res.y;
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uv_corrected, mouse_corrected);

    // Mouse X modulates radius; speed stretches it
    let effectiveRadius = radius * (1.0 + mouse.x * 0.3 + mouseSpeed * 5.0);
    let audioStrength = strength * (1.0 + env * 0.3 + mids * 0.2);
    let audioScanlines = scanline_intensity * (1.0 + env * 0.5);

    // ─── Single magnetic displacement field ───
    let pull = audioStrength * 0.05 / (dist * dist + 0.01);
    let influence = smoothstep(effectiveRadius, 0.0, dist);
    let dir = uv - mouse;
    let magneticDisp = dir * pull * influence;

    // ─── Ripple system integration for shockwave interference ───
    var rippleDisp = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rElapsed = time - ripple.z;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = distance(uv, ripple.xy);
            let rWave = sin(rDist * 40.0 - rElapsed * 8.0) * exp(-rElapsed * 1.5);
            rippleDisp += (uv - ripple.xy) * rWave * smoothstep(0.3, 0.0, rDist) * 0.5;
        }
    }

    // ─── Gravity well + velocity trail drag ───
    let gStrength = select(0.0, 0.03 + treble * 0.02, isMouseDown);
    let gWell = gravityWell(uv, mouse, gStrength);
    let gravityDisp = gWell * influence * 0.02;
    let velDisp = mouseVel * influence * (0.1 + env * 0.1);

    let totalDisp = magneticDisp + rippleDisp + gravityDisp + velDisp;
    let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));

    // ─── Sample video input at displaced UV ───
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // ─── Temporal feedback for smearing ───
    let prevColor = textureLoad(dataTextureC, pixel, 0).rgb;
    let fieldMag = length(totalDisp) * 20.0;
    let feedbackMix = tentAlpha(fieldMag) * (0.1 + mouseSpeed * 2.0);
    let feedbackColor = mix(baseColor, prevColor, feedbackMix);

    // Spectral tint via mix, not per-channel sampling
    let tint = vec3<f32>(1.0 + aberration * 0.3, 1.0, 1.0 - aberration * 0.3);
    let tintedColor = mix(feedbackColor, feedbackColor * tint, fieldMag * 0.5);

    // Scanlines modulated by field magnitude
    let scanline = sin((uv.y + fieldMag * 0.5) * res.y * 0.5 + time * 5.0);
    let scanline_mask = 1.0 - (scanline * 0.5 + 0.5) * audioScanlines;
    var color = tintedColor * scanline_mask;

    // ─── Chromatic aberration + ACES tone map ───
    let caStr = 0.003 * (1.0 + env) + depth * 0.001;
    color = genChromaticShift(color, uv, caStr * aberration, time);
    color = acesToneMap(color * (0.9 + mids * 0.2));

    // ─── Depth-aware compositing (stronger in background) ───
    let fog = 1.0 - exp(-depth * 1.5);
    color = mix(baseColor, color, fog * 0.5 + 0.5);

    // ─── Semantic alpha = field intensity * distance falloff * depth ───
    let fieldMagnetic = length(magneticDisp) * 10.0;
    let alpha = clamp(fieldMagnetic * influence + env * 0.2 + depth * 0.15, 0.0, 1.0);

    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));

    if (pixel.x == 0 && pixel.y == 0) {
        textureStore(dataTextureA, pixel, vec4<f32>(env, 0.0, 0.0, 0.0));
        extraBuffer[0] = mouse.x;
        extraBuffer[1] = mouse.y;
    } else {
        textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    }
}
