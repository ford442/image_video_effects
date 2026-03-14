// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Phase Inversion
//  Category: EFFECT | Complexity: VERY_HIGH
//  Inverts specific color channels by temporal phase, creating surreal color
//  ghosts that are spatially offset from the source. Colors feel "ahead of" or
//  "behind" reality—a temporal chromatic aberration in perception space.
//  Mathematical approach: Per-channel Hilbert-style analytic signal via
//  quadrature oscillators, phase-offset sampling in time, Lissajous UV
//  displacement, adaptive inversion masks from local luminance gradient.
// ═══════════════════════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=PhaseSpeed, y=MouseX, z=MouseY, w=GhostTrail
    zoom_params: vec4<f32>,  // x=PhaseOffset, y=InversionDepth, z=SpatialSpread, w=LissajousRatio
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Hash
// ─────────────────────────────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth noise
// ─────────────────────────────────────────────────────────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Quadrature oscillator: produces sine/cosine pair for analytic signal
//  This creates a smooth "phase" that can be shifted per-channel
// ─────────────────────────────────────────────────────────────────────────────
fn quadraturePhase(signal: f32, time: f32, freq: f32) -> vec2<f32> {
    let phase = signal * 6.28318 + time * freq;
    return vec2<f32>(sin(phase), cos(phase));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Lissajous curve displacement: creates complex orbital UV offsets
//  Different frequency ratios per channel create separation patterns
// ─────────────────────────────────────────────────────────────────────────────
fn lissajousOffset(time: f32, ratio: f32, amplitude: f32, phaseOff: f32) -> vec2<f32> {
    let a = 3.0 * ratio;
    let b = 2.0 * ratio + 1.0;
    return vec2<f32>(
        sin(a * time + phaseOff) * amplitude,
        sin(b * time) * amplitude
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Luminance gradient magnitude: detects edges for inversion masking
// ─────────────────────────────────────────────────────────────────────────────
fn lumGradient(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    let cR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;
    let cL = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rgb;
    let cU = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
    let cD = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).rgb;
    let lumR = dot(cR, vec3<f32>(0.299, 0.587, 0.114));
    let lumL = dot(cL, vec3<f32>(0.299, 0.587, 0.114));
    let lumU = dot(cU, vec3<f32>(0.299, 0.587, 0.114));
    let lumD = dot(cD, vec3<f32>(0.299, 0.587, 0.114));
    return length(vec2<f32>(lumR - lumL, lumU - lumD));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Phase-driven selective inversion
//  When the phase crosses zero, the channel inverts—creating temporal flicker
// ─────────────────────────────────────────────────────────────────────────────
fn phaseInvert(value: f32, phase: f32, depth: f32) -> f32 {
    let invertMask = smoothstep(-0.1, 0.1, sin(phase));
    return mix(value, 1.0 - value, invertMask * depth);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = fragCoord / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    // ─────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ─────────────────────────────────────────────────────────────────────────
    let phaseOffset = u.zoom_params.x * 3.14159;            // 0 – π
    let inversionDepth = u.zoom_params.y * 0.8 + 0.1;      // 0.1 – 0.9
    let spatialSpread = u.zoom_params.z * 0.04 + 0.002;    // 0.002 – 0.042
    let lissajousRatio = u.zoom_params.w * 2.0 + 0.5;      // 0.5 – 2.5
    let phaseSpeed = u.zoom_config.x * 3.0 + 0.5;          // 0.5 – 3.5
    let ghostTrail = u.zoom_config.w * 0.4 + 0.5;          // 0.5 – 0.9

    // ─────────────────────────────────────────────────────────────────────────
    //  Read source and depth
    // ─────────────────────────────────────────────────────────────────────────
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, u_sampler, uv, 0.0).r;
    let lum = dot(srcColor, vec3<f32>(0.299, 0.587, 0.114));
    let edgeStr = lumGradient(uv, texel);

    // ─────────────────────────────────────────────────────────────────────────
    //  Per-channel phase computation
    //  Each channel has a different temporal phase → they invert at different times
    // ─────────────────────────────────────────────────────────────────────────
    let phaseR = quadraturePhase(lum, time * phaseSpeed, 1.0);
    let phaseG = quadraturePhase(lum, time * phaseSpeed, 1.0 + phaseOffset * 0.3);
    let phaseB = quadraturePhase(lum, time * phaseSpeed, 1.0 + phaseOffset * 0.7);

    // ─────────────────────────────────────────────────────────────────────────
    //  Lissajous spatial displacement per channel
    //  Colors drift in orbital patterns, offset from each other
    // ─────────────────────────────────────────────────────────────────────────
    let depthMod = 0.3 + depth * 0.7;
    let dispR = lissajousOffset(time * 0.7, lissajousRatio, spatialSpread * depthMod, 0.0);
    let dispG = lissajousOffset(time * 0.7, lissajousRatio * 1.1, spatialSpread * depthMod, phaseOffset);
    let dispB = lissajousOffset(time * 0.7, lissajousRatio * 0.9, spatialSpread * depthMod, phaseOffset * 2.0);

    // ─────────────────────────────────────────────────────────────────────────
    //  Ripple interaction: phase disruption
    // ─────────────────────────────────────────────────────────────────────────
    var ripplePhaseShift = 0.0;
    var rippleDisp = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let dist = distance(uv, r.xy);
        let age = time - r.z;
        if (age > 0.0 && age < 4.0) {
            let wave = sin(dist * 30.0 - age * 5.0) * exp(-dist * 5.0) * exp(-age * 0.7);
            ripplePhaseShift += wave * 3.14159;
            rippleDisp += normalize(uv - r.xy + vec2<f32>(0.0001)) * wave * 0.01;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Sample displaced channels
    // ─────────────────────────────────────────────────────────────────────────
    let uvR = clamp(uv + dispR + rippleDisp, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + dispG + rippleDisp * 0.7, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + dispB + rippleDisp * 1.3, vec2<f32>(0.0), vec2<f32>(1.0));

    let sampR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let sampG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let sampB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // ─────────────────────────────────────────────────────────────────────────
    //  Apply phase-driven inversion per channel
    //  Edge areas invert more strongly → ghosts form at contours
    // ─────────────────────────────────────────────────────────────────────────
    let edgeMask = smoothstep(0.01, 0.15, edgeStr);
    let effectiveDepth = inversionDepth * mix(0.3, 1.0, edgeMask);

    let finalR = phaseInvert(sampR, phaseR.x + ripplePhaseShift, effectiveDepth);
    let finalG = phaseInvert(sampG, phaseG.x + ripplePhaseShift * 0.8, effectiveDepth);
    let finalB = phaseInvert(sampB, phaseB.x + ripplePhaseShift * 1.2, effectiveDepth);

    var result = vec3<f32>(finalR, finalG, finalB);

    // ─────────────────────────────────────────────────────────────────────────
    //  Ghost overlay: previous frame's inverted state bleeds through
    //  Creates the "temporal echo" of color ghosts
    // ─────────────────────────────────────────────────────────────────────────
    let noiseWarp = valueNoise(uv * 20.0 + time * 0.3) * 0.005;
    let ghostUV = clamp(uv + vec2<f32>(noiseWarp), vec2<f32>(0.0), vec2<f32>(1.0));
    let ghost = textureSampleLevel(dataTextureC, u_sampler, ghostUV, 0.0).rgb;

    // Ghost color is shifted: the "memory" of where colors used to be
    let ghostShifted = vec3<f32>(ghost.g, ghost.b, ghost.r) * 0.8;
    result = mix(result, mix(result, ghostShifted, 0.3), ghostTrail);

    // ─────────────────────────────────────────────────────────────────────────
    //  Subtle phase-interference pattern overlay
    // ─────────────────────────────────────────────────────────────────────────
    let interference = sin(uv.x * 200.0 + time * 2.0) * sin(uv.y * 200.0 - time * 1.7);
    result += vec3<f32>(interference * 0.02 * edgeMask);

    // ─────────────────────────────────────────────────────────────────────────
    //  Output
    // ─────────────────────────────────────────────────────────────────────────
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(result, 1.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(result, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
