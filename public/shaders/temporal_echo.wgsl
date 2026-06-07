// ═══════════════════════════════════════════════════════════════════
//  Temporal Echo
//  Category: lighting-effects
//  Features: temporal, depth-aware, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  upgraded-rgba
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: decay_rate       — how fast echoes fade (high=fast trails)
//  Param2: hue_shift_speed  — hue rotation rate per echo generation
//  Param3: chroma_spread    — RGB channel separation on older echoes
//  Param4: depth_influence  — near objects echo more strongly/longer

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
  zoom_params: vec4<f32>,  // x=DecayRate, y=HueShiftSpeed, z=ChromaSpread, w=DepthInfluence
  ripples: array<vec4<f32>, 50>,
};

// ─── Colour helpers ────────────────────────────────────────────────

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// ─── Main ─────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv   = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let px   = 1.0 / resolution;

    // Params
    let decayRate     = u.zoom_params.x * 0.12 + 0.02;
    let hueSpeed      = u.zoom_params.y * 0.4;
    let chromaSpread  = u.zoom_params.z * 0.018;
    let depthInfluence = u.zoom_params.w;

    // Audio
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass   = select(0.0, plasmaBuffer[0].x, hasAudio);
    let mids   = select(0.0, plasmaBuffer[0].y, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

    // Depth: near = 1, far = 0
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Depth-weighted decay: near objects hold their echo longer
    let effectiveDecay = decayRate * (1.0 - depth * depthInfluence * 0.7)
                       * (1.0 - bass * 0.25);  // bass slows decay on beat

    // ── Chromatic aberration on echo sample ───────────────────────
    // Older echoes have RGB channels pulled apart by chromaSpread
    let echoOffset = vec2<f32>(sin(time * 0.4) * 0.003, cos(time * 0.3) * 0.003);
    let rUV = clamp(uv + echoOffset + vec2<f32>( chromaSpread, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + echoOffset,                                  vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + echoOffset - vec2<f32>( chromaSpread, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let prevR = textureSampleLevel(dataTextureC, non_filtering_sampler, rUV, 0.0).r;
    let prevG = textureSampleLevel(dataTextureC, non_filtering_sampler, gUV, 0.0).g;
    let prevB = textureSampleLevel(dataTextureC, non_filtering_sampler, bUV, 0.0).b;
    let prevA = textureSampleLevel(dataTextureC, non_filtering_sampler, uv,  0.0).a;

    let prevColor = vec3<f32>(prevR, prevG, prevB);

    // ── Hue-rotate the echo ───────────────────────────────────────
    var hsv = rgb2hsv(prevColor);
    hsv.x = fract(hsv.x + hueSpeed * 0.016
                  + mids * 0.008       // mids nudge hue on beat
                  + treble * 0.004);
    let rotatedEcho = hsv2rgb(hsv);

    // ── Current frame sample ──────────────────────────────────────
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let brightness = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let newAlpha = brightness * mix(0.5, 1.0, depth);  // near objects contribute more

    // ── Blend: decay echo, add new frame ─────────────────────────
    let decayedEcho = rotatedEcho * (1.0 - effectiveDecay);
    let echoAlpha   = prevA       * (1.0 - effectiveDecay);

    // Beat flash: bass triggers a brief bright injection
    let beatFlash = bass * 0.18 * step(0.65, bass);

    // Mix new frame into decayed echo
    let blendFactor = clamp(newAlpha * 0.4 + beatFlash, 0.0, 1.0);
    let newColor = mix(decayedEcho, current.rgb + vec3<f32>(beatFlash), blendFactor);
    let newAcc   = clamp(echoAlpha + newAlpha * 0.3, 0.0, 1.0);

    let finalAlpha = mix(current.a, 1.0, newAcc * 0.7);
    let result = vec4<f32>(newColor, finalAlpha);

    textureStore(dataTextureA, vec2<i32>(global_id.xy), result);
    textureStore(writeTexture,  vec2<i32>(global_id.xy), result);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy),
                 vec4<f32>(depth, 0.0, 0.0, 1.0));
}
