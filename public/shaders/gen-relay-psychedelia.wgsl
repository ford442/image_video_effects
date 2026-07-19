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
}

fn motionModulate(time: f32, bass: f32, mids: f32) -> MotionState {
    let pulse = 0.85 + 0.15 * sin(time * (1.2 + bass * 0.5));
    let warpStrength = mix(0.12, 0.38, clamp(u.zoom_params.x, 0.0, 1.0)) * pulse;
    let timeScale = 1.0 + mids * 0.15;
    return MotionState(warpStrength, timeScale, pulse);
}

// ═══ CHUNK: domain-warp (OWNER: hop-1) ═══════════════════════════════════════

fn applyDomainWarp(p: vec2<f32>, time: f32, strength: f32) -> vec2<f32> {
    // Spine: single-level warp. Hop 1: recursive fbm(p + fbm(p + fbm(p))).
    let drift = organicDrift(p, time, 6.0) * strength;
    let q = p + drift;
    let field = fbm(q * 1.8 + vec2<f32>(time * 0.04, -time * 0.03), 3);
    return q + vec2<f32>(field - 0.5, fbm(q * 2.1 - time * 0.02, 2) - 0.5) * strength * 0.35;
}

// ═══ CHUNK: symmetry-fold (OWNER: hop-2) ═════════════════════════════════════

fn applySymmetry(p: vec2<f32>) -> vec2<f32> {
    // Spine: identity. Hop 2: polar/kaleidoscope fold before field sampling.
    return p;
}

// ═══ CHUNK: palette (OWNER: hop-3) — sole RGB assignment site ══════════════

fn sampleField(p: vec2<f32>, time: f32) -> f32 {
    return fbm(p * 2.4 + vec2<f32>(sin(time * 0.07), cos(time * 0.05)) * 0.3, 4);
}

fn applyPalette(field: f32, time: f32, saturation: f32, hueShift: f32) -> vec3<f32> {
    let t = field + time * 0.06 + hueShift * TAU;
    var color = psychedelicPalette(t);
    let gray = vec3<f32>(dot(color, vec3<f32>(0.2126, 0.7152, 0.0722)));
    return mix(gray, color, clamp(saturation, 0.0, 1.0));
}

// ═══ CHUNK: temporal-feedback (OWNER: hop-4) ═════════════════════════════════

fn applyTemporalFeedback(color: vec3<f32>, prevRgb: vec3<f32>, strength: f32, bass: f32) -> vec3<f32> {
    let fb = clamp(strength + bass * 0.04, 0.0, 0.85);
    let decayed = prevRgb * 0.94;
    return mix(color, decayed, fb);
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
    var color = applyPalette(field, animTime, mix(0.55, 1.0, u.zoom_params.y), u.zoom_params.z);

    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    color = applyTemporalFeedback(color, prev, u.zoom_params.w * 0.35, bass);

    color = finalComposite(color, 1.05 * motion.pulse);

    let alpha = clamp(0.35 + dot(color, vec3<f32>(0.299, 0.587, 0.114)) * 0.65, 0.0, 1.0);
    let outColor = vec4<f32>(color, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    let uv01 = (vec2<f32>(coord) + 0.5) / res;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
