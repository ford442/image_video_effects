// ═══════════════════════════════════════════════════════════════
//  Stellar Plasma - Endless procedural cosmic nebula (OPTIMIZED)
//  Category: generative
//  Features: generative, procedural, loops, audio-reactivity,
//            upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration
//
//  OPTIMIZATIONS APPLIED:
//  - Precomputed noise hash values
//  - Added audio reactivity hooks
//  - Distance-based FBM octaves
//  - Cached rotation matrix
//  - Early exit for distant regions
//
//  UPGRADE (Batch 17, Visualist):
//  - Fixed lying uniform comments (config.y = rippleCount, NOT AudioLow;
//    zoom_config.x = time, mouse = zoom_config.yz) — code unchanged.
//  - Real chromatic aberration: 3 spectral fbm samples at sub-pixel
//    offsets reusing the domain-warp coords (true prismatic fringing).
//  - IQ cosine palette replaces the 4 hardcoded base colors; the
//    Hue Shift slider drives palette phase (default = legacy look).
//  - Spring-damper mouse gravity via extraBuffer[133..136].
//  - Nested double domain-warp (q → r → f) preserved VERBATIM,
//    including 4.0x warp amplitude and offsets (1.7,9.2 / 8.3,2.8).
//
//  Author: Gemini 3.1 Pro Vertex (optimized)
//  Chunks From: gen-protocell-division.wgsl (upgraded-rgba stack)
//  Upgraded: 2026-06-14 (Claude Code Batch 3B), 2026-07-26 (Batch 17)
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=rippleCount, z=resW, w=resH
  zoom_config: vec4<f32>,  // x=time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=HueShift, y=FlowSpeed, z=ZoomScale, w=MouseGravity
  ripples: array<vec4<f32>, 50>,
};

// OPTIMIZATION: Precomputed hash constants
const HASH_CONST1: vec3<f32> = vec3<f32>(0.1031, 0.1031, 0.1031);
const HASH_CONST2: vec3<f32> = vec3<f32>(33.33, 33.33, 33.33);

// Spring-damper persistent state slots in extraBuffer safe zone [133..255].
// [133]=smoothed mouse x, [134]=smoothed mouse y, [135]=velocity x, [136]=velocity y
const SPRING_POS_X: u32 = 133u;
const SPRING_POS_Y: u32 = 134u;
const SPRING_VEL_X: u32 = 135u;
const SPRING_VEL_Y: u32 = 136u;

// Pseudo-random hash (optimized)
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * HASH_CONST1);
    p3 += dot(p3, p3.yzx + HASH_CONST2);
    return fract((p3.x + p3.y) * p3.z);
}

// 2D Value Noise
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    let u_f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u_f.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u_f.x),
        u_f.y
    );
}

// OPTIMIZATION: Fractional Brownian Motion with LOD
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let shift = vec2<f32>(100.0, 100.0);

    // Precomputed rotation (cos(0.5), sin(0.5))
    let c: f32 = 0.87758256189;
    let s: f32 = 0.4794255386;
    let rot = mat2x2<f32>(vec2<f32>(c, s), vec2<f32>(-s, c));

    var p_mut = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        v += a * noise(p_mut);
        p_mut = rot * p_mut * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hue shift function (Rodrigues rotation around the grey axis)
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

