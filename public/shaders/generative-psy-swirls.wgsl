// ═══════════════════════════════════════════════════════════════════
//  Generative Psy Swirls
//  Category: generative
//  Features: audio-reactive, mouse-interactive, psychedelic, chromatic, temporal-layer-memory,
//            upgraded-rgba, aces-tone-map, chromatic-hue-separation, audio-twist,
//            domain-warped-swirl, mids-hue-fan, feedback-clamp
//  Complexity: High
//  Upgraded: 2026-08-03, 2026-11-09 (Batch 34: sprung interaction, guarded ripples,
//            non-filtering feedback loads, generated relief depth)
//  Ideas: arm-wound hue (spectrum winds with the polar arms); Rankine eye-wall cores
//         (calm eye + bright wall instead of a pinwheel singularity)
//  Rescue: cursor glide kept in A texel (0,0) (extraBuffer[133..138] is re-uploaded zero
//          every frame, so the old spring never persisted)
//  A packing: raw trail colour (clamp 1.2, pre-ACES, C read as colour);
//             texel (0,0) = (glide.xy, 7, fract(time))
//  Shared by presets: generative-psy-swirls + psy-swirls (same WGSL, same four slots)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ── Value noise & fbm for the swirl domain warp ───────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),                       hash21(i + vec2<f32>(1.0, 0.0)), s.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x),
        s.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// One swirl arm layer in polar space. hueShift fans the layer's hue
// rotation so mids energy spreads layers into rainbow fringes.
fn layeredSwirlLayer(uv: vec2<f32>, time: f32, twist: f32, freq: f32,
                     offset: vec2<f32>, hueShift: f32) -> vec3<f32> {
    let d = length(uv - offset);
    let a = atan2(uv.y - offset.y, uv.x - offset.x);
    let wound = a + d * twist * freq;            // spatial part of the arm phase
    let swirl = wound - time * 0.5;
    let arm = sin(swirl * 3.0) * 0.5 + 0.5;
    let distRipple = sin(d * 10.0 - time * 2.0) * 0.5 + 0.5;

    // ── Idea 2: Rankine eye-wall core ────────────────────────────────
    // A real vortex has a finite calm eye ringed by its fastest wall; HEAD's
    // centre is a bare atan2 pinwheel point. Tighter twist -> tighter eye.
    let coreR = 0.05 + 0.07 / (1.0 + max(twist, 0.0) * 0.5);
    let eye = smoothstep(coreR * 0.45, coreR, d);
    let wallX = (d - coreR * 1.25) / (coreR * 0.35);
    let wall = exp(-wallX * wallX);
    let val = min(arm * distRipple * eye + wall * 0.5, 1.0);

    // ── Idea 1: arm-wound hue ────────────────────────────────────────
    // The spectrum follows the polar arms (one full wrap per turn). wound/TAU
    // jumps by exactly 1.0 across the atan2 seam, so fract() stays continuous.
    // The existing hue drift in time is untouched.
    let hue = fract(d * 0.5 + time * 0.1 + hueShift + wound / TAU);
    return hsv2rgb(vec3<f32>(hue, 0.8, val));
}

