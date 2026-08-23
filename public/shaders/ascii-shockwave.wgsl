// ═══════════════════════════════════════════════════════════════════
//  ASCII Shockwave — Dot-Matrix Terminal Blast Fronts
//  Category: visual-effects
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, dot-matrix-glyphs, chromatic-aberration,
//            phosphor-persistence, depth-aware, upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 56 — Turbulent Vortex)
// ═══════════════════════════════════════════════════════════════════
//  The original drew four hand-written shapes with an if/else chain and hard
//  edges, driven by a single sine pulse. Two structures replace that:
//
//    1. Packed 4x6 dot-matrix glyph ROM — eight glyphs are stored as 24-bit
//       masks and indexed by cell luminance, giving a real character ramp
//       (space · : + * o # █). Cell luminance is a 2x2 box average of the
//       source rather than a single tap, so glyph choice is stable instead of
//       flickering on high-frequency detail, and the dot is rendered with a
//       soft footprint so the matrix anti-aliases at any cell size.
//
//    2. Dispersive multi-front wave field — the ASCII region is the union of a
//       continuous pointer pulse and every bounded click front (u.ripples,
//       capped at 50), each expanding at its own rate with a trailing wake.
//       The wave number is banded by the 8 FFT bins, so the ring spacing
//       breathes with the spectrum.
//
//  The crest of every front is drawn with a chromatic split, and glyphs leave a
//  decaying phosphor trace through dataTextureC.
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
  zoom_params: vec4<f32>,  // x=CellDensity, y=WaveSpeed, z=Tint, w=Persistence
  ripples: array<vec4<f32>, 50>,
};

// ── Glyph ROM ────────────────────────────────────────────────────────────────
// 4 columns x 6 rows, bit index = row * 4 + col, col 0 = left, row 0 = top.
// Ordered by ink coverage so the index doubles as a luminance ramp.
var<private> GLYPHS: array<u32, 8> = array<u32, 8>(
    0x000000u,  // ' '  empty
    0x020000u,  // '.'  single low dot
    0x020020u,  // ':'  two stacked dots
    0x002F20u,  // '+'  cross
    0x009690u,  // '*'  diagonal star
    0x069960u,  // 'o'  ring
    0x05F5F5u,  // '#'  hatch
    0xFFFFFFu   // '█'  solid block
);

