// ═══════════════════════════════════════════════════════════════════
//  Oil Slick Iridescence — Nanometre Thin-Film Interference
//  Category: image
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, snell-refraction, fresnel, temporal-flow,
//            depth-aware, upgraded-rgba, semantic-alpha, aces
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-08-23 (Batch 56 — Turbulent Vortex)
// ═══════════════════════════════════════════════════════════════════
//  Thin-film interference done at the correct scale. Two structures:
//
//    1. Nanometre film + Snell/Fresnel — film thickness is now expressed in
//       NANOMETRES (120–900 nm) instead of arbitrary units, the incidence
//       angle comes from the height field's own gradient (the slick's slope),
//       the in-film angle follows Snell's law, and the two reflected beams are
//       combined with a Fresnel-weighted amplitude plus the π phase step at the
//       external interface. This is the fix for the washed-out look: the old
//       code divided a path difference of ~5 "units" by a 700 nm wavelength, so
//       every phase was ≈0 and all three channels returned ≈1.0 — a constant
//       white wash that no slider could shift.
//
//    2. Curl-advected film flow — the height field is transported by a curl
//       noise field whose rotation rate is banded by the 8 FFT bins, so the
//       slick creeps and folds rather than scrolling rigidly. The previous
//       frame's colour (dataTextureC) is advected along the same field, which
//       smears the rainbow into flow lines.
//
//  Interaction: the pointer is a capillary source (held = stronger standing
//  wave), and clicks drop bounded expanding ring waves onto the film surface.
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
  config: vec4<f32>,      // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=Thickness, y=IridescentStrength, z=FlowSpeed, w=Blend
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647;
const PI: f32 = 3.14159265358979324;
const N_AIR: f32 = 1.0;
const N_OIL: f32 = 1.46;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),                       hash(i + vec2<f32>(1.0, 0.0)), uu.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), uu.x),
        uu.y
    );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < oct; i++) {
        val += vnoise(p * freq) * amp;
        freq *= 2.0;
        amp *= 0.5;
    }
    return val;
}

// Curl of an fbm potential — divergence-free, so the film folds instead of
// piling up. Band index selects which FFT bin sets the rotation rate.
fn curlFlow(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.02;
    let dx = fbm(p + vec2<f32>(e, 0.0) + t, 3) - fbm(p - vec2<f32>(e, 0.0) + t, 3);
    let dy = fbm(p + vec2<f32>(0.0, e) + t, 3) - fbm(p - vec2<f32>(0.0, e) + t, 3);
    return vec2<f32>(dy, -dx) / (2.0 * e);
}

// Schlick Fresnel reflectance for the air→oil interface.
fn fresnelSchlick(cosTheta: f32) -> f32 {
    let r0 = ((N_AIR - N_OIL) / (N_AIR + N_OIL)) * ((N_AIR - N_OIL) / (N_AIR + N_OIL));
    let m = clamp(1.0 - cosTheta, 0.0, 1.0);
    let m2 = m * m;
    return r0 + (1.0 - r0) * m2 * m2 * m;
}

