// ═══════════════════════════════════════════════════════════════════════════════
//  Relay Psychedelia — multi-agent generative shader relay
//  Category: generative
//  Relay doc: agents/RELAY_PROTOCOL.md
//  Hop 0 (spine): baseline warped field + palette + feedback-ready composite
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=time, y=delta_time, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // x=warp, y=saturation, z=hue-shift, w=feedback
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ─── FROZEN UTILITIES (relay agents: do not modify) ─────────────────────────

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

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

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn psychedelicPalette(t: f32) -> vec3<f32> {
    let hue = fract(t);
    let saturation = clamp(0.72 + 0.28 * sin(TAU * (t * 0.137 + 0.19)), 0.45, 1.0);
    let value = 1.0 + 0.18 * sin(TAU * (t * 0.071 + 0.43));
    let rgb = clamp(abs(fract(vec3<f32>(hue) + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let smoothRgb = rgb * rgb * (vec3<f32>(3.0) - 2.0 * rgb);
    return mix(vec3<f32>(value), smoothRgb * value, saturation);
}

fn organicDrift(uv: vec2<f32>, time: f32, scale: f32) -> vec2<f32> {
    let safeScale = max(scale, 0.001);
    let p = uv * safeScale;
    let slow = vec2<f32>(time * 0.11, -time * 0.08);
    let q = vec2<f32>(
        fbm(p + slow, 3),
        fbm(p * 1.37 + vec2<f32>(5.2, 1.3) - slow.yx, 3)
    );
    let r = vec2<f32>(
        fbm(p * 0.73 + q * 2.0 + vec2<f32>(1.7, 9.2), 2),
        fbm(p * 0.91 - q.yx * 2.0 + vec2<f32>(8.1, 2.8), 2)
    );
    return ((q + r * 0.5) * 2.0 - vec2<f32>(1.5)) / safeScale;
}

fn aspectUv(coord: vec2<i32>, res: vec2<f32>) -> vec2<f32> {
    var uv = (vec2<f32>(coord) + 0.5) / res;
    uv = uv * 2.0 - 1.0;
    let aspect = res.x / max(res.y, 1.0);
    uv.x *= aspect;
    return uv;
}

// ─── FROZEN COMPOSITE (only mix weights may change between hops) ─────────────

fn finalComposite(color: vec3<f32>, exposure: f32) -> vec3<f32> {
    return acesToneMap(clamp(color, vec3<f32>(0.0), vec3<f32>(8.0)) * exposure);
}

// ═══ CHUNK: motion-modulation (OWNER: hop-5) ═════════════════════════════════

struct MotionState {
    warpStrength: f32,
    timeScale: f32,
    pulse: f32,
    saturationBoost: f32,
    hueDrift: f32,
}

fn motionModulate(time: f32, bass: f32, mids: f32) -> MotionState {
    // OWNER: cursor-hop-5 2026-07-19
    // Multi-LFO audio stack — pushes warp + palette timing past legibility on peaks.
    let treble = plasmaBuffer[0].z;
    let safeBass = clamp(bass, 0.0, 2.0);
    let safeMids = clamp(mids, 0.0, 2.0);
    let safeTreble = clamp(treble, 0.0, 2.0);

    // Incommensurate LFOs avoid short-loop repetition.
    let lfoSlow = sin(time * 0.37) * 0.5 + 0.5;
    let lfoMid = sin(time * 1.13 + safeBass * 0.9) * 0.5 + 0.5;
    let lfoFast = sin(time * 2.71 + safeMids * 1.1) * 0.5 + 0.5;
    let lfoSpark = sin(time * 5.17 + safeTreble * 1.8) * 0.5 + 0.5;

    // Bass surges warp depth; stacked LFOs add breathing chaos.
    let warpLfo = mix(0.62, 1.55, lfoMid * lfoFast);
    let warpBase = mix(0.12, 0.52, clamp(u.zoom_params.x, 0.0, 1.0));
    let bassSurge = 1.0 + safeBass * 0.38;
    let warpStrength = warpBase * warpLfo * bassSurge * (0.86 + 0.28 * lfoSlow);

    // Mids/treble accelerate palette phase; slow LFO adds crawl/sprint swings.
    let timeWarp = 1.0
        + safeMids * 0.30 * lfoFast
        + safeTreble * 0.14 * sin(time * 3.9)
        + (lfoSlow - 0.5) * 0.26;
    let timeScale = clamp(timeWarp, 0.50, 2.45);

    // Exposure thump + treble sparkle on composite.
    let pulse = 0.76
        + 0.24 * lfoMid
        + safeBass * 0.14 * sin(time * (2.2 + safeBass * 0.6))
        + safeTreble * 0.07 * lfoSpark;

    // Palette LFOs: saturation pump + hue wobble (wired in main).
    let saturationBoost = clamp(
        0.72 + 0.36 * lfoFast + safeMids * 0.18 * lfoSpark,
        0.55,
        1.45,
    );
    let hueDrift = (lfoMid - 0.5) * 0.22
        + safeTreble * 0.06 * sin(time * 4.3)
        + safeBass * 0.04 * sin(time * 0.85);

    return MotionState(
        warpStrength,
        timeScale,
        clamp(pulse, 0.70, 1.42),
        saturationBoost,
        hueDrift,
    );
}

// ═══ CHUNK: domain-warp (OWNER: hop-1) ═══════════════════════════════════════

fn applyDomainWarp(p: vec2<f32>, time: f32, strength: f32) -> vec2<f32> {
    // OWNER: claude-hop-1 2026-07-19
    // Recursive IQ-style domain warp: three chained fbm displacement levels
    // (q -> r -> s), organicDrift kept as a slow pre-warp layer.
    var pp = p + organicDrift(p, time, 6.0) * strength * 0.5;

    // Optional mouse bias: pull the warp domain toward the cursor while held.
    if (u.zoom_config.w > 0.5) {
        let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
        pp += (mouse - pp) * 0.18 * strength;
    }

    let flow = vec2<f32>(time * 0.05, -time * 0.04);

    let q = vec2<f32>(
        fbm(pp * 1.6 + flow, 4),
        fbm(pp * 1.6 + vec2<f32>(5.2, 1.3) - flow, 4)
    ) - vec2<f32>(0.5);

    let r = vec2<f32>(
        fbm(pp * 1.9 + q * 2.3 + vec2<f32>(1.7, 9.2) + flow * 1.4, 4),
        fbm(pp * 1.9 + q * 2.3 + vec2<f32>(8.3, 2.8) - flow * 1.1, 4)
    ) - vec2<f32>(0.5);

    let s = vec2<f32>(
        fbm(pp * 1.4 + r * 2.7 + vec2<f32>(6.9, 4.1) + flow * 0.7, 3),
        fbm(pp * 1.4 + r * 2.7 + vec2<f32>(3.4, 7.7) - flow * 0.9, 3)
    ) - vec2<f32>(0.5);

    // Bounded: |q|,|r|,|s| <~ 0.5 each, so total offset <~ 2.1 * strength.
    return pp + strength * (q * 0.7 + r * 1.2 + s * 1.6);
}

// ═══ CHUNK: symmetry-fold (OWNER: hop-2) ═════════════════════════════════════

fn applySymmetry(p: vec2<f32>) -> vec2<f32> {
    // OWNER: cursor-hop-2 2026-07-19
    // Polar kaleidoscope fold: fixed 6-fold mandala, slow time spin, mouse-centers when held.
    var q = p;

    // Slow pre-rotation so the fold breathes instead of locking static.
    let spin = u.config.x * 0.04;
    let cs = cos(spin);
    let sn = sin(spin);
    q = vec2<f32>(cs * q.x - sn * q.y, sn * q.x + cs * q.y);

    // Pull fold origin toward cursor while mouse is held (no zoom_params steal).
    if (u.zoom_config.w > 0.5) {
        let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
        q -= mouse * 0.35;
    }

    let segments: f32 = 6.0;
    let angle = atan2(q.y, q.x);
    let radius = length(q);
    let segmentAngle = TAU / segments;
    let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
    return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}

// ═══ CHUNK: palette (OWNER: hop-3) — sole RGB assignment site ══════════════

fn sampleField(p: vec2<f32>, time: f32) -> f32 {
    // OWNER: kimi-hop-3 2026-07-19
    // Base fbm layer + finer ridged layer so the kaleidoscope folds pick up vein detail.
    let drift = vec2<f32>(sin(time * 0.07), cos(time * 0.05)) * 0.3;
    let base = fbm(p * 2.4 + drift, 4);
    let ridge = 1.0 - abs(2.0 * fbm(p * 4.8 - drift * 1.6, 3) - 1.0);
    return clamp(mix(base, ridge, 0.3), 0.0, 1.0);
}

// Chunk-local IQ cosine palette helper (hop 3).
fn iqPalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(TAU * (c * t + d));
}

fn applyPalette(field: f32, time: f32, saturation: f32, hueShift: f32) -> vec3<f32> {
    // OWNER: kimi-hop-3 2026-07-19
    // Hybrid: psychedelicPalette base + IQ cosine interference bands at a slower phase.
    let t = field + time * 0.06 + hueShift * TAU;
    let base = psychedelicPalette(t);
    let bands = iqPalette(
        t * 0.5 + field * 0.7,
        vec3<f32>(0.5, 0.5, 0.5),
        vec3<f32>(0.5, 0.5, 0.5),
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    var color = mix(base, bands, 0.45);
    let gray = vec3<f32>(dot(color, vec3<f32>(0.2126, 0.7152, 0.0722)));
    color = mix(gray, color, clamp(saturation, 0.0, 1.0));
    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.2));
}

// ═══ CHUNK: temporal-feedback (OWNER: hop-4) ═════════════════════════════════

fn applyTemporalFeedback(
    color: vec3<f32>,
    coord: vec2<i32>,
    res: vec2<f32>,
    strength: f32,
    bass: f32,
    time: f32,
) -> vec3<f32> {
    // OWNER: cursor-hop-4 2026-07-19
    // Self-advecting echo trails: organic UV warp on history + stable decay blend.
    let uv01 = (vec2<f32>(coord) + 0.5) / res;

    // Warp the history sample UV — trails smear instead of stacking in place.
    let drift = organicDrift(uv01, time, 5.0) * (0.012 + strength * 0.018 + bass * 0.008);
    let fbUV = clamp(uv01 + drift, vec2<f32>(0.0), vec2<f32>(1.0));
    let fbUV2 = clamp(uv01 - drift * 0.65, vec2<f32>(0.0), vec2<f32>(1.0));

    // Bilinear history taps for soft phosphor echo (dataTextureC → prior frame).
    let prevA = textureSampleLevel(dataTextureC, u_sampler, fbUV, 0.0).rgb;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, fbUV2, 0.0).rgb;
    let prev = (prevA + prevB) * 0.5;

    // Trail Echo slider drives mix; bass nudges persistence.
    let fbMix = clamp(strength * 0.82 + bass * 0.04, 0.0, 0.85);

    // Decay stays < 1.0 so feedback remains stable after long runs.
    let decay = clamp(0.86 + strength * 0.10 + bass * 0.02, 0.0, 0.97);
    let decayed = prev * decay;

    // Luminance-weighted echo: bright trails linger slightly longer.
    let prevLuma = dot(decayed, vec3<f32>(0.2126, 0.7152, 0.0722));
    let echoWeight = fbMix * (0.75 + 0.25 * prevLuma);

    return mix(color, decayed, echoWeight);
}

// ─── ENTRY ───────────────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) {
        return;
    }

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let motion = motionModulate(time, bass, mids);
    let animTime = time * motion.timeScale;

    var p = aspectUv(coord, res);
    p = applyDomainWarp(p, animTime, motion.warpStrength);
    p = applySymmetry(p);

    let field = sampleField(p, animTime);
    let paletteSat = clamp(mix(0.55, 1.0, u.zoom_params.y) * motion.saturationBoost, 0.0, 1.0);
    let paletteHue = fract(u.zoom_params.z + motion.hueDrift);
    var color = applyPalette(field, animTime, paletteSat, paletteHue);

    color = applyTemporalFeedback(color, coord, res, u.zoom_params.w * 0.35, bass, animTime);

    color = finalComposite(color, 1.05 * motion.pulse);

    let alpha = clamp(0.35 + dot(color, vec3<f32>(0.299, 0.587, 0.114)) * 0.65, 0.0, 1.0);
    let outColor = vec4<f32>(color, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    let uv01 = (vec2<f32>(coord) + 0.5) / res;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