fn glyphInk(index: u32, cellUV: vec2<f32>, softness: f32) -> f32 {
    let bits = GLYPHS[min(index, 7u)];
    // Nearest dot centre in the 4x6 matrix.
    let g = cellUV * vec2<f32>(4.0, 6.0);
    let cell = clamp(floor(g), vec2<f32>(0.0), vec2<f32>(3.0, 5.0));
    let bit = u32(cell.y) * 4u + u32(cell.x);
    let on = f32((bits >> bit) & 1u);
    // Soft round footprint per dot so the matrix anti-aliases.
    let d = length(fract(g) - vec2<f32>(0.5));
    return on * smoothstep(0.52, 0.52 - softness, d);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
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
    let mouse = u.zoom_config.yz;
    let held = step(0.5, u.zoom_config.w);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Params ───────────────────────────────────────────────────────────────
    let cells = mix(40.0, 160.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let waveSpeed = mix(4.0, 16.0, clamp(u.zoom_params.y, 0.0, 1.0)) * (1.0 + mids * 0.35);
    let tintMix = clamp(u.zoom_params.z, 0.0, 1.0);
    let persistence = mix(0.55, 0.94, clamp(u.zoom_params.w, 0.0, 1.0));

    // ── Structure 2: dispersive multi-front wave field ───────────────────────
    // Ring spacing is banded by the FFT: each horizontal band gets its own bin.
    let bandIdx = u32(clamp(uv.y * 8.0, 0.0, 7.999));
    let band = plasmaBuffer[bandIdx + 1u].x;
    let waveNumber = 20.0 + band * 26.0 + bass * 10.0;

    let uv_aspect = uv * vec2<f32>(aspect, 1.0);
    let mouse_aspect = mouse * vec2<f32>(aspect, 1.0);
    let dist = distance(uv_aspect, mouse_aspect);

    // Continuous pointer pulse — holding the button raises its amplitude.
    var pulse = sin(dist * waveNumber - time * waveSpeed) * (0.55 + held * 0.45);

    // Bounded click fronts with a trailing wake.
    var frontGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.8) {
            let rDist = distance(uv_aspect, rp.xy * vec2<f32>(aspect, 1.0));
            let radius = age * 0.6;
            let front = rDist - radius;
            let decay = exp(-age * 1.1);
            // Crest plus a wake that trails behind the front.
            pulse += cos(front * waveNumber) * exp(-front * front * 24.0) * decay * 1.2;
            frontGlow += exp(-front * front * 320.0) * decay;
        }
    }
    frontGlow = min(frontGlow, 1.6);
    pulse = clamp(pulse, -1.5, 1.5);

    // ── ASCII region ─────────────────────────────────────────────────────────
    let asciiMask = smoothstep(0.42, 0.58, pulse);

    // Structure 1: box-averaged cell luminance → glyph index → dot matrix.
    let cellSize = 1.0 / cells;
    let cellOrigin = floor(uv * cells) / cells;
    let q = cellSize * 0.25;
    let s0 = textureSampleLevel(readTexture, u_sampler, cellOrigin + vec2<f32>(q, q), 0.0);
    let s1 = textureSampleLevel(readTexture, u_sampler, cellOrigin + vec2<f32>(3.0 * q, q), 0.0);
    let s2 = textureSampleLevel(readTexture, u_sampler, cellOrigin + vec2<f32>(q, 3.0 * q), 0.0);
    let s3 = textureSampleLevel(readTexture, u_sampler, cellOrigin + vec2<f32>(3.0 * q, 3.0 * q), 0.0);
    let cellColor = (s0 + s1 + s2 + s3) * 0.25;
    let cellLuma = luma(cellColor.rgb);

    // Crest brightness pushes the cell up the ramp, so the wave "burns in".
    let ramp = clamp(cellLuma * (1.0 + asciiMask * 0.5 + treble * 0.25), 0.0, 1.0);
    let glyphIndex = u32(ramp * 7.999);
    let localUV = fract(uv * cells);
    let softness = clamp(cells / resolution.y * 2.5, 0.04, 0.35);
    let ink = glyphInk(glyphIndex, localUV, softness);

    // Terminal phosphor colour, tinted back toward the source by Param3.
    let phosphor = vec3<f32>(0.15, 1.0, 0.35);
    let glyphColor = mix(phosphor * (0.35 + cellLuma), cellColor.rgb, tintMix) * ink;

    // ── Composite: source outside the wave, glyphs inside ────────────────────
    // Chromatic split scales with the crest, so fronts fringe as they pass.
    let ca = (0.0015 + treble * 0.004) * (asciiMask + frontGlow);
    let dir = normalize(uv_aspect - mouse_aspect + vec2<f32>(1e-6)) / vec2<f32>(aspect, 1.0);
    let pR = textureSampleLevel(readTexture, u_sampler, uv + dir * ca, 0.0).r;
    let pG = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let pB = textureSampleLevel(readTexture, u_sampler, uv - dir * ca, 0.0).b;
    let plain = vec3<f32>(pR, pG.g, pB);

    var color = mix(plain * (1.0 - asciiMask * 0.85), glyphColor, asciiMask);

    // Front crest glows green-white; the wave edge stays legible on dark frames.
    color += vec3<f32>(0.35, 1.0, 0.5) * frontGlow * (0.5 + bass * 0.7);

    // ── Phosphor persistence ─────────────────────────────────────────────────
    let prev = textureLoad(dataTextureC, coord, 0);
    color = max(color, prev.rgb * persistence);

    color = acesFilm(color);

    // ── Alpha ────────────────────────────────────────────────────────────────
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let inkPresence = max(ink * asciiMask, frontGlow * 0.7);
    let base = mix(0.7, 1.0, luma(color));
    let alpha = clamp(mix(base * 0.8, base, depth) + inkPresence * 0.25, 0.0, 1.0);

    let outColor = vec4<f32>(color, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);

    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
