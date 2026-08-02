// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Mirage
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-30
//  Upgraded: 2026-08-02 (Batch 29)
// ═══════════════════════════════════════════════════════════════════
//  Vertical heat shimmer driven by a rising hot-air column. A
//  time-varying noise field is advected upward, displacing the UV
//  sample. Temporal feedback (dataTextureC) stores the accumulated
//  heat state and slowly cools. Bass (plasmaBuffer[0].x) injects
//  fresh heat bursts; the mouse is a spring-damped heat source and
//  clicks pop decaying heat blooms via the ripple queue.
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
  config: vec4<f32>,      // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=HeatIntensity, y=RiseSpeed, z=WavyScale, w=ChromaShift
  ripples: array<vec4<f32>, 50>,
};

// extraBuffer layout (this shader): [0..4] reserved, [5..132] engine FFT,
// [133..136] = heat-source spring state (pos.xy, vel.xy), [137] = init flag.

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),                       hash(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    ) * 2.0 - 1.0;
}

fn fbm2(p: vec2<f32>) -> vec2<f32> {
    let n1 = vnoise(p);
    let n2 = vnoise(p + vec2<f32>(5.2, 1.3));
    return vec2<f32>(n1, n2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv     = vec2<f32>(gid.xy) / dims;
    let coord  = vec2<i32>(gid.xy);
    let time   = u.config.x;
    let aspect = dims.x / dims.y;

    // Audio: real FFT bands live in plasmaBuffer[0] (x=bass, y=mid, z=treble)
    let bass   = plasmaBuffer[0].x;
    let mid    = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let heatIntensity = mix(0.0, 0.025, u.zoom_params.x) * (1.0 + bass * 2.0);
    let riseSpeed     = mix(0.1, 1.5,   u.zoom_params.y);
    let wavyScale     = mix(2.0, 12.0,  u.zoom_params.z);
    let chromaShift   = mix(0.0, 0.008, u.zoom_params.w) * (1.0 + treble * 0.5);

    // ── Spring-damped heat source (persistent state in extraBuffer) ──
    // Critically-damped spring toward the raw mouse: the hot spot lags
    // and drifts like a real thermal instead of snapping to the cursor.
    let dt       = 1.0 / 60.0;
    let omega    = 3.0;
    let rawMouse = u.zoom_config.yz;
    var heatPos  = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var heatVel  = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let springInitialized = extraBuffer[137] > 0.5;
    if (!springInitialized) { // cold start: begin at the cursor, including (0,0)
        heatPos = rawMouse;
        heatVel = vec2<f32>(0.0, 0.0);
    }
    let springAcc = (rawMouse - heatPos) * (omega * omega) - heatVel * (2.0 * omega);
    heatVel += springAcc * dt;
    heatPos += heatVel * dt;
    if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[133] = heatPos.x;
        extraBuffer[134] = heatPos.y;
        extraBuffer[135] = heatVel.x;
        extraBuffer[136] = heatVel.y;
        extraBuffer[137] = 1.0;
    }

    // Thermal sway: a whisper of advected noise makes the hot spot
    // wander like a real pocket of hot air instead of a pinned disc.
    let sway      = fbm2(vec2<f32>(time * 0.7, time * 0.53)) * 0.015;

    // Heat column: stronger at bottom of screen (y~0), rises upward
    let heatBase  = smoothstep(1.0, 0.0, uv.y) * 0.5 + 0.5; // more heat at bottom
    // Also mouse can be a heat source (aspect-corrected: circular column)
    let mDist     = length((uv - (heatPos + sway)) * vec2<f32>(aspect, 1.0));
    let mouseHeat = smoothstep(0.25, 0.0, mDist) * u.zoom_config.w;

    var heatFactor = heatBase + mouseHeat;

    // ── Click heat bursts ─────────────────────────────────────────
    // Each live ripple pops a mirage at its click point: a decaying
    // heat bloom (~2s life, exp falloff), no mouseDown required. The
    // bloom distance is aspect-corrected so bursts stay circular.
    var clickHeat = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp  = u.ripples[i];          // xy = click pos, z = click time
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            clickHeat = max(clickHeat, exp(-age * 1.5) * smoothstep(0.2, 0.0, rDist));
        }
    }
    heatFactor = min(heatFactor + clickHeat, 2.5);

    // ── Per-band FFT shimmer ──────────────────────────────────────
    // The screen is sliced into 8 vertical bands; each band's FFT bin
    // (plasmaBuffer[1..8]) locally boosts the shimmer amplitude, so the
    // haze dances differently from the floor to the top of the frame.
    let band      = u32(clamp(uv.y * 8.0, 0.0, 7.999));
    let bandBoost = plasmaBuffer[(band % 8u) + 1u].x * 0.3;

    // Rising displacement field
    let risingUV  = vec2<f32>(uv.x * wavyScale, uv.y * wavyScale - time * riseSpeed);
    let disp      = fbm2(risingUV) * heatIntensity * heatFactor * (1.0 + bandBoost);

    // Vertical bias: haze mostly shifts horizontally (shimmer), slight vertical
    let heatDisp  = vec2<f32>(disp.x, disp.y * 0.3);

    // Chromatic shift: red slightly ahead, blue slightly behind (mirage)
    let rUV = clamp(uv + heatDisp + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + heatDisp,                                vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + heatDisp - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let a = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    // Atmospheric haze: slight brightness boost + warm tint at heat zones
    let warmTint   = vec3<f32>(1.04, 1.01, 0.97) * (1.0 + heatFactor * 0.1);
    var col        = vec3<f32>(r, g, b) * warmTint;

    // Heat shimmer glow (subtle)
    let glowMask   = heatFactor * heatIntensity * 50.0;
    col += vec3<f32>(0.05, 0.03, 0.01) * glowMask * (1.0 + mid);

    // Temporal accumulate haze state (A write / C read contract)
    let prev     = textureLoad(dataTextureC, coord, 0);
    let hazeAcc  = mix(vec4<f32>(col, a), prev, 0.85);

    let outColor = vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.3)), a);
    textureStore(writeTexture, coord, outColor);
    let reliefDepth = clamp(heatFactor * 0.5, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(reliefDepth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, hazeAcc);
    textureStore(dataTextureB, coord, vec4<f32>(heatDisp, heatFactor, bass));
}
