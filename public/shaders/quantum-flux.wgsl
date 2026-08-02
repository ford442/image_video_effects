// ═══════════════════════════════════════════════════════════════════
//  Quantum Flux
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  Swarm upgrade: 2026-08-02 (sprung flux center, click decoherence
//  bursts, per-sector FFT jitter voices)
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Slider params (roles kept EXACTLY): x = Flux Jitter, y = Wave Freq,
    // z = Color Drift, w = Flux Radius — each rides its own audio band.
    let jitterBase = u.zoom_params.x * (1.0 + treble * 0.6);
    let freq = u.zoom_params.y * (1.0 + mids * 0.4);
    let driftSpeed = u.zoom_params.z * (1.0 + mids * 0.5);
    let radiusParam = u.zoom_params.w * (1.0 + bass * 0.3);

    // ─── Sprung flux center (critically-damped spring, zeta = 1) ───
    // The raw cursor is only the spring TARGET; the influence zone trails
    // it like a probability cloud that cannot collapse instantly.
    // Persistent state in extraBuffer (engine reserves [0..4], FFT bins
    // live in [5..132], shader state stays in [133..255]):
    //   [133..134] sprung center, [135..136] spring velocity,
    //   [137] init flag, [138] last integration time.
    let mouse = u.zoom_config.yz;
    var fPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var fVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let springInitialized = extraBuffer[137] >= 0.5;
    if (!springInitialized) {
        fPos = mouse;
        fVel = vec2<f32>(0.0, 0.0);
    }
    let dt = select(0.0, clamp(time - extraBuffer[138], 0.0005, 0.05), springInitialized);
    let omega = 9.0;
    let fAcc = omega * omega * (mouse - fPos) - 2.0 * omega * fVel;
    fVel = fVel + fAcc * dt;
    fPos = fPos + fVel * dt;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = fPos.x;
        extraBuffer[134] = fPos.y;
        extraBuffer[135] = fVel.x;
        extraBuffer[136] = fVel.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }
    // All pixels use the same locally integrated center for this frame.
    let fluxCenter = fPos;

    let aspect = resolution.x / resolution.y;
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(fluxCenter.x * aspect, fluxCenter.y);
    let dist = distance(uvCorrected, mouseCorrected);

    let influenceRadius = radiusParam * 0.8 + 0.1;
    let influence = smoothstep(influenceRadius, 0.0, dist);

    // ─── Per-sector FFT voices ───
    // The influence zone is sliced into 8 angular sectors around the sprung
    // center; each wedge's jitter magnitude rides its own FFT bin, so
    // different directions vibrate to different frequencies.
    let delta = uvCorrected - mouseCorrected;
    let angle = atan2(delta.y, delta.x);
    let sectorF = floor((angle + 3.14159265) / 6.2831853 * 8.0);
    let sector = u32(sectorF) % 8u;
    let sectorVoice = plasmaBuffer[(sector % 8u) + 1u].x * 0.3;

    // ─── Click decoherence bursts ───
    // Each live ripple (a click) spikes the jitter locally at its click
    // point: a decaying bump in an aspect-corrected ~0.25 radius falloff,
    // exp(-rippleAge * 2.0), effective lifetime ~1.2s. Reality flickers
    // where you clicked without holding the cursor still.
    var clickBurst = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge > 0.0 && rippleAge < 1.2) {
            let ripplePos = vec2<f32>(ripple.x * aspect, ripple.y);
            let rippleDist = distance(uvCorrected, ripplePos);
            clickBurst = clickBurst + jitterBase * 0.6
                * smoothstep(0.25, 0.0, rippleDist) * exp(-rippleAge * 2.0);
        }
    }

    // Local jitter magnitude: slider base, voiced by this wedge's FFT bin,
    // spiked by click decoherence bursts.
    let jitterAmount = jitterBase * (1.0 + sectorVoice) + clickBurst;

    let seed = uv + vec2<f32>(time * 0.1, time * 0.1);
    let noiseX = (rand(seed) - 0.5) * 2.0;
    let noiseY = (rand(seed + vec2<f32>(1.0, 1.0)) - 0.5) * 2.0;
    let jitter = vec2<f32>(noiseX, noiseY) * jitterAmount * 0.05 * influence;
    let wave = sin(dist * (freq * 50.0) - time * 5.0) * 0.02 * influence;

    let split = jitterAmount * 0.02 * influence;
    let uvR = clamp(uv + jitter + vec2<f32>(wave + split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv - jitter + vec2<f32>(0.0, wave), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + jitter * 0.5 - vec2<f32>(split + wave, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
    let sG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
    let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // Hue drift (branchless via mix on influence)
    var hsv = rgb2hsv(color);
    hsv.x = fract(hsv.x + (time * driftSpeed * 0.5) + (dist * 2.0));
    hsv.y = min(1.0, hsv.y + influence * 0.2);
    let driftedColor = hsv2rgb(hsv);
    let driftMask = clamp(driftSpeed * 10.0, 0.0, 1.0) * smoothstep(0.0, 0.01, influence);
    color = mix(color, driftedColor, driftMask);

    // Interference scanlines
    let interference = sin(uv.y * resolution.y * 0.5 + time * 10.0) * 0.5 + 0.5;
    color = mix(color, color * (0.8 + 0.2 * interference), influence * 0.5);

    // Meaningful alpha: blend weight from influence + chromatic split + base alpha
    let splitMag = abs(sR.r - sB.b) + abs(sG.g - sR.r);
    let alpha = clamp(baseSample.a * 0.5 + influence * 0.3 + splitMag * 0.4 + treble * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