// Two-beam interference for one wavelength (nm). `thicknessNm` is the film
// thickness, `cosT` the cosine of the refracted angle inside the film. The
// extra PI is the hard phase reversal on reflection at the denser medium.
fn thinFilm(thicknessNm: f32, cosT: f32, lambdaNm: f32, reflectance: f32) -> f32 {
    let opd = 2.0 * N_OIL * thicknessNm * cosT;
    let phase = TAU * opd / lambdaNm + PI;
    let amp = sqrt(clamp(reflectance, 0.0, 1.0));
    return clamp(2.0 * amp * (0.5 + 0.5 * cos(phase)), 0.0, 1.6);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Height field in "film units" (later scaled to nm). Shared by the value and
// its finite-difference gradient so the normal is consistent with the surface.
fn filmHeight(p: vec2<f32>, t: f32, flowSpeed: f32, bandWobble: f32) -> f32 {
    let flowUV = p + vec2<f32>(t * flowSpeed * 0.3, t * flowSpeed * 0.2);
    return fbm(flowUV * 4.0, 5) + bandWobble * 0.12;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) { return; }

    let dims = vec2<f32>(dimsI);
    let uv = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    // ── Audio (canonical source: plasmaBuffer) ───────────────────────────────
    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Vertical FFT banding — the slick is sliced into 8 horizontal bands, each
    // wobbling with its own bin, so the rainbow ripples travel with the music.
    let bandIdx = u32(clamp(uv.y * 8.0, 0.0, 7.999));
    let band = plasmaBuffer[bandIdx + 1u].x;

    // ── Params ───────────────────────────────────────────────────────────────
    // Thickness now maps to a real optical range: 120 nm (first-order blue) to
    // ~900 nm (higher-order pastel bands).
    let thicknessNmBase = mix(120.0, 900.0, u.zoom_params.x) * (1.0 + bass * 0.55);
    let iriStr = u.zoom_params.y;
    let flowSpeed = mix(0.05, 0.5, u.zoom_params.z);
    let blend = u.zoom_params.w;
    let held = step(0.5, u.zoom_config.w);

    // ── Structure 2: curl-advected flow ──────────────────────────────────────
    let flow = curlFlow(uv * 3.0, time * (0.05 + band * 0.12)) * 0.012 * (1.0 + mid * 0.6);
    let pAdv = uv + flow;

    // Height field and its gradient → surface normal → incidence angle.
    // Epsilon is in UV units, not texels: the height field varies on a ~0.25 UV
    // scale, so a texel-sized step would return a slope of nearly zero and the
    // surface normal would collapse to straight-up at every pixel.
    let e = 0.004;
    let h0 = filmHeight(pAdv, time, flowSpeed, band);
    let hx = filmHeight(pAdv + vec2<f32>(e, 0.0), time, flowSpeed, band);
    let hy = filmHeight(pAdv + vec2<f32>(0.0, e), time, flowSpeed, band);

    // ── Pointer capillary wave + bounded click rings ─────────────────────────
    let mouse = u.zoom_config.yz;
    let mDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let pointerWave = sin(mDist * 30.0 - time * 6.0) * exp(-mDist * 8.0) * (0.25 + held * 0.9);

    var clickWave = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.6) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            let front = rDist - age * 0.45;
            clickWave += sin(front * 90.0) * exp(-front * front * 90.0) * exp(-age * 1.3);
        }
    }
    clickWave = clamp(clickWave, -1.2, 1.2);

    let surfaceWave = pointerWave * 0.3 + clickWave * 0.35;
    let h = h0 + surfaceWave;

    // Gradient of the full surface (height field dominates the slope).
    let grad = vec2<f32>(hx - h0, hy - h0) / e * 0.18;
    let normal = normalize(vec3<f32>(-grad, 1.0));
    let cosI = clamp(normal.z, 0.05, 1.0);                    // view along +Z
    let sinI = sqrt(max(0.0, 1.0 - cosI * cosI));
    let sinT = clamp(sinI * N_AIR / N_OIL, 0.0, 0.999);       // Snell
    let cosT = sqrt(1.0 - sinT * sinT);
    let reflectance = fresnelSchlick(cosI);

    // Thickness in nm — the slope thins the film where it is steep, as a real
    // spreading slick does.
    let thicknessNm = max(20.0, thicknessNmBase * (0.35 + h * 0.9));

    let iR = thinFilm(thicknessNm, cosT, 680.0, reflectance);
    let iG = thinFilm(thicknessNm, cosT, 550.0, reflectance);
    let iB = thinFilm(thicknessNm, cosT, 450.0, reflectance);
    let iridCol = vec3<f32>(iR, iG, iB) * iriStr * (1.0 + mid * 0.5);

    // ── Source, advected by the same flow ────────────────────────────────────
    let src = textureSampleLevel(readTexture, u_sampler, uv + flow * 0.4, 0.0);

    // Additive sheen on top of a multiplicative tint — the slick both filters
    // and reflects.
    var finalRGB = mix(src.rgb, src.rgb * (0.4 + iridCol * 0.8) + iridCol * 0.35, blend);

    // Specular glint where the surface tips toward the viewer.
    finalRGB += vec3<f32>(1.0) * pow(cosI, 24.0) * reflectance * (0.6 + treble * 1.4);

    // ── Temporal flow smear ──────────────────────────────────────────────────
    let prevCoord = clamp(coord - vec2<i32>(flow * dims * 0.8),
                          vec2<i32>(0), dimsI - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, prevCoord, 0);
    finalRGB = mix(finalRGB, max(finalRGB, prev.rgb * 0.9), 0.3 + band * 0.15);

    finalRGB = acesFilm(finalRGB);

    // ── Semantic alpha ───────────────────────────────────────────────────────
    // The film is where the effect lives: strong interference and wave crests
    // read as more substantial, transparent gaps stay transparent.
    let filmPresence = clamp(dot(iridCol, vec3<f32>(0.33)) * blend + abs(surfaceWave) * 0.5, 0.0, 1.0);
    let alpha = clamp(mix(src.a, 1.0, filmPresence * 0.8), 0.0, 1.0);

    let outColor = vec4<f32>(finalRGB, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(iR, iG, iB, thicknessNm / 1000.0));

    // Depth: the film sits above the plate, thicker where it piles up.
    let srcDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(srcDepth * (1.0 - filmPresence * 0.06), 0.0, 0.0, 0.0));
}
