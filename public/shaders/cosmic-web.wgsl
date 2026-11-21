// ═══ Cosmic Web Filament ═══════════════════════════════════════════
//  Category: generative
//  Features: mouse-driven, organic, temporal, audio-reactive, depth-aware,
//            aces-tone-map, chromatic-aberration, alpha-layered
//  Complexity: High
//  Upgraded: 2026-11-21
//  Ideas: junction clusters where filaments swell into F3-F1 nodes; golden-angle galaxy groups (Vogel spiral, §12.2E) stretched along the local filament tangent
//  A packing: pre-ACES HDR temporal colour + temporal alpha (read back as colour history); ACES on writeTexture only
//  Rescues: compile errors (__finalRGB, redeclared rippleCount/aspect) and the stamped clock-ring/IQ-palette tail removed; node mask moved from void cores to Voronoi junctions
//  Batch 17 upgrade:
//   - void path routed through the SAME temporal feedback mix as filaments
//     (no early-exit shimmer at filament edges)
//   - per-octave spectrum: filament octave o follows plasmaBuffer[(o % 8) + 1].x
//     (large structure rides bass bins, fine structure rides treble bins)
//   - critically-damped spring-damper gravity well (extraBuffer[133..136])

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const BASE_FREQ: f32 = 3.0;
const TIME_SCALE: f32 = 0.1;
const FILAMENT_SHARP: f32 = 10.0;
const FILAMENT_BIAS: f32 = 0.05;
const VOID_CUTOFF: f32 = 0.03;
const GALAXY_SCALE: f32 = 38.0;
const GALAXY_THRESH: f32 = 0.55;
const NODE_THRESHOLD: f32 = 0.22;   // junction width: F3 - F1 below this = a node (was an f1 core mask)
const DECAY: f32 = 0.96;
const FEEDBACK: f32 = 0.25;
const JUNCTION_SWELL: f32 = 0.10;    // border reduction at a junction: filaments swell into clusters
const GROUP_SATS: i32 = 4;           // satellite galaxies per host (golden-angle / Vogel layout)
const GOLDEN_ANGLE: f32 = 2.39996323;

// Filament octave stack (numerically tuned with FILAMENT_SHARP/BIAS above)
const FILAMENT_OCTAVES: i32 = 3;
const OCTAVE_AMP_SUM: f32 = 1.75;    // 1 + 0.5 + 0.25 amplitude normalization
const OCTAVE_BIN_BASE: f32 = 0.75;   // audio floor so silence keeps structure
const OCTAVE_BIN_GAIN: f32 = 0.5;    // audio gain per octave bin

// Spring-damper gravity well (critically damped, extraBuffer[133..136])
const SPRING_FREQ: f32 = 6.0;        // natural frequency (rad/s)
const SPRING_DT: f32 = 0.016;        // first-frame fallback step

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// Branchless Voronoi F1/F2
fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var f1 = 1.0;
    var f2 = 1.0;
    for (var k = -1; k <= 1; k = k + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            for (var i = -1; i <= 1; i = i + 1) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g + o - f;
                let d = dot(r, r);
                let b1 = f32(d < f1);
                let b2 = f32(d < f2) * (1.0 - b1);
                f2 = mix(f2, mix(f1, d, b2), b1 + b2);
                f1 = mix(f1, d, b1);
            }
        }
    }
    return vec2<f32>(sqrt(f1), sqrt(f2));
}

// Voronoi with F3 and the wall normal. Same 27-cell loop and the same F1/F2
// caps as voronoi3 (so the base octave is unchanged); additionally keeps the
// third-nearest distance (junction detector) and r2-r1, the direction between
// the two nearest seeds, which is the wall normal -> filament tangent.
struct VoroX {
    f: vec3<f32>,   // (F1, F2, F3)
    n: vec2<f32>,   // unit wall normal in the screen slice (xy of r2 - r1)
};

