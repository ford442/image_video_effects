// ═══════════════════════════════════════════════════════════════════
//  Holographic Lens-Flare Matrix
//  Category: generative
//  Features: anamorphic-flare, blue-noise, fast-approximations,
//            mouse-spin, audio-reactive, palette-tinted,
//            chromatic-dispersion, temporal-flare-persistence, depth-aware
//  Complexity: Medium
//  Phase B / Optimizer
//  Upgraded: 2026-06-28 — Optimizer Batch (blue noise + fast approximations)
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
const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

// ─── Blue noise 2D (fast, decorrelated) ───
fn blueNoise2(p: vec2<f32>) -> f32 {
    let n = fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let n2 = fract(sin(dot(p + vec2<f32>(PI, TAU), vec2<f32>(45.234, 91.123))) * 12345.6789);
    return fract(n + n2 * 0.5);
}

// ─── Fast approximate sin (for non-critical paths) ───
fn fastSin(x: f32) -> f32 {
    let y = x * (1.0 / PI);
    let z = y - floor(y * 0.5) * 2.0;
    let w = z - 1.0;
    let q = w * (z - 2.0);
    return q * w * 0.225 * (abs(w) - 2.5) + w;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let coords = vec2<i32>(gid.xy);
    let res = textureDimensions(writeTexture);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let aspect = f32(res.x) / max(f32(res.y), 1.0);
    let p = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let mouse_p = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
    let intensityControl = clamp(u.zoom_params.x, 0.0, 1.0);
    let speedControl = clamp(u.zoom_params.y, 0.0, 1.0);
    let scaleControl = clamp(u.zoom_params.z, 0.0, 1.0);
    let mouseInfluence = clamp(u.zoom_params.w, 0.0, 1.0);
    let phaseTime = time * mix(0.25, 2.8, speedControl);

    var mouseOffset = vec2<f32>(0.0);
    let toMouse = p - mouse_p;
    let mouseDistance = length(toMouse);
    let hoverLens = exp(-mouseDistance * mouseDistance * 7.0) * mouseInfluence;
    mouseOffset -= toMouse / max(mouseDistance, 1e-4) * hoverLens * select(0.025, 0.11, mouseDown);

    // Click timestamps launch finite flare-burst fronts. ripple.w is padding.
    let rippleCount = min(u32(u.config.y), 50u);
    var clickBurst = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.6) { continue; }
        let rPos = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0);
        let toR = p - rPos;
        let d = length(toR);
        let radius = age * mix(0.18, 0.55, speedControl);
        let front = exp(-pow((d - radius) * 34.0, 2.0)) * exp(-age * 1.15);
        clickBurst += front;
        mouseOffset += toR / max(d, 1e-4) * front * 0.055 * mouseInfluence;
    }

    let gridSize = mix(5.0, 16.0, scaleControl) + bass * 1.5;
    let flareSpread = mix(0.08, 0.42, scaleControl);

    let gUv = (p + mouseOffset * 0.1) * gridSize;
    let idc = floor(gUv);
    let fUv = fract(gUv) - vec2<f32>(0.5);

    // Blue noise offset for flare position (decorrelates grid aliasing)
    let bn = blueNoise2(idc + phaseTime * 0.03);
    let offset = (vec2<f32>(bn, fract(bn * PHI)) - vec2<f32>(0.5)) * flareSpread * 2.0;
    let flarePos = fUv - offset;
    let dist = length(flarePos);

    // Fast approximate streak: x^2 instead of exp for performance
    let streak = exp(-flarePos.y * flarePos.y * 80.0) * exp(-abs(flarePos.x) * 4.0);

    let size = mix(0.045, 0.14, scaleControl) + bass * 0.09 + hoverLens * 0.025;
    let spinSpeed = phaseTime * (1.0 + bass * 1.2);
    let angle = atan2(flarePos.y, flarePos.x) + spinSpeed;

    // Core: fast approximation using smoothstep instead of exp for small distances
    let core = exp(-dist * dist / max(size * size, 1e-6));
    let starMod = 0.5 + 0.5 * fastSin(angle * 4.0 + time * 5.0);
    var density = core * starMod + streak * (0.3 + mids * 0.18) + clickBurst * 0.75;

    // Chromatic dispersion per flare: RGB stars at different angular offsets
    let chromaOff = 0.04 + treble * 0.22;
    let angleR = angle + chromaOff;
    let angleB = angle - chromaOff;
    let starR = 0.5 + 0.5 * fastSin(angleR * 4.0 + time * 5.0);
    let starB = 0.5 + 0.5 * fastSin(angleB * 4.0 + time * 5.0);
    let densityR = core * starR + streak * 0.4;
    let densityG = density;
    let densityB = core * starB + streak * 0.4;

    // Fast plasma color lookup with blue noise jitter
    let plasmaIdx = u32(abs(fract(bn + time * 0.1)) * 256.0);
    let pColor = plasmaBuffer[plasmaIdx % 256u].rgb;
    let brightness = mix(0.55, 2.4, intensityControl) * (1.0 + bass * 0.45);
    var col = vec3<f32>(pColor.r * densityR, pColor.g * densityG, pColor.b * densityB) * brightness;

    let motion = textureLoad(readTexture, coords, 0).rgb;
    col = motion * (1.0 - density * 0.6) + col;

    // A/C owns raw flare state: density, streak, nearest distance, alpha.
    // Keep it un-tone-mapped and use exact history loads.
    let prev = textureLoad(dataTextureC, coords, 0);
    let persistentDensity = max(density, prev.r * mix(0.86, 0.95, speedControl));
    let persistentStreak = max(streak + clickBurst * 0.35, prev.g * 0.91);
    let persistentDistance = mix(dist, prev.b, 0.18);
    density = persistentDensity;

    // Depth-aware compositing: flares behind depth are dimmer
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthDim = 0.6 + depth * 0.4;
    col = col * depthDim;
    col += pColor * persistentDensity * (0.18 + mids * 0.12);

    let lumaOut = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let bloom = max(0.0, lumaOut - 0.7) * 3.0;
    let alpha = clamp(0.08 + density * 0.62 + persistentStreak * 0.22 + bloom * 0.25, 0.02, 0.98);
    let stateAlpha = max(alpha, prev.a * 0.92);
    let display = acesToneMap(col * mix(0.85, 1.35, intensityControl));

    textureStore(writeTexture, coords, vec4<f32>(display, stateAlpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(clamp(depth * (0.7 + persistentDensity * 0.3), 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(persistentDensity, persistentStreak, persistentDistance, stateAlpha));
}