// ── Rescue R1: cursor glide in A texel (0,0) ─────────────────────────
// extraBuffer[133..] is re-uploaded zeroed every frame, so the old spring could
// never persist (every pixel fell back to the raw cursor). State = A(0,0) =
// (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel reads the same C texel
// and integrates the same step, only pixel (0,0) stores it. First-order glide
// replacing a dead critically-damped spring: at rest identical, moving the swirl
// centres lag the cursor by ~1/rate s.
const GLIDE_MARK: f32 = 7.0;
fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
    let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w < 1.0;
    let dt = clamp(fract(time - st.w), 0.001, 0.05);
    let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
    let snapped = select(g, raw, length(raw - g) < 0.003);
    return select(raw, snapped, ok);
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
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let coord = vec2<i32>(global_id.xy);

    // ── Sliders (saved-preset contract: ids/defaults unchanged) ──
    // twist          -> vortex twist strength (bass adds a kick)
    // layers         -> number of stacked swirl layers
    // frequency      -> polar arm frequency + domain warp scale
    // depthReduction -> how much scene depth flattens the twist
    let twist = u.zoom_params.x * 4.0 * (1.0 + bass * 0.3);
    let layers = u.zoom_params.y * 5.0 + 2.0;
    let freq = u.zoom_params.z * 2.0 + 0.5;
    let depthReduction = u.zoom_params.w;

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let adjustedTwist = twist * (1.0 - depth * depthReduction);

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let mouse = glideStep(glideState, rawMouse, time, 8.0);
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let m = (mouse - 0.5) * vec2<f32>(aspect, 1.0);

    // ── Domain warp: fbm offset bends the swirl arms so they ──────
    // breathe instead of rotating rigidly. Frequency slider scales
    // the warp field; treble adds shimmer to the warp drift.
    let warpScale = 1.5 + freq * 1.5;
    let warpDrift = vec2<f32>(time * 0.11, -time * 0.08) * (1.0 + treble * 0.2);
    let warp = vec2<f32>(
        fbm(p * warpScale + warpDrift, 3),
        fbm(p * warpScale * 1.37 + vec2<f32>(5.2, 1.3) - warpDrift.yx, 3)
    );
    let warpStrength = 0.10 + u.zoom_params.z * 0.10 + bass * 0.03;
    p = p + (warp - vec2<f32>(0.5)) * warpStrength;

    // ── Multi-layer swirl with mids-driven chromatic hue fan ──────
    var rLayer = vec3<f32>(0.0);
    var gLayer = vec3<f32>(0.0);
    var bLayer = vec3<f32>(0.0);
    for (var i: i32 = 0; i < i32(layers); i = i + 1) {
        let fi = f32(i);
        let offset = m * fi * 0.1 + vec2<f32>(
            sin(time * 0.3 + fi * 1.2) * 0.1,
            cos(time * 0.2 + fi * 0.8) * 0.1
        );
        // Per-layer hue stagger grows with mids: layers fan out into
        // rainbow fringes on musical peaks.
        let hueFan = fi * mids * 0.06;
        rLayer += layeredSwirlLayer(p, time, adjustedTwist, freq + fi * 0.2 + treble * 0.1,
                                    offset + vec2<f32>(fi * 0.02, 0.0), hueFan + mids * 0.10);
        gLayer += layeredSwirlLayer(p, time, adjustedTwist, freq + fi * 0.2,
                                    offset, hueFan * 0.5);
        bLayer += layeredSwirlLayer(p, time, adjustedTwist, freq + fi * 0.2 - bass * 0.1,
                                    offset - vec2<f32>(fi * 0.02, 0.0), hueFan - mids * 0.10);
    }
    let invLayers = 1.0 / layers;
    rLayer *= invLayers;
    gLayer *= invLayers;
    bLayer *= invLayers;

    var color = vec3<f32>(rLayer.r, gLayer.g, bLayer.b);

    var clickSwirl = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rp = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0);
        let rd = length(p - rp);
        let rt = time - ripple.z;
        if (rt >= 0.0 && rt < 1.7) {
            let ring = exp(-abs(rd - rt * 0.26) * 72.0) * exp(-rt * 1.7);
            clickSwirl = max(clickSwirl, ring);
        }
    }
    color += vec3<f32>(0.5, 0.3, 0.9) * clickSwirl * (0.35 + treble * 0.18);

    // ── Temporal swirl layer accumulation: previous color fades ───
    // in for trails. FEEDBACK CLAMP: the memory write is clamped
    // pre-tint at 1.2 (luma-echo-warp lesson) so accumulated color
    // can never blow up across frames.
    // texel (0,0) of C holds the glide state, not colour: use the live colour there.
    let isGlideTexel = global_id.x == 0u && global_id.y == 0u;
    let prev = select(textureLoad(dataTextureC, coord, 0).rgb, color, isGlideTexel);
    let trail = mix(color, prev * 0.92, 0.04 + mids * 0.02);
    let trailClamped = clamp(trail, vec3<f32>(0.0), vec3<f32>(1.2));
    let trailTinted = trailClamped * vec3<f32>(0.98, 0.99, 1.02);
    let trailOut = vec4<f32>(min(trailTinted, vec3<f32>(1.2)), 1.0);
    textureStore(dataTextureA, coord,
                 select(trailOut, vec4<f32>(mouse, GLIDE_MARK, fract(time)), isGlideTexel));

    color = mix(color, prev * 0.92, 0.04 + mids * 0.02);

    let reliefDepth = clamp(length(color) * 0.42 + clickSwirl * 0.16, 0.0, 1.0);
    let alpha = clamp(length(color) * 0.72 + bass * 0.05 + clickSwirl * 0.12, 0.0, 0.96);

    color = acesToneMap(color * 1.1);
    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(reliefDepth, 0.0, 0.0, 0.0));
}
