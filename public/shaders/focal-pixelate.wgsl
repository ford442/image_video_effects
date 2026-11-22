// ═══════════════════════════════════════════════════════════════════
//  Focal Pixelate
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, domain-warp, depth-aware, hex-bokeh, anti-moiré, lod-bias, upgraded-rgba
//  Complexity: Low
//  Upgraded: 2026-10-31, 2026-11-22
//  Ideas: pixel-aperture well; defocus circle of confusion; CFA zipper (§12.2A); highlight-weighted defocus discs
//  A packing: ACES display RGBA (same value as writeTexture; HEAD stored focus metadata nobody read)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.5, 0.866),
    vec2<f32>(-0.5, 0.866), vec2<f32>(-1.0, 0.0), vec2<f32>(-0.5, -0.866), vec2<f32>(0.5, -0.866)
);

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
// Returns a DISPLACEMENT in uv units (HEAD returned `p + strength*q`, an absolute position
// that main() then added to uv -> the fringe sampled ~9*uv, clamped to the photo's edge).
// 3-octave value-noise fbm has mean ~0.44, subtracted so the fringe is not biased diagonally.
fn domainWarp(p: vec2<f32>, strength: f32, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + t * 0.1, 3), fbm(p + vec2<f32>(5.2, 1.3) - t * 0.08, 3));
    return strength * (q - vec2<f32>(0.44));
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }

// Compute a fractional LOD based on the block grid frequency. Higher block
// counts alias less, but when the block size is large we bias LOD down to
// preserve crisp pixel edges. This acts as an anti-moiré filter.
fn lodForBlocks(blocks: f32, res: vec2<f32>) -> f32 {
    let cellFreq = max(blocks / max(res.x, res.y), 1.0e-4);
    let rawLod = log2(cellFreq * 512.0);
    return clamp(rawLod * 0.35 - 0.5, 0.0, 3.0);
}

