// ═══════════════════════════════════════════════════════════════════
//  Magnetic Interference - Alpha Translucency Edition
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, ripple-integration, upgraded-rgba
//  Complexity: Medium
//  Transform: Replaced per-channel magnetic pull with unified
//             displacement field. Alpha encodes magnetic field
//             strength * distance falloff. Added ripple shockwave
//             interference and gravity-well mouse attraction.
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    let bass = plasmaBuffer[0].x;

    // ─── Audio envelope with attack/release ───
    var prevEnv = 0.0;
    if (global_id.x == 0u && global_id.y == 0u) {
        prevEnv = textureSampleLevel(dataTextureC, u_sampler, vec2<f32>(0.0), 0.0).r;
    }
    let env = bass_env(prevEnv, bass, 0.8, 0.15);

    let aspect = resolution.x / resolution.y;
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

    let dist = distance(uv_corrected, mouse_corrected);

    let strength = u.zoom_params.x;
    let radius = u.zoom_params.y;
    let aberration = u.zoom_params.z;
    let scanline_intensity = u.zoom_params.w;

    // Mouse X modulates magnetic radius
    let mouseRadiusMod = 1.0 + mousePos.x * 0.3;
    let effectiveRadius = radius * mouseRadiusMod;

    let audioStrength = strength * (1.0 + env * 0.3);
    let audioScanlines = scanline_intensity * (1.0 + env * 0.5);

    // ─── Single magnetic displacement field ───
    let pull = audioStrength * 0.05 / (pow(dist, 2.0) + 0.01);
    let influence = smoothstep(effectiveRadius, 0.0, dist);

    var dir = uv - mousePos;
    let magneticDisp = dir * pull * influence;

    // ─── Ripple system integration for shockwave interference ───
    var rippleDisp = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = distance(uv, rPos);
            let rWave = sin(rDist * 40.0 - rElapsed * 8.0) * exp(-rElapsed * 1.5);
            rippleDisp = rippleDisp + (uv - rPos) * rWave * smoothstep(0.3, 0.0, rDist) * 0.5;
        }
    }

    // ─── Gravity well attracts pixels when mouse is down ───
    let gWell = gravityWell(uv, mousePos, select(0.0, 0.03, isMouseDown));
    let gravityDisp = gWell * influence * 0.02;

    // Unified displacement (NO per-channel splitting)
    let totalDisp = magneticDisp + rippleDisp + gravityDisp;
    let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));

    // Single sample from unified UV
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // ─── Temporal feedback for smearing ───
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let fieldMag = length(totalDisp) * 20.0;
    let feedbackMix = tentAlpha(fieldMag) * 0.1;
    let feedbackColor = mix(baseColor, prevColor, feedbackMix);

    // Spectral tint via mix(), NOT per-channel sampling
    let tint = vec3<f32>(1.0 + aberration * 0.3, 1.0, 1.0 - aberration * 0.3);
    let tintedColor = mix(feedbackColor, feedbackColor * tint, fieldMag * 0.5);

    // Scanlines modulated by field magnitude
    let scanline_uv_y = uv.y + fieldMag * 0.5;
    let scanline = sin(scanline_uv_y * resolution.y * 0.5 + time * 5.0);
    let scanline_mask = 1.0 - (scanline * 0.5 + 0.5) * audioScanlines;
    let color = tintedColor * scanline_mask;

    // ─── Alpha = magnetic field strength * distance falloff ───
    let fieldMagnetic = length(magneticDisp) * 10.0;
    let alpha = clamp(fieldMagnetic * influence + env * 0.2, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coord, vec4<f32>(color, alpha));

    if (coord.x == 0 && coord.y == 0) {
        textureStore(dataTextureA, coord, vec4<f32>(env, 0.0, 0.0, 0.0));
    } else {
        textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
    }
}