fn voronoi3x(p: vec3<f32>) -> VoroX {
    let n = floor(p);
    let f = fract(p);
    var d1 = 1.0;
    var d2 = 1.0;
    var d3 = 3.0;
    var r1 = vec3<f32>(1.0, 0.0, 0.0);
    var r2 = vec3<f32>(0.0);
    for (var k = -1; k <= 1; k = k + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            for (var i = -1; i <= 1; i = i + 1) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g + o - f;
                let d = dot(r, r);
                let lt1 = d < d1;
                let lt2 = d < d2;
                let lt3 = d < d3;
                d3 = select(select(d3, d, lt3), d2, lt2);
                d2 = select(select(d2, d, lt2), d1, lt1);
                r2 = select(select(r2, r, lt2), r1, lt1);
                r1 = select(r1, r, lt1);
                d1 = select(d1, d, lt1);
            }
        }
    }
    let nrm = (r2 - r1).xy;
    let nl = length(nrm);
    return VoroX(vec3<f32>(sqrt(d1), sqrt(d2), sqrt(d3)),
                 select(vec2<f32>(1.0, 0.0), nrm / max(nl, 1e-4), nl > 1e-4));
}

// 3-octave FBM over 3D Voronoi (domain warp only — filament stack is below)
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i = 0; i < 3; i = i + 1) {
        v += a * voronoi3(pp).x;
        pp = pp * 2.0 + vec3<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735);
    let s = sin(shift);
    let c = cos(shift);
    return color * c + cross(k, color) * s + k * dot(k, color) * (1.0 - c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(color.r * (1.0 + shift.x * 0.8), color.g, color.b * (1.0 - shift.y * 0.5));
}

fn filamentDensity(border: f32, scale: f32) -> f32 {
    let f = 1.0 / (border * FILAMENT_SHARP + FILAMENT_BIAS);
    return smoothstep(0.0, 1.0, f * scale);
}

