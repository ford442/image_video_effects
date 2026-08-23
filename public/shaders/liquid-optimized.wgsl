// ═══════════════════════════════════════════════════════════════════
//  Liquid Surface Tension (Optimized) — Analytic Capillary Field
//  Category: liquid-effects
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, capillary-waves, analytic-gradient, fresnel,
//            spectral-absorption, temporal-sheen, depth-aware,
//            upgraded-rgba, semantic-alpha, aces
//  Complexity: High
//  Created: 2026-03-20
//  Upgraded: 2026-08-23 (Batch 58B — Liquid)
// ═══════════════════════════════════════════════════════════════════
//  "Optimized" was a misnomer before this pass. The surface normal was built
//  by calling proceduralHeight() five times (centre + 4 neighbours), and each
//  call ran the full 50-ripple loop — up to 250 ripple iterations per pixel to
//  produce one normal. This version evaluates the height field ONCE and
//  accumulates its analytic gradient in the same loop: every wave term here has
//  a closed-form derivative, so the normal is exact rather than a finite
//  difference, and the per-pixel ripple work drops by 5x. That budget is what
//  pays for the two new structures:
//
//    1. Per-band FFT capillary spectrum — the ambient chop is now eight wave
//       trains, one per plasmaBuffer[1..8] bin, each with its own wavevector
//       and dispersion-correct phase speed (omega = sqrt(sigma·k³/rho) for
//       capillary waves, so short waves genuinely run faster than long ones).
//
//    2. Spectral absorption with Fresnel-weighted transmission — Beer-Lambert
//       absorption is evaluated per channel against the true slant path length
//       through the film (thickness / cos of the refracted angle) rather than a
//       flat thickness, so the liquid deepens in colour where you look through
//       it obliquely.
//
//  Also fixed: the ripple loop used an unguarded `u32(u.config.y)`; the
//  contract requires min(..., 50u). Workgroup moved 8x8x1 -> 16x16x1.
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=SurfaceTension, y=Gravity, z=Damping, w=Turbidity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

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

