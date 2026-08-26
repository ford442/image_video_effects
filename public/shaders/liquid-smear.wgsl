// ═══════════════════════════════════════════════════════════════════════════════
//  Liquid Smear — Pointer-Velocity Pigment Drag
//  Category: liquid-effects
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, spring-damper-pointer, velocity-smear,
//            pigment-diffusion, depth-aware, upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
// ═══════════════════════════════════════════════════════════════════════════════
//  Two structures replace the original "pull toward the cursor" offset:
//
//    1. Velocity smear from a spring-damped pointer — the smoothed cursor and
//       its velocity live in extraBuffer[133..136] (position xy, velocity xy),
//       written by invocation (0,0) only. The smear direction is now the
//       pointer's actual travel direction with its speed as the drag length,
//       so flicking the cursor rakes pigment along the stroke. The old code had
//       no velocity at all — it always pulled toward the cursor centre, which
//       reads as a sink, not a brush.
//
//    2. Per-band FFT pigment diffusion — the smeared field is blurred along the
//       stroke normal by a kernel whose width comes from the local FFT bin, so
//       loud bands bleed pigment sideways while quiet ones keep crisp streaks.
//
//  Also fixed: the shader had NO bounds guard (it wrote past the render target
//  on non-multiple-of-16 resolutions), and it read dataTextureC through the
//  FILTERING sampler. dataTextureC is rgba32float and `float32-filterable` is
//  only requested when the adapter offers it (src/renderer/webgpu/device.ts),
//  so that read is invalid on devices without the feature. History is now
//  fetched with exact textureLoad, bilinear-interpolated by hand where the
//  advection offset is sub-pixel.
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=SmearStrength, y=BrushSize, z=Persistence, w=MixStrength
  ripples: array<vec4<f32>, 50>,
};

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  let m = clamp(1.0 - cosTheta, 0.0, 1.0);
  let m2 = m * m;
  return F0 + (1.0 - F0) * m2 * m2 * m;
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Exact float32 history fetch with hand-rolled bilinear — dataTextureC must
// never go through the filtering sampler (see header).
fn historyBilinear(p: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
    let maxC = dims - vec2<i32>(1);
    let f = fract(p);
    let i0 = vec2<i32>(floor(p));
    let s00 = textureLoad(dataTextureC, clamp(i0, vec2<i32>(0), maxC), 0);
    let s10 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0);
    let s01 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
    let s11 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0);
    return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dimsI);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Params ───────────────────────────────────────────────────────────────
    let smearStrength = 0.1 + (u.zoom_params.x * 0.9);
    let brushSize = 0.05 + (u.zoom_params.y * 0.2);
    let decayRate = 0.9 + (u.zoom_params.z * 0.095);
    let mixStrength = 0.1 + (u.zoom_params.w * 0.9);

    // ── Structure 1: spring-damped pointer + velocity ────────────────────────
    // extraBuffer[133..134] = smoothed position, [135..136] = smoothed velocity.
    // Only invocation (0,0) writes, as the house pattern requires.
    let rawMouse = u.zoom_config.yz;
    if (global_id.x == 0u && global_id.y == 0u) {
        var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        if (sm.x == 0.0 && sm.y == 0.0) { sm = rawMouse; }
        let dt = 0.016;
        let k = 1.0 - exp(-9.0 * dt);
        let next = sm + (rawMouse - sm) * k;
        let vel = (next - sm) / dt;
        var smoothVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        smoothVel = mix(smoothVel, vel, 0.25);
        extraBuffer[133] = next.x;
        extraBuffer[134] = next.y;
        extraBuffer[135] = smoothVel.x;
        extraBuffer[136] = smoothVel.y;
    }
    let mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let held = step(0.5, u.zoom_config.w);

    let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(toMouse);
    let brushFalloff = 1.0 - smoothstep(0.0, brushSize, dist);

    // Drag along the pointer's actual travel, not toward its centre.
    let speed = length(mouseVel);
    let strokeDir = select(vec2<f32>(0.0), mouseVel / max(speed, 1e-5), speed > 1e-4);
    let dragLen = clamp(speed * 0.02, 0.0, 0.06) * smearStrength * (0.5 + held);
    var offset = strokeDir * dragLen * brushFalloff;

    // ── Bounded click splats ─────────────────────────────────────────────────
    var splat = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.2) {
            let rDelta = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
            let r = max(length(rDelta), 1e-4);
            let front = r - age * 0.42;
            let env = exp(-front * front * 150.0) * exp(-age * 1.5);
            offset += (rDelta / r) * env * smearStrength * 0.03;
            splat += env;
        }
    }
    splat = min(splat, 1.5);

    // ── Structure 2: per-band FFT pigment diffusion ──────────────────────────
    // Band chosen by position so different regions bleed with different bins;
    // the blur runs along the stroke NORMAL, spreading pigment sideways.
    let bandIdx = u32(clamp((uv.x * 0.5 + uv.y * 0.5) * 8.0, 0.0, 7.999));
    let band = plasmaBuffer[bandIdx + 1u].x;
    let bleed = (0.4 + band * 3.2 + mids * 0.8) * (0.5 + smearStrength);
    let normalDir = vec2<f32>(-strokeDir.y, strokeDir.x);

    let basePx = (uv - offset) * resolution;
    let bleedPx = normalDir * bleed;
    let h0 = historyBilinear(basePx, dimsI);
    let h1 = historyBilinear(basePx + bleedPx, dimsI);
    let h2 = historyBilinear(basePx - bleedPx, dimsI);
    let h3 = historyBilinear(basePx + bleedPx * 2.0, dimsI);
    let h4 = historyBilinear(basePx - bleedPx * 2.0, dimsI);
    // Gaussian-ish 5-tap along the normal.
    var smeared = h0 * 0.38 + (h1 + h2) * 0.24 + (h3 + h4) * 0.07;

    let currentInput = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Cold start: an empty history seeds from the live plate.
    if (smeared.a <= 0.0001) { smeared = currentInput; }

    // Fresh input keeps bleeding in so the field never degenerates; clicks and
    // the brush core inject extra fresh pigment.
    let refresh = clamp(splat * 0.5 + brushFalloff * held * 0.4, 0.0, 0.9);
    let keep = decayRate * (1.0 - refresh);
    let blend = mix(currentInput, smeared, keep);

    // ── Colour ───────────────────────────────────────────────────────────────
    var color = mix(currentInput.rgb, blend.rgb, mixStrength);
    color += vec3<f32>(0.02, 0.01, 0.0) * smearStrength;
    color += vec3<f32>(1.0, 0.86, 0.7) * splat * 0.25 * (1.0 + bass * 0.6);
    color += vec3<f32>(0.25, 0.45, 0.8) * brushFalloff * held * (0.15 + treble * 0.35);
    color = acesFilm(color);

    // ── Semantic alpha ───────────────────────────────────────────────────────
    let normal = normalize(vec3<f32>(offset * 40.0, 1.0));
    let fresnel = schlickFresnel(max(0.0, normal.z), 0.02);
    let thickness = smearStrength * 2.0 * brushFalloff + 0.2;
    let absorption = exp(-thickness);
    let baseAlpha = mix(0.4, mix(0.7, 0.95, decayRate), absorption);
    let pigment = clamp(brushFalloff * 0.5 + splat * 0.6 + length(offset) * 12.0, 0.0, 1.0);
    let alpha = clamp(mix(currentInput.a * baseAlpha, 1.0, pigment) * (1.0 - fresnel * 0.2), 0.0, 1.0);

    let outColor = vec4<f32>(color, alpha);
    textureStore(writeTexture, coord, outColor);
    // A carries the smeared field forward — it becomes next frame's C.
    textureStore(dataTextureA, coord, vec4<f32>(blend.rgb, max(alpha, 0.02)));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