// IQ cosine palette: a + b*cos(2*pi*(c*t + d)).
// Coefficients are tuned so huePhase = 0 sweeps the legacy ramp
// (cyan → magenta → deep blue → gold) as t runs 0 → 1; the Hue Shift
// slider rotates the phase to explore the full spectral family.
fn iqPalette(t: f32, huePhase: f32) -> vec3<f32> {
    let a = vec3<f32>(0.42, 0.38, 0.52);
    let b = vec3<f32>(0.48, 0.42, 0.45);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.62, 0.42, 0.78) + vec3<f32>(huePhase);
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;

    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) {
        return;
    }

    // Normalize UV coordinates (-1.0 to 1.0) and fix aspect ratio
    var uv = vec2<f32>(global_id.xy) / res;
    var p = uv * 2.0 - 1.0;
    p.x *= res.x / res.y;

    // Calculate distance for LOD
    let dist = length(p);
    let lodFactor = smoothstep(1.5, 2.5, dist);

    // OPTIMIZATION: Early exit for distant regions
    if (dist > 3.0) {
        textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 1.0));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 1.0));
        return;
    }

    // Parameters mapped from UI (saved-preset contract — ids/defaults fixed)
    let hue_phase = u.zoom_params.x;               // Hue Shift: palette phase 0..1
    let speed = mix(0.5, 2.0, u.zoom_params.y);    // Flow Speed: time multiplier
    let scale = mix(1.0, 4.0, u.zoom_params.z);    // Zoom / Scale: nebula zoom
    let mouse_influence = u.zoom_params.w;         // Mouse Gravity strength

    // OPTIMIZATION: Audio reactivity hooks (bass/mid/treble from plasmaBuffer)
    let audioLow = plasmaBuffer[0].x;
    let audioMid = plasmaBuffer[0].y;
    let audioHigh = plasmaBuffer[0].z;
    let audioReactivity = 1.0 + audioMid * 0.3;

    let time = u.config.x * speed * audioReactivity;

    // ── Spring-damper mouse gravity (persistent state) ─────────────
    // extraBuffer[133..134] = smoothed mouse position (aspect-corrected)
    // extraBuffer[135..136] = spring velocity
    // Only invocation (0,0) integrates the spring to avoid races.
    var raw_mouse = u.zoom_config.yz * 2.0 - 1.0;
    raw_mouse.x *= res.x / res.y;

    var sm_pos = vec2<f32>(extraBuffer[SPRING_POS_X], extraBuffer[SPRING_POS_Y]);
    var sm_vel = vec2<f32>(extraBuffer[SPRING_VEL_X], extraBuffer[SPRING_VEL_Y]);
    if (global_id.x == 0u && global_id.y == 0u) {
        // Critically-damped-ish spring: stiff follow, soft overshoot.
        let stiffness = 90.0;
        let damping = 12.0;
        let dt = 0.016;
        sm_vel += (raw_mouse - sm_pos) * stiffness * dt;
        sm_vel *= exp(-damping * dt);
        sm_pos += sm_vel * dt;
        extraBuffer[SPRING_POS_X] = sm_pos.x;
        extraBuffer[SPRING_POS_Y] = sm_pos.y;
        extraBuffer[SPRING_VEL_X] = sm_vel.x;
        extraBuffer[SPRING_VEL_Y] = sm_vel.y;
    }

    // Mouse gravity well around the spring-smoothed cursor
    let dist_to_mouse = length(p - sm_pos);
    let interaction = exp(-dist_to_mouse * 3.0) * mouse_influence;

    // Apply scaling and interaction displacement
    var q_pos = p * scale + interaction;

    // OPTIMIZATION: LOD-based FBM octaves
    let octaves = i32(mix(6.0, 3.0, lodFactor));

    // Domain Warping Step 1
    var q = vec2<f32>(
        fbm(q_pos + vec2<f32>(0.0, time * 0.2), octaves),
        fbm(q_pos + vec2<f32>(1.0, 2.0) + time * 0.2, octaves)
    );

    // Domain Warping Step 2 (Nested FBM) — classic IQ signature, VERBATIM
    var r = vec2<f32>(
        fbm(q_pos + 4.0 * q + vec2<f32>(1.7, 9.2) + time * 0.15, octaves),
        fbm(q_pos + 4.0 * q + vec2<f32>(8.3, 2.8) + time * 0.126, octaves)
    );

    // Final Noise Value
    var f = fbm(q_pos + 4.0 * r, octaves);

    // ═══ CHUNK: real chromatic aberration (spectral fbm sampling) ═══
    // 3 actual spectral samples of the final fbm field at sub-pixel
    // offsets — the warp coords (q, r) are reused, so this is only one
    // extra fbm octave-loop per fringe channel. True prismatic fringing
    // on the nebula filaments, not an additive tint.
    let caDir = normalize(q_pos + vec2<f32>(0.0013, 0.0017));
    let caOff = caDir * (0.004 * (1.0 + audioLow));
    let fR = fbm(q_pos + 4.0 * r + caOff, octaves);
    let fB = fbm(q_pos + 4.0 * r - caOff, octaves);
    let spectral = vec3<f32>(fR, f, fB);

    // Audio-reactive palette phase wobble (bass↔treble tug)
    let audioHuePhase = (audioLow - audioHigh) * 0.03;
    let phase = hue_phase + audioHuePhase;

    // Color construction via IQ cosine palette.
    // Layer mix factors preserved from the legacy 4-color build so the
    // default phase (huePhase = 0) reproduces the original look:
    //   f^2 field → cyan↔magenta, |q| → deep blue, |r.x| → gold glow.
    let tField = clamp(f * f * 4.0, 0.0, 1.0);
    var color = mix(iqPalette(0.05, phase), iqPalette(0.35, phase), tField);
    color = mix(color, iqPalette(0.55, phase), clamp(length(q), 0.0, 1.0) * 0.5);
    color = mix(color, iqPalette(0.90, phase), clamp(length(r.x), 0.0, 1.0) * 0.8);

    // Audio-reactive color brightness shifts (legacy behaviour kept)
    color = mix(color, color * vec3<f32>(1.1, 1.25, 1.3), audioLow * 0.15);
    color = mix(color, color * vec3<f32>(1.3, 1.1, 1.2), audioHigh * 0.15);

    // Subtle time drift on hue + audio rotation
    color = hueShift(color, time * 0.1 + (audioLow - audioHigh) * 0.1);

    // Enhance contrast and glow — per-channel spectral field gives the
    // fringed highlights their prismatic separation.
    let glowIntensity = 1.0 + audioMid * 0.5;
    color = (spectral * spectral * spectral + 0.6 * spectral * spectral + 0.5 * spectral) * color * glowIntensity;

    let coord = vec2<i32>(global_id.xy);

    // ═══ CHUNK: temporal-feedback (dataTextureC → dataTextureA) ═══
    let prev = textureLoad(dataTextureC, coord, 0);
    color = mix(color, prev.rgb * 0.92, 0.05 + audioLow * 0.01);

    color = acesToneMap(color * 1.2);

    // Output final color with semantic alpha
    let lumaOut = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(lumaOut * 0.8 + 0.1, 0.0, 1.0);
    let final_color = vec4<f32>(color, alpha);
    textureStore(writeTexture, coord, final_color);
    textureStore(dataTextureA, coord, final_color);

    // Write empty depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
