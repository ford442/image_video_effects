// ═══════════════════════════════════════════════════════════════════
//  Luma Echo Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-echo, depth-attenuation, upgraded-rgba, curl-noise, chromatic-echo
//  Complexity: High
//  Chunks From: luma-echo-warp, bass_env, temporal-feedback
//  Created: 2024-01-01
//  Upgraded: 2026-06-28
//  Upgraded by: kimi-swarm 2026-07-19
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

// ── Noise helpers (canonical codebase forms) ──────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),                        hash21(i + vec2<f32>(1.0, 0.0)), uu.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)),  hash21(i + vec2<f32>(1.0, 1.0)), uu.x),
        uu.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum  += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp  *= 0.5;
    }
    return sum;
}

// Divergence-free curl of an animated fbm potential: organic swirl
// without the smearing a pure radial push produces. 4 taps x 3 octaves.
fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.12;
    let drift = vec2<f32>(t * 0.07, -t * 0.05);
    let nT = fbm(p + vec2<f32>(0.0, e) + drift, 3);
    let nB = fbm(p - vec2<f32>(0.0, e) + drift, 3);
    let nR = fbm(p + vec2<f32>(e, 0.0) - drift.yx, 3);
    let nL = fbm(p - vec2<f32>(e, 0.0) - drift.yx, 3);
    let dY = (nT - nB) / (2.0 * e);
    let dX = (nR - nL) / (2.0 * e);
    return vec2<f32>(dY, -dX);
}

// IQ cosine palette — slow hue cycle for the echo shimmer
fn cosPalette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

// Soft shoulder: identity below 1.0, compresses highlights toward ~2.0
fn highlightRollOff(c: vec3<f32>) -> vec3<f32> {
    let over = max(c - vec3<f32>(1.0), vec3<f32>(0.0));
    return min(c, vec3<f32>(1.0)) + over / (vec3<f32>(1.0) + over);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAtten = mix(1.0, 0.6, depth);

    // User params — semantics unchanged:
    //   x = Warp Strength, y = Echo Decay, z = Radius, w = Luma Weight
    let audioMod = bass_env(bass, mids);
    let strength = mix(0.0, 2.0, clamp(u.zoom_params.x, 0.0, 1.0)) * audioMod * depthAtten;
    let decay = mix(0.9, 0.99, clamp(u.zoom_params.y, 0.0, 1.0));
    let radius = mix(0.1, 0.5, clamp(u.zoom_params.z, 0.0, 1.0));
    let lumaWeight = clamp(u.zoom_params.w, 0.0, 1.0);

    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // ── Warp field: radial push + tangential swirl + curl drift ────
    let dVec = uv - mousePos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
    let lenD = length(dVec);
    let dir = select(vec2<f32>(0.0, 0.0), dVec / max(lenD, 0.0001), lenD > 0.0001);
    let influence = smoothstep(radius, 0.0, dist);
    let weight = mix(1.0, luma, lumaWeight);
    let mouseActive = select(0.0, 1.0, mousePos.x >= 0.0);

    let tangent = vec2<f32>(-dir.y, dir.x);
    var warp = (dir + tangent * 0.7) * influence * strength * weight * 0.1 * mouseActive;
    let flow = curlNoise(uv * vec2<f32>(aspect, 1.0) * 2.5, u.config.x);
    warp += flow * 0.012 * strength * weight * (0.3 + 0.7 * influence) * mouseActive;
    // Hard bound on displacement so warped taps can never run away
    let warpLen = length(warp);
    warp *= select(1.0, 0.15 / max(warpLen, 0.0001), warpLen > 0.15);

    let distortedUV = clamp(uv - warp, vec2<f32>(0.0), vec2<f32>(1.0));
    let warpedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // ── Temporal echo with true chromatic trail ────────────────────
    // Per-channel history taps offset along the warp direction; bilinear
    // history sampling keeps the trail smooth instead of stepping texels.
    let caMag = (0.0012 + bass * 0.0018) * (0.3 + 0.7 * influence);
    let caVec = dir * caMag + warp * 0.05;
    let histG = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let histR = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + caVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let histB = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - caVec * 0.7, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let history = vec4<f32>(histR, histG.g, histB, histG.a);

    let echoDecay = clamp(decay * (1.0 - bass * 0.05), 0.0, 1.0);
    let mixed = mix(warpedColor, history, echoDecay);
    let outputColor = mix(mixed, warpedColor, isMouseDown * 0.5);

    // ── Echo shimmer: cosine palette tint, locked to luma ──────────
    // Output-only (never fed back) so the tint cannot accumulate.
    let tint = cosPalette(u.config.x * 0.05 + luma * 0.6);
    let tintAmt = (0.10 + bass * 0.05) * smoothstep(0.15, 0.85, luma);
    var finalRGB = outputColor.rgb * mix(vec3<f32>(1.0), tint * 1.15, clamp(tintAmt, 0.0, 0.25));

    // Treble sparkle with per-pixel twinkle in high-luma regions
    let twinkle = 0.5 + 0.5 * hash21(vec2<f32>(global_id.xy) * 0.713 + floor(u.config.x * 24.0) * 17.0);
    let sparkle = treble * 0.15 * luma * influence * twinkle;
    finalRGB += vec3<f32>(sparkle);

    // HDR-safe highlights: soft shoulder, then hard backstop
    finalRGB = clamp(highlightRollOff(finalRGB), vec3<f32>(0.0), vec3<f32>(4.0));
    let alpha = clamp(outputColor.a * 0.7 + influence * 0.2 + bass * 0.08, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    // Feedback store: pre-tint / pre-sparkle echo only, clamped — keeps the
    // decay loop stable instead of integrating sparkle toward blowup.
    let feedback = clamp(mixed.rgb, vec3<f32>(0.0), vec3<f32>(1.2));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(feedback, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
