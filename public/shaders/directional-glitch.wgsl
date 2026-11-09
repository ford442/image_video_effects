// ═══════════════════════════════════════════════════════════════════
//  Directional Glitch
//  Category: advanced-hybrid
//  Combined techniques:
//    - SDF-masked mouse zone (sdCircle + smin ring)
//    - Domain-warped FBM + Voronoi-ridge glitch blocks
//    - Curl-noise directional displacement
//    - Audio-reactive cosine palette + chromatic aberration
//    - Kaleidoscope temporal feedback echo
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-11-09
//  Ideas: directional block tear (cells slide along the mouse heading in block-pitch steps, RGB split on the same axis); compass-snapped cell headings (45-degree hashed turns per voronoi cell); leading-edge overrun sliver
//  A packing: pre-ACES linear display RGB + coverage alpha; C read back (exact load) for the local kaleido echo
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

// ── Canonical hash / noise ────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
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
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}

// Divergence-free velocity field for organic glitch drift
fn curl2D(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.001;
    let nx = fbm(p + vec2<f32>(0.0, eps), 3) - fbm(p - vec2<f32>(0.0, eps), 3);
    let ny = fbm(p + vec2<f32>(eps, 0.0), 3) - fbm(p - vec2<f32>(eps, 0.0), 3);
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}

// ── Cellular ridges (Voronoi F2-F1) for multi-scale glitch bands ──
fn voronoiEdges(p: vec2<f32>) -> f32 {
    var F1: f32 = 999999.0;
    var F2: f32 = 999999.0;
    let ip = floor(p);
    for (var i: i32 = -1; i <= 1; i = i + 1) {
        for (var j: i32 = -1; j <= 1; j = j + 1) {
            let n = ip + vec2<f32>(f32(i), f32(j));
            let d = length(p - n - hash21(n));
            if (d < F1) { F2 = F1; F1 = d; } else if (d < F2) { F2 = d; }
        }
    }
    return F2 - F1;
}

// Nearest voronoi cell id (same jitter as voronoiEdges) for per-cell headings.
fn voronoiCell(p: vec2<f32>) -> vec2<f32> {
    var best: f32 = 999999.0;
    var id = vec2<f32>(0.0);
    let ip = floor(p);
    for (var i: i32 = -1; i <= 1; i = i + 1) {
        for (var j: i32 = -1; j <= 1; j = j + 1) {
            let n = ip + vec2<f32>(f32(i), f32(j));
            let d = length(p - n - hash21(n));
            if (d < best) { best = d; id = n; }
        }
    }
    return id;
}

// Temporally coherent hash for sparkling blocks
fn temporalHash(p: vec2<f32>, time: f32) -> f32 {
    let seed = floor(time * 8.0);
    let n1 = hash21(p + vec2<f32>(seed));
    let n2 = hash21(p + vec2<f32>(seed + 1.0));
    return mix(n1, n2, fract(time * 8.0));
}

// ── Color / tone mapping ──────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Audio-driven cosine palette
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.50, 0.50, 0.50);
    let b = vec3<f32>(0.50, 0.50, 0.50);
    let c = vec3<f32>(1.00, 1.00, 1.00);
    let d = vec3<f32>(0.26, 0.42, 0.56);
    return a + b * cos(TAU * (c * t + d));
}