// Multi-factor alpha for the 3-slot compositor
fn compositeAlpha(color: vec3<f32>, density: f32, galaxy: f32, node: f32, depth: f32) -> f32 {
    let lumaKey = smoothstep(0.03, 0.24, luma(color));
    let edgePreserve = smoothstep(0.0, 0.28, density) * (1.0 - smoothstep(0.78, 0.96, density) * 0.5);
    let depthLayer = mix(0.25, 1.0, depth);
    let base = clamp(density * 0.9 + galaxy * 0.55 + node * 0.65, 0.0, 1.0);
    return clamp(base * lumaKey * edgePreserve * depthLayer, 0.0, 0.98);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let aspect = res.x / res.y;
    var uv = (uv01 - 0.5) * vec2<f32>(aspect, 1.0) + 0.5;

    // Slider wiring (saved-preset contract — ids/defaults unchanged):
    //   x = Warp Strength, y = Filament Density, z = Flow Speed, w = Color Shift
    let warpStrength = u.zoom_params.x;
    let densityScale = u.zoom_params.y;
    let time = u.config.x * u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    var prev = textureLoad(dataTextureC, pixel, 0);

    // ── Spring-damper gravity well ────────────────────────────────
    // Critically-damped spring eases the well center toward the cursor so the
    // gravity lags organically. Persistent state (safe zone [133..255]):
    //   extraBuffer[133/134] = smoothed well position (aspect-corrected uv)
    //   extraBuffer[135/136] = spring velocity
    let rawMouse = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0) + 0.5;
    var wellPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var wellVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let springInitialized = extraBuffer[137] >= 0.5;
    // Explicit init makes top-left a valid cursor target instead of a sentinel.
    if (!springInitialized) {
        wellPos = rawMouse;
        wellVel = vec2<f32>(0.0);
    }
    let springDt = select(SPRING_DT, clamp(u.config.x - extraBuffer[138], 0.0005, 0.05), springInitialized);
    // Critical damping: accel = w²·(target − pos) − 2w·vel
    let springAccel = SPRING_FREQ * SPRING_FREQ * (rawMouse - wellPos)
                    - 2.0 * SPRING_FREQ * wellVel;
    wellVel += springAccel * springDt;
    wellPos += wellVel * springDt;
    // Single invocation commits the shared spring state (benign 1-frame lag)
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = wellPos.x;
        extraBuffer[134] = wellPos.y;
        extraBuffer[135] = wellVel.x;
        extraBuffer[136] = wellVel.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = u.config.x;
    }

    // Mouse gravity well — branchless normalization
    let toMouse = wellPos - uv;
    let distMouse = length(toMouse);
    let dirToMouse = select(vec2<f32>(0.0), toMouse / distMouse, distMouse > 0.001);
    uv += dirToMouse * (0.3 * smoothstep(0.8, 0.0, distMouse));

    // Held pointer winds an accretion disk around the gravity well; clicks
    // launch alternating compressive waves through the filament network.
    let wellAngle = atan2(toMouse.y, toMouse.x);
    let held = select(0.35, 1.0, u.zoom_config.w > 0.5);
    let accretionEnvelope = exp(-distMouse * distMouse * 12.0) * held;
    let accretion = pow(abs(sin(wellAngle * 7.0 + distMouse * 54.0 - u.config.x * 3.2)), 12.0)
        * accretionEnvelope;
    var clickWave = 0.0;
    var clickFlow = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = u.config.x - ripple.z;
        if (age >= 0.0 && age < 2.8) {
            let rippleCenter = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0) + 0.5;
            let delta = uv - rippleCenter;
            let radius = length(delta);
            let front = smoothstep(0.024, 0.0, abs(radius - age * 0.24)) * exp(-age * 0.75);
            let direction = delta / max(radius, 0.001);
            clickWave += front;
            clickFlow += vec2<f32>(-direction.y, direction.x) * front
                * select(-1.0, 1.0, (ri % 2u) == 0u);
        }
    }
    uv += clickFlow * 0.045 + vec2<f32>(-dirToMouse.y, dirToMouse.x) * accretionEnvelope * 0.025;

    // Domain warp with audio-driven pulse
    var p = vec3<f32>(uv * BASE_FREQ, time * TIME_SCALE);
    let warp = fbm(p);
    p += vec3<f32>(warp * (warpStrength + bass * 0.15));
    p = vec3<f32>(p.xy + clickFlow * (0.8 + warpStrength * 0.5), p.z);

    // ── Per-octave filament stack ─────────────────────────────────
    // Octave o reads spectrum bin plasmaBuffer[(o % 8) + 1].x, so large-scale
    // structure follows the bass bins and fine structure follows treble bins.
    // Amplitudes halve per octave; OCTAVE_AMP_SUM renormalizes to [0,1].
    var density = 0.0;
    var amp = 1.0;
    var po = p;
    var vx = VoroX(vec3<f32>(1.0), vec2<f32>(1.0, 0.0));
    var junction = 0.0;
    for (var o = 0; o < FILAMENT_OCTAVES; o = o + 1) {
        var vo = vec2<f32>(0.0);
        var swell = 0.0;
        if (o == 0) {
            // base octave: also yields F3 and the wall normal (Ideas 1 and 2)
            vx = voronoi3x(po);
            vo = vx.f.xy;
            // ── Idea 1: junction clusters (§12.1 tactic 3: F3 was free in the loop).
            // F3 - F1 -> 0 where three walls meet = a cluster node. Mass funnels
            // along filaments into it, so the filament band swells there.
            junction = smoothstep(NODE_THRESHOLD, 0.0, vx.f.z - vx.f.x);
            swell = junction * JUNCTION_SWELL;
        } else {
            vo = voronoi3(po);
        }
        let binLevel = plasmaBuffer[(u32(o) % 8u) + 1u].x;
        let od = filamentDensity(max(vo.y - vo.x - swell, 0.0), densityScale);
        density += amp * od * (OCTAVE_BIN_BASE + binLevel * OCTAVE_BIN_GAIN);
        po = po * 2.0 + vec3<f32>(100.0);
        amp *= 0.5;
    }
    density = clamp(density / OCTAVE_AMP_SUM, 0.0, 1.0);

    let voidColor = vec3<f32>(0.05, 0.0, 0.1);

    var colFilament = vec3<f32>(0.2, 0.6, 1.0);
    let colCore = vec3<f32>(1.0, 1.0, 1.0);
    colFilament = hueShift(colFilament, colorShift * TAU + bass * 0.3);

    var color = mix(voidColor, colFilament, density);
    color = mix(color, colCore, smoothstep(0.8, 1.0, density));

    // ── VOID FEEDBACK FIX ─────────────────────────────────────────
    // No early-exit: void pixels fall through the SAME temporal feedback mix
    // as filament pixels, so the whole frame stays temporally coherent and
    // voids no longer shimmer at filament edges.
    let isVoid = density < VOID_CUTOFF;
    color = select(color, voidColor, isVoid);

    // Cluster nodes at Voronoi junctions (base octave F3 - F1). Rescue: HEAD keyed
    // this on F1 (the seed = the centre of a VOID cell, where density is lowest),
    // so the node bloom was effectively dead (mean nodeMetric^2 ~ 0.001).
    let nodeMetric = junction * density;

    // Galaxy point field along filaments
    let gCell = floor(uv * GALAXY_SCALE);
    let gRand = hash3(vec3<f32>(gCell, 1.0));
    // group centre pulled into the cell interior so satellites are not clipped
    // at the grid edge (host moves by <= 0.2 cell vs HEAD)
    let gPos = (gCell + 0.2 + 0.6 * gRand.xy) / GALAXY_SCALE;
    // uv is already aspect-corrected: HEAD multiplied by aspect a second time,
    // squeezing every galaxy dot horizontally on a wide canvas (no-op at 1:1).
    let gd = length(uv - gPos);
    let twinkle = 0.6 + 0.4 * sin(time * 3.0 + gRand.z * TAU);
    let gLive = step(GALAXY_THRESH, gRand.z) * twinkle * density;
    var galaxy = smoothstep(0.006, 0.0, gd) * gLive;

    // ── Idea 2: golden-angle galaxy groups aligned with their filament (§12.2E).
    // Each host galaxy carries GROUP_SATS satellites on a Vogel spiral
    // (theta = i * 2.39996, r = c * sqrt(i + 1/2)), stretched along the local
    // filament tangent (perpendicular to the wall normal r2 - r1 from the
    // base-octave Voronoi): galaxies live in groups, and groups align with the
    // filament they sit in (tidal-tensor alignment).
    let gTan = vec2<f32>(-vx.n.y, vx.n.x);
    let gNrm = vx.n;
    var sat = 0.0;
    for (var gi = 0; gi < GROUP_SATS; gi = gi + 1) {
        let fi = f32(gi) + 0.5;
        let ga = fi * GOLDEN_ANGLE + gRand.z * TAU;
        let gr = 0.0046 * sqrt(fi);
        let off = vec2<f32>(cos(ga), sin(ga)) * gr;
        let spos = gPos + gTan * (off.x * 1.35) + gNrm * (off.y * 0.6);
        sat += smoothstep(0.0027, 0.0, length(uv - spos));
    }
    let gcf = fract(uv * GALAXY_SCALE);
    let gWin = smoothstep(0.0, 0.12, min(gcf.x, 1.0 - gcf.x)) * smoothstep(0.0, 0.12, min(gcf.y, 1.0 - gcf.y));
    galaxy = clamp(galaxy + sat * 0.65 * gWin * gLive, 0.0, 1.0);
    let gTint = mix(vec3<f32>(0.7, 0.85, 1.0), vec3<f32>(1.0, 0.9, 0.7), gRand.x);

    color += vec3<f32>(1.0, 0.85, 0.6) * (nodeMetric * nodeMetric) * (1.3 + treble * 0.5);
    color += gTint * galaxy * (1.5 + bass * 0.6);
    color += hueShift(vec3<f32>(0.4, 0.72, 1.2), colorShift * TAU)
        * (accretion * (0.8 + mids * 0.5) + clickWave * (0.55 + treble * 0.45));

    // Depth-aware intensity boost
    color *= 1.0 + depth * 0.25;

    // Temporal feedback — now applied to voids and filaments alike
    let historyDrift = vec2<i32>(round((clickFlow + vec2<f32>(-dirToMouse.y, dirToMouse.x)
        * accretionEnvelope) * 2.5));
    prev = textureLoad(dataTextureC, clamp(pixel - historyDrift, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);
    let temporal = mix(prev.rgb * DECAY, color, FEEDBACK);

    // Chromatic aberration + ACES tone map
    color = genChromaticShift(temporal, uv01, 0.003 * (1.0 + bass));
    color = acesToneMap(color * (0.9 + mids * 0.2));

    // Layered alpha: luminance-keyed, edge-preserved, depth-layered.
    // voidColor luma ≈ 0.018 → lumaKey = 0 → void alpha stays 0 (unchanged).
    let alpha = clamp(compositeAlpha(color, density, galaxy, nodeMetric, depth)
        + accretion * 0.18 + clickWave * 0.16, 0.0, 0.98);
    let temporalAlpha = mix(prev.a * DECAY, alpha, FEEDBACK);

    // dataTextureA carries pre-ACES HDR color (no clamp — feedback equilibrium)
    textureStore(dataTextureA, pixel, vec4<f32>(temporal, temporalAlpha));
    // Rescue: HEAD ended here with `let __finalRGB` (illegal identifier), a second
    // `let rippleCount` / `let aspect` in the same scope, a screen-wide concentric
    // clockRings * IQ-cosine spectral overlay and a click front mis-timed against
    // ripple.z. All removed: the display output is the ACES'd colour computed above.
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    // Preserve the original void depth output (0.0) exactly
    textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(select(density, 0.0, isVoid)
        + accretion * 0.12 + clickWave * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