// Height plus its analytic gradient, packed as (h, dh/du, dh/dv).
// Every term below is differentiated in closed form, so the caller gets an
// exact normal from ONE evaluation instead of five finite-difference probes.
fn heightAndGradient(
    uv: vec2<f32>,
    currentTime: f32,
    surfaceTension: f32,
    gravityScale: f32,
    damping: f32,
    backgroundFactor: f32,
    bass: f32,
    mids: f32,
    held: f32
) -> vec3<f32> {
    var h = 0.0;
    var grad = vec2<f32>(0.0);

    // ── Click ripples: radial wave packets ───────────────────────────────────
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rippleData = u.ripples[i];
        let age = currentTime - rippleData.z;
        if (age <= 0.0 || age >= 3.0) { continue; }

        let d = uv - rippleData.xy;
        let r = max(length(d), 1e-4);
        let rHat = d / r;

        let k = 20.0 * gravityScale;
        let phase = r * k - age * 5.0 * gravityScale;
        let packetWidth = 0.3 + age * 0.1;
        let inv2 = 1.0 / (packetWidth * packetWidth);
        let envelope = exp(-(r * r) * inv2);
        let attenuation = 1.0 - smoothstep(0.0, 1.0, age / 2.5);
        let amp = 0.01 * attenuation * envelope * (1.0 + damping * 2.0);

        h += sin(phase) * amp;
        // d/dr [ sin(k r) * A * exp(-r^2/w^2) ]
        let dAdr = amp * (k * cos(phase) - sin(phase) * 2.0 * r * inv2);
        grad += rHat * dAdr;
    }

    // ── Structure 1: per-band FFT capillary spectrum ─────────────────────────
    // Capillary dispersion: omega ~ sqrt(k^3). Short (high-band) waves run
    // faster than long ones, which is what makes real chop look alive.
    let t = currentTime;
    let chopAmp = 0.003 * surfaceTension * backgroundFactor;
    for (var b: u32 = 0u; b < 8u; b = b + 1u) {
        let fb = f32(b);
        let energy = plasmaBuffer[b + 1u].x;
        let k = (8.0 + fb * 7.0) * (1.0 + mids * 0.25);
        let omega = sqrt(k * k * k) * 0.035;
        let theta = fb * 0.7853981634;                    // fan the directions
        let dirW = vec2<f32>(cos(theta), sin(theta));
        let arg = dot(uv, dirW) * k - t * omega;
        let amp = chopAmp * (0.35 + energy * 1.4) / (1.0 + fb * 0.35);
        h += sin(arg) * amp;
        grad += dirW * (k * cos(arg) * amp);
    }

    // ── Bass swell radiating from frame centre ───────────────────────────────
    let c = uv - vec2<f32>(0.5);
    let rc = max(length(c), 1e-4);
    let cHat = c / rc;
    let kc = 30.0;
    let argc = rc * kc - currentTime * 8.0;
    let envc = exp(-rc * 3.0);
    let ampc = bass * 0.015 * backgroundFactor;
    h += sin(argc) * envc * ampc;
    grad += cHat * ampc * (kc * cos(argc) * envc - sin(argc) * 3.0 * envc);

    // ── Held pointer: a standing capillary dimple under the cursor ───────────
    let m = uv - u.zoom_config.yz;
    let rm = max(length(m), 1e-4);
    let mHat = m / rm;
    let km = 42.0;
    let argm = rm * km - currentTime * 6.0;
    let envm = exp(-rm * 9.0);
    let ampm = held * 0.012 * (1.0 + bass * 0.6);
    h += sin(argm) * envm * ampm;
    grad += mHat * ampm * (km * cos(argm) * envm - sin(argm) * 9.0 * envm);

    return vec3<f32>(h, grad);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dimsI);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let currentTime = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held   = step(0.5, u.zoom_config.w);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let backgroundFactor = 1.0 - smoothstep(0.0, 0.1, depth);

    let surfaceTension = u.zoom_params.x * 0.5 + 0.1;
    let gravityScale = (u.zoom_params.y * 2.0 + 0.5) * (1.0 + bass * 0.4);
    let damping = u.zoom_params.z * 0.15 + 0.02;
    let turbidity = u.zoom_params.w;

    // ── One evaluation, exact normal ─────────────────────────────────────────
    let hg = heightAndGradient(uv, currentTime, surfaceTension, gravityScale,
                               damping, backgroundFactor, bass, mids, held);
    let hCenter = hg.x;
    let heightScale = 0.5 * surfaceTension;
    // The original built its slope from a raw central difference over one texel
    // (hRight - hLeft), i.e. an UNNORMALISED difference. Scaling the analytic
    // derivative by that same 2*texel step reproduces the tuned magnitude
    // exactly to first order — without it the normals would be ~1/(2*texel)
    // times steeper (three orders of magnitude at 1080p) and the refraction
    // would blow out.
    let pixelSize = vec2<f32>(1.0) / resolution;
    let slope = hg.yz * 2.0 * pixelSize * heightScale;
    let normal = normalize(vec3<f32>(-slope.x, -slope.y, 2.0));

    // ── Refraction ───────────────────────────────────────────────────────────
    let refractionStrength = 0.02 * surfaceTension;
    let refractDisplacement = normal.xy * refractionStrength * backgroundFactor;
    let totalDisplacement = refractDisplacement + vec2<f32>(hCenter * 0.01);
    let colorUV = clamp(uv + totalDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));

    // Slight dispersion along the slope — the film splits light where it tilts.
    let dispDir = normalize(hg.yz + vec2<f32>(1e-6));
    let disp = (0.0006 + treble * 0.0025) * clamp(length(hg.yz) * 0.02, 0.0, 1.0);
    let sR = textureSampleLevel(readTexture, u_sampler, clamp(colorUV + dispDir * disp, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let sG = textureSampleLevel(readTexture, u_sampler, colorUV, 0.0);
    let sB = textureSampleLevel(readTexture, u_sampler, clamp(colorUV - dispDir * disp, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let baseColor = vec3<f32>(sR.r, sG.g, sB.b);

    // ── Structure 2: Fresnel-weighted spectral absorption ────────────────────
    // Beer-Lambert along the true slant path: thickness / cos(refracted angle).
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cosI = clamp(dot(viewDir, normal), 0.05, 1.0);
    let sinI = sqrt(max(0.0, 1.0 - cosI * cosI));
    let sinT = clamp(sinI / 1.333, 0.0, 0.999);            // Snell, water
    let cosT = sqrt(1.0 - sinT * sinT);
    let fresnel = schlickFresnel(cosI, 0.02);

    let thickness = abs(hCenter) * 2.0 + 0.1;
    let pathLength = thickness * (1.0 + turbidity * 2.0) / max(cosT, 0.05);
    let absorption = vec3<f32>(exp(-pathLength * 2.0),
                               exp(-pathLength * 1.6),
                               exp(-pathLength * 1.2));
    let absorptionMean = dot(absorption, vec3<f32>(1.0 / 3.0));

    let heightTint = vec3<f32>(0.0, 0.1, 0.15) * hCenter * 0.5;
    var liquidColor = baseColor * absorption + heightTint;

    // Specular from the exact normal.
    let lightDir = normalize(vec3<f32>(0.3, 0.5, 1.0));
    let halfDir = normalize(lightDir + viewDir);
    let specAngle = max(0.0, dot(normal, halfDir));
    // specAngle^128 by repeated squaring (matches the original exponent).
    let s2 = specAngle * specAngle;
    let s4 = s2 * s2;
    let s8 = s4 * s4;
    let s16 = s8 * s8;
    let s32 = s16 * s16;
    let s64 = s32 * s32;
    let specular = s64 * s64 * 0.8 * (1.0 - turbidity * 0.5) * (1.0 + treble * 0.5);
    liquidColor += vec3<f32>(specular) + vec3<f32>(0.6, 0.8, 1.0) * fresnel * 0.25;

    // ── Temporal sheen (exact load — dataTextureC is rgba32float) ────────────
    let prev = textureLoad(dataTextureC, coord, 0);
    liquidColor = mix(liquidColor, max(liquidColor, prev.rgb * 0.88), 0.35);

    // ── Semantic alpha ───────────────────────────────────────────────────────
    let baseAlpha = mix(0.3, 0.95, absorptionMean * backgroundFactor);
    let finalAlpha = clamp(baseAlpha * (1.0 - fresnel * 0.5), 0.0, 1.0);
    let finalColor = acesFilm(mix(baseColor, liquidColor, finalAlpha));

    let outColor = vec4<f32>(finalColor, finalAlpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    // Depth: the meniscus lifts the surface toward the viewer.
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(clamp(depth - hCenter * 0.5, 0.0, 1.0), 0.0, 0.0, 0.0));
}