// Hex-bokeh weighted sample kernel. The center tap receives full weight while
// the six surrounding taps average neighboring cells for a softer transition.
fn sampleHexBokeh(uv: vec2<f32>, cellSize: f32, lod: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    var wt = 0.0;
    let scale = cellSize * 0.5;
    for (var i = 0; i < 7; i = i + 1) {
        let off = HEX_TAPS[i] * scale;
        let tap = textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.001), vec2<f32>(0.999)), lod).rgb;
        // ── Idea 4: highlight-weighted defocus discs ────────────────────
        // A real defocus kernel integrates light, so a bright tap outweighs a dark one and
        // specular highlights open into aperture-shaped (hex) discs instead of a flat blur.
        // Weights are normalised below (acc / wt): energy is moved, not added.
        let hl = smoothstep(0.55, 1.0, dot(tap, vec3<f32>(0.2126, 0.7152, 0.0722)));
        let w = select(0.85, 1.35, i == 0) * (1.0 + 3.0 * hl);
        acc += tap * w;
        wt += w;
    }
    return acc / max(wt, 1.0e-4);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / res;
    let mouse = u.zoom_config.yz;
    let aspect = res.x / res.y;
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;
    let p1 = u.zoom_params.x; let p2 = u.zoom_params.y; let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;

    // Distance from mouse in aspect-corrected space.
    let d = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(d);

    // Branchless focus selection: p4 > 0.5 inverts the focus region.
    let focus = smoothstep(p2, p2 + p3 + 0.001, dist);
    let invert = step(0.5, p4);
    let mix_factor = select(focus, 1.0 - focus, invert > 0.5);

    // Block count from pixel size parameter, with audio-reactive contraction.
    let base_blocks = mix(500.0, 20.0, p1) * (1.0 - bass * 0.3);
    let blocks = max(mix(2000.0, base_blocks, mix_factor), 1.0);

    // Domain warp only affects the pixelated fringe; branchless mix suppresses it
    // in the focused center for a cleaner in-focus image.
    let warp = domainWarp(uv * 8.0, 0.02 * mix_factor * (1.0 + bass), u.config.x);
    let cell = floor((uv + warp * mix_factor) * blocks);
    let sample_uv = clamp(cell / blocks + (0.5 / blocks), vec2<f32>(0.001), vec2<f32>(0.999));

    // Anti-moiré LOD bias: larger blocks get a fractional mip bias to smooth
    // high-frequency content; focused pixels stay at LOD 0.
    let lod = mix(0.0, lodForBlocks(blocks, res), mix_factor);

    // Combine point sampling for the focused center with hex-bokeh sampling for
    // the pixelated fringe using a branchless mix.
    let pointColor = textureSampleLevel(readTexture, non_filtering_sampler, sample_uv, 0.0).rgb;
    // ── Idea 2: defocus circle of confusion ─────────────────────────
    // The quantize grid stays `blocks`. The hex kernel widens with how
    // far this pixel already is from focus.
    let coc = mix(0.2, 2.6, mix_factor);
    let bokehColor = sampleHexBokeh(sample_uv, coc / blocks, lod);
    let shownBlur = mix(pointColor, bokehColor, mix_factor);

    // ── Idea 3: CFA zipper (§12.2A) ─────────────────────────────────
    // A pixelator that imitates a low-res sensor resolves luma per block but chroma only on
    // the coarser 2x2 colour-filter mosaic: every pair of blocks shares one hue, so block
    // edges show the Bayer "zipper" colour fringe. Fringe only (x mix_factor).
    let lumW = vec3<f32>(0.2126, 0.7152, 0.0722);
    let chromaUV = clamp((floor(cell * 0.5) * 2.0 + 1.0) / blocks, vec2<f32>(0.001), vec2<f32>(0.999));
    let chromaTap = textureSampleLevel(readTexture, non_filtering_sampler, chromaUV, 0.0).rgb;
    let shownL = dot(shownBlur, lumW);
    let chromaCoarse = chromaTap - vec3<f32>(dot(chromaTap, lumW));
    let chromaFine = shownBlur - vec3<f32>(shownL);
    let shown = max(vec3<f32>(shownL) + mix(chromaFine, chromaCoarse, 0.7 * mix_factor), vec3<f32>(0.0));

    // ── Idea 1: pixel-aperture well ─────────────────────────────────
    // fract inside the block is the square pixel. Corners darken only
    // in the fringe that is already pixelated.
    let fr = fract((uv + warp * mix_factor) * blocks);
    let margin = min(min(fr.x, 1.0 - fr.x), min(fr.y, 1.0 - fr.y));
    let aperture = smoothstep(0.0, 0.14, margin);
    let color = mix(shown, shown * (0.42 + 0.58 * aperture), mix_factor);

    // Depth-aware fog uses the warped sample coordinate to match the pixelated
    // look, but is attenuated near the focused center.
    let depthSampleUV = mix(uv, sample_uv, mix_factor);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, depthSampleUV, 0.0).r;
    let fog = exp(-depth * (1.5 + mix_factor));

    // ACES tone mapping with audio-reactive exposure lift.
    let tone = aces(color * (1.0 + treble * 0.15 + bass * 0.05) * fog);

    // Semantic alpha: stronger pixelation = slightly more transparent so the
    // slot chain can blend, but clamped to avoid disappearing.
    let alpha = clamp(0.2 + mix_factor * 0.35 + treble * 0.08, 0.08, 0.9);

    // IGN dithering breaks 8-bit banding on smooth gradients.
    let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;

    // Depth-aware compositing: depth is nudged in the pixelated fringe.
    let depthOut = clamp(depth + mix_factor * 0.03, 0.0, 1.0);

    // A = ACES display RGBA (HEAD packed focus metadata that nothing reads; a downstream slot
    // sampling C would have seen it as colour). B is not written: the host copies B->C first
    // and A->C last, so a B written next to A is never observed.
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(tone + dither, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(tone, alpha));
}