// ── SDFs & kaleidoscope ───────────────────────────────────────────
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn kaleido(uv: vec2<f32>, n: f32) -> vec2<f32> {
    let a = atan2(uv.y, uv.x);
    let r = length(uv);
    let an = TAU / n;
    let am = a + an * 0.5;
    let a2 = am - an * floor(am / an) - an * 0.5;
    return vec2<f32>(cos(a2), sin(a2)) * r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let highs = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;

    let intensity = u.zoom_params.x;
    let radius = u.zoom_params.y;
    let scatter = u.zoom_params.z;
    let angle_bias = u.zoom_params.w;

    // SDF mouse mask with smooth-unioned audio ring
    let aspect = res.x / max(res.y, 1.0);
    let uv_c = vec2<f32>(uv01.x * aspect, uv01.y);
    let mouse_c = vec2<f32>(mouse.x * aspect, mouse.y);
    let dMouse = sdCircle(uv_c - mouse_c, radius * 0.35);
    let dRing = abs(sdCircle(uv_c - mouse_c, radius * (0.65 + bass * 0.2))) - 0.04;
    let sdf = smin(dMouse, dRing, 0.12);
    let mask = smoothstep(radius, 0.0, sdf) * (0.5 + 0.5 * clamp(depth, 0.0, 1.0));

    // Directional + divergence-free displacement
    let angle = atan2(uv01.y - mouse.y, uv01.x - mouse.x) + angle_bias * TAU;
    let radial = vec2<f32>(cos(angle), sin(angle));
    let curl = curl2D(uv01 * 6.0 + mouse * 2.0 + vec2<f32>(time * 0.1));
    let dir = normalize(mix(radial, curl, 0.35 * intensity) + vec2<f32>(0.0001));

    // Domain-warped FBM + Voronoi ridges drive the glitch blocks
    let noiseScale = 8.0 + scatter * 64.0;
    let warp = domainWarp(uv01 * noiseScale + vec2<f32>(time * 0.3), intensity * 0.5, 3);
    let field = fbm(warp + bass * 0.5, 4);
    let cells = voronoiEdges(uv01 * noiseScale * 0.5 + vec2<f32>(time * 0.2));
    let trigger = field + cells * 0.4 * intensity;
    let glitchMask = step(1.0 - scatter * 0.6, trigger);

    let disp = glitchMask * intensity * mask * (0.04 + bass * 0.03);
    let caAmount = disp * 3.0 + depth * 0.001 + bass * 0.001;

    // IDEA 2 — compass-snapped cell headings: each voronoi cell turns the field heading
    // by a hashed multiple of 45 degrees (mostly 0 / +-45), so neighbours tear in related
    // but different directions.
    let cellP = uv01 * noiseScale * 0.5 + vec2<f32>(time * 0.2);
    let cellId = voronoiCell(cellP);
    let turn = floor(hash21(cellId + vec2<f32>(3.1, 7.7)) * 3.0) - 1.0;
    let cellAng = atan2(dir.y, dir.x) + turn * PI * 0.25;
    let cellDir = vec2<f32>(cos(cellAng), sin(cellAng));

    // IDEA 1 — directional block tear (HEAD computed `dir` but never used it, so Angle Bias
    // was dead and the split was radial from screen centre). Each triggered cell slides along
    // its heading by a whole number of block pitches; RGB split rides the same axis.
    let pitch = 1.0 / max(noiseScale * 0.5, 1.0);
    let steps = 1.0 + floor(hash21(cellId + vec2<f32>(floor(time * 4.0))) * 3.0);
    let slideAmt = glitchMask * mask * intensity * steps * pitch * (0.5 + bass * 0.5);
    let slideUV = uv01 - cellDir * vec2<f32>(1.0 / aspect, 1.0) * slideAmt;
    let caVec = cellDir * vec2<f32>(1.0 / aspect, 1.0) * caAmount;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(slideUV + caVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(slideUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let bch = textureSampleLevel(readTexture, u_sampler, clamp(slideUV - caVec * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var glitch = vec3<f32>(r, g, bch) * (1.0 + disp * 6.0);

    // Audio-reactive palette and temporally coherent sparkle
    let pal = palette(time * 0.04 + bass * 0.6 + mids * 0.3 + trigger * 0.3 + highs * 0.2);
    glitch *= mix(vec3<f32>(1.0), pal * 1.6, 0.6) * (1.0 + bass * 0.5);
    let spark = temporalHash(uv01 * 120.0 + mouse * 20.0, time);
    glitch += vec3<f32>(spark * spark * mask * intensity * 0.35 * (1.0 + bass));

    // IDEA 3 — leading-edge overrun sliver: where the trigger field crosses its threshold on
    // the side the cell is heading toward, a thin bright line spills (buffer overrun).
    let ahead = uv01 + cellDir * vec2<f32>(1.0 / aspect, 1.0) * pitch * 0.15;
    let warpA = domainWarp(ahead * noiseScale + vec2<f32>(time * 0.3), intensity * 0.5, 3);
    let trigA = fbm(warpA + bass * 0.5, 4) + voronoiEdges(ahead * noiseScale * 0.5 + vec2<f32>(time * 0.2)) * 0.4 * intensity;
    let leadEdge = glitchMask * (1.0 - step(1.0 - scatter * 0.6, trigA));
    glitch += pal * leadEdge * mask * (0.6 + highs * 0.5);

    // Blend with original based on glitch strength
    let original = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
    let mixFactor = clamp(mask * glitchMask * intensity, 0.0, 1.0);
    var color = mix(original.rgb, glitch, mixFactor);

    // Kaleidoscope temporal feedback echo — now local to the SDF zone (HEAD blended 80% of a
    // filtered-sampled kaleido C over the whole frame, which washed the picture out).
    let seg = 4.0 + floor(2.0 + bass * 6.0);
    let kuv = kaleido(uv01 - mouse, seg) + mouse;
    let kc = vec2<i32>(clamp(kuv * res, vec2<f32>(0.0), res - 1.0));
    let prev = textureLoad(dataTextureC, kc, 0);
    let decay = 0.97 - intensity * 0.03;
    let echoW = mask * (0.45 + bass * 0.1) * intensity;
    color = mix(color, max(prev.rgb, vec3<f32>(0.0)) * decay, clamp(echoW, 0.0, 0.8));

    // Tone map and semantic alpha
    let linear = max(color * (0.9 + mids * 0.25), vec3<f32>(0.0));
    let alpha = clamp(max(original.a, mixFactor + leadEdge * mask) + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(linear * 1.1), alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(linear, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
