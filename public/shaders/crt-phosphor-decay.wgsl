// ═══════════════════════════════════════════════════════════════════
//  CRT Phosphor Decay — Phase A Upgrade
//  Category: retro-glitch
//  Features: mouse-driven, click-reactive, audio-reactive, depth-aware, temporal
//  Complexity: Medium
//  Created: 2026-05-23
//  Upgraded: 2026-08-02 (Batch 30)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: decay_rate        — phosphor persistence (longer trails)
//  Param2: scanline_intensity — scanline darkness and spacing
//  Param3: halation_spread   — bloom radius around bright phosphors
//  Param4: audio_sensitivity — bass → brightness flash, treble → scanline flutter

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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=DecayRate, y=ScanlineIntensity, z=HalationSpread, w=AudioSensitivity
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let p3d = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3d.x + p3d.y) * p3d.z);
}

// 5-tap horizontal blur for halation glow
fn halation(uv: vec2<f32>, spread: f32) -> vec3<f32> {
    let e = vec2<f32>(spread / u.config.z, 0.0);
    var c = textureSampleLevel(readTexture, u_sampler, clamp(uv - e * 2.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.08;
    c    += textureSampleLevel(readTexture, u_sampler, clamp(uv - e, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.17;
    c    += textureSampleLevel(readTexture, u_sampler, uv,            0.0).rgb * 0.50;
    c    += textureSampleLevel(readTexture, u_sampler, clamp(uv + e, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.17;
    c    += textureSampleLevel(readTexture, u_sampler, clamp(uv + e * 2.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.08;
    return c;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let uv   = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    let audioSens   = u.zoom_params.w;
    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0) * audioSens;
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0) * audioSens;
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0) * audioSens;
    let rowBin = (gid.y % 8u) + 1u;
    let rowVoice = clamp(plasmaBuffer[rowBin].x, 0.0, 1.0) * audioSens;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        mouse = rawMouse;
        mouseVelocity = vec2<f32>(0.0);
    }
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 11.0;
    mouseVelocity += ((rawMouse - mouse) * (omega * omega) - mouseVelocity * (2.0 * omega)) * dt;
    mouse += mouseVelocity * dt;
    if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[133] = mouse.x;
        extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x;
        extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }

    // Params (mids deepens scanlines)
    let decayBase   = 0.82 + u.zoom_params.x * 0.17;
    let scanlineStr = u.zoom_params.y * (1.0 + mids * 0.5);
    let haloSpread  = u.zoom_params.z * 4.0 + 0.5;

    // Depth — near phosphors (depth→1) bloom more
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Fresh phosphor input with halation bloom
    let fresh = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let halo  = halation(uv, haloSpread);
    let luma  = dot(fresh, vec3<f32>(0.299, 0.587, 0.114));
    // Halation only where bright; depth-weighted (near glows more)
    let haloMix = smoothstep(0.3, 0.9, luma) * 0.35 * (0.5 + depth * 0.5);
    let boosted = mix(fresh, halo, haloMix) * (1.0 + bass * 0.3);

    // Per-channel decay — R slowest (red phosphor holds charge longest), B fastest
    let prev   = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    let decayR = decayBase;
    let decayG = decayBase * 0.97;
    let decayB = decayBase * 0.94;
    let decayed = vec3<f32>(prev.r * decayR, prev.g * decayG, prev.b * decayB);

    // Phosphor: max(fresh, ghost) — bright pixels light up instantly, fade slowly
    var outCol = max(boosted, decayed);

    // Scanlines — sine wave with treble flutter on spacing
    let scanFreq = resolution.y * 0.5 * (1.0 + treble * 0.08 + rowVoice * 0.025);
    let scanline = sin(uv.y * scanFreq) * 0.5 + 0.5;
    outCol *= mix(1.0, scanline, scanlineStr * 0.7);

    // Sub-pixel RGB mask (phosphor triad simulation)
    let pixX  = fract(uv.x * resolution.x);
    let subR  = smoothstep(0.0, 0.33, pixX) * (1.0 - smoothstep(0.33, 0.66, pixX));
    let subG  = smoothstep(0.33, 0.66, pixX) * (1.0 - smoothstep(0.66, 1.0, pixX));
    let subB  = smoothstep(0.66, 1.0, pixX);
    let subMask = vec3<f32>(subR, subG, subB) * 0.4 + 0.6;
    outCol *= mix(vec3<f32>(1.0), subMask, scanlineStr * 0.5);

    // Mouse static and click blooms activate localized phosphors.
    let aspect = resolution.x / resolution.y;
    let mDist  = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));
    let mouseFalloff = 1.0 - smoothstep(0.0, 0.12, mDist);
    outCol += hash12(uv * time) * mouseFalloff * (0.25 + treble * 0.25);

    var clickBloom = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.2) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let radius = length(delta);
            let core = (1.0 - smoothstep(0.0, 0.10, radius)) * exp(-age * 2.8);
            let ring = exp(-abs(radius - age * 0.12) * 65.0) * exp(-age * 1.2);
            clickBloom = max(clickBloom, core + ring * 0.7);
        }
    }
    outCol += vec3<f32>(1.0, 0.55 + rowVoice * 0.25, 0.3 + treble * 0.3) * clickBloom * 0.65;

    outCol = clamp(outCol, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(outCol, 1.0));
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(outCol, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
