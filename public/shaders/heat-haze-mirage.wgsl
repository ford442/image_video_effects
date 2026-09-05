// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Mirage — Batch 60
//  Category: image
//  Inferior mirage from a refractive-index gradient: ray curvature
//  follows dn/dy through the hot layer; past critical gradient a
//  vertically mirrored sample folds in (false water / doubled horizon).
//  Depth preserves scene geometry (no heat-column clobber). ACES +
//  semantic alpha. Spring heat source in extraBuffer[133..137].
//
//  A packing: dataTextureA stores temporal haze accumulation RGBA
//  (col.rgb + source a), resurfaced via dataTextureC next frame.
//  B writes diagnostics (heatDisp.xy, heatFactor, bass). Heat spring
//  owns [133..137] from pixel (0,0) only. Depth = scene + mirage relief.
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

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
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
    let dt       = 1.0 / 60.0;
    let omega    = 3.0;
    let rawMouse = u.zoom_config.yz;
    let held     = u.zoom_config.w > 0.5;
    var heatPos  = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var heatVel  = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let springInitialized = extraBuffer[137] > 0.5;
    if (!springInitialized) {
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

    // Thermal sway
    let sway      = fbm2(vec2<f32>(time * 0.7, time * 0.53)) * 0.015;

    // Heat column stronger at bottom; held press widens + intensifies gradient
    let heatBase  = smoothstep(1.0, 0.0, uv.y) * 0.5 + 0.5;
    let mDist     = length((uv - (heatPos + sway)) * vec2<f32>(aspect, 1.0));
    let holdRadius = select(0.25, 0.34, held);
    let holdGain   = select(1.0, 1.55 + bass * 0.35, held);
    let mouseHeat = smoothstep(holdRadius, 0.0, mDist) * select(0.0, holdGain, held);

    var heatFactor = heatBase + mouseHeat;

    // ── Click heat bursts (≤50) ───────────────────────────────────
    var clickHeat = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp  = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            clickHeat = max(clickHeat, exp(-age * 1.5) * smoothstep(0.2, 0.0, rDist));
        }
    }
    heatFactor = min(heatFactor + clickHeat, 2.5);

    // ── Per-band FFT shimmer ──────────────────────────────────────
    let band      = u32(clamp(uv.y * 8.0, 0.0, 7.999));
    let bandBoost = plasmaBuffer[(band % 8u) + 1u].x * 0.35;

    // Rising displacement field
    let risingUV  = vec2<f32>(uv.x * wavyScale, uv.y * wavyScale - time * riseSpeed);
    let disp      = fbm2(risingUV) * heatIntensity * heatFactor * (1.0 + bandBoost);

    // ── Refractive-index gradient ray bending ─────────────────────
    // Held press intensifies dn/dy so the inversion fold arrives sooner.
    let gradScale = select(25.0, 34.0, held);
    let heatAbove = smoothstep(1.0, 0.0, uv.y + 0.04) * 0.5 + 0.5 + mouseHeat;
    let dn_dy     = (heatAbove - heatBase - mouseHeat) * gradScale;
    let pathLen   = smoothstep(0.9, 0.0, uv.y);
    let bend      = -dn_dy * pathLen * pathLen * heatIntensity * 0.42;

    let heatDisp  = vec2<f32>(disp.x, disp.y * 0.3 + bend);

    // Caustic runners — bright amber streaks racing through the hot layer
    let causticPhase = uv.x * 48.0 + uv.y * 14.0 - time * 7.5;
    let caustic = pow(max(0.0, sin(causticPhase + disp.x * 18.0)), 18.0)
                * heatFactor * smoothstep(0.75, 0.0, uv.y);
    let causticWarp = vec2<f32>(caustic * 0.004 * (1.0 + treble), -caustic * 0.002);
    let totalDisp = heatDisp + causticWarp;

    // Chromatic shift across the mirage
    let rUV = clamp(uv + totalDisp + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + totalDisp,                                vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + totalDisp - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let a = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    // ── Stronger inversion-layer false-water fold ─────────────────
    let criticalGrad = select(0.55, 0.42, held);
    let tirMix = smoothstep(criticalGrad, criticalGrad + 0.42, abs(bend) * 48.0)
               * smoothstep(0.58, 0.0, uv.y);
    let mirrorUV = clamp(vec2<f32>(gUV.x, 2.0 * uv.y - gUV.y + bend * 2.4),
                         vec2<f32>(0.0), vec2<f32>(1.0));
    let mirrored = textureSampleLevel(readTexture, u_sampler, mirrorUV, 0.0).rgb;

    // Warm amber atmospheric tint (not neon cyan)
    let warmTint   = vec3<f32>(1.06, 1.01, 0.94) * (1.0 + heatFactor * 0.12);
    var col        = mix(vec3<f32>(r, g, b), mirrored, tirMix * 0.88) * warmTint;

    // Heat shimmer glow + caustic highlights
    let glowMask   = heatFactor * heatIntensity * 55.0;
    col += vec3<f32>(0.07, 0.035, 0.01) * glowMask * (1.0 + mid);
    col += vec3<f32>(1.0, 0.55, 0.18) * caustic * 0.22 * (1.0 + bandBoost);

    // Temporal accumulate haze state — exact textureLoad on C
    let prev     = textureLoad(dataTextureC, coord, 0);
    let hazeAcc  = mix(vec4<f32>(col, a), prev, 0.85);

    col = acesFilm(col);

    // Semantic alpha: haze density + mirage fold + caustic
    let hazeDensity = clamp((heatFactor - 0.5) * 0.85 + tirMix * 0.7 + caustic * 0.25, 0.0, 1.0);
    let outAlpha = clamp(mix(a, 1.0, hazeDensity * 0.75), 0.0, 1.0);
    let outColor = vec4<f32>(col, outAlpha);
    textureStore(writeTexture, coord, outColor);

    // Depth: scene geometry preserved, pushed by mirage relief
    let sceneDepth = textureLoad(readDepthTexture, coord, 0).r;
    let reliefDepth = clamp(sceneDepth - heatFactor * 0.04 - tirMix * 0.07 - caustic * 0.02, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(reliefDepth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, hazeAcc);
    textureStore(dataTextureB, coord, vec4<f32>(totalDisp, heatFactor, bass));
}
