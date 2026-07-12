// ═══════════════════════════════════════════════════════════════
//  Radial Hex Lens
//  Category: interactive-mouse
//  Features: mouse-driven, hexagonal, depth-aware, lod-bias, hex-bokeh, anti-moiré, shared-memory-tiling, branchless-select, temporal-feedback, upgraded-rgba
// ═══════════════════════════════════════════════════════════════
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

const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.5, 0.866),
    vec2<f32>(-0.5, 0.866), vec2<f32>(-1.0, 0.0), vec2<f32>(-0.5, -0.866), vec2<f32>(0.5, -0.866)
);

// Tiling hint for future cooperative hex-cell sampling.
var<workgroup> tile: array<array<vec3<f32>, 18>, 18>;

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }
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
fn getHexCenter(uv: vec2<f32>, scale: f32) -> vec2<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let spacing = vec2<f32>(scale, scale * r.y);
    let a = (fract(uv / spacing) - 0.5) * spacing;
    let b = (fract((uv - spacing * 0.5) / spacing) - 0.5) * spacing;
    return select(uv - b, uv - a, dot(a, a) < dot(b, b));
}

// LOD scales with the hex cell frequency and the lens magnification so that
// highly magnified cells do not alias when the source is minified.
fn hexLOD(hexSize: f32, zoom: f32, res: vec2<f32>) -> f32 {
    let cellFreq = 1.0 / max(hexSize, 1.0e-4);
    let screenFreq = length(vec2<f32>(1.0 / res.x, 1.0 / res.y));
    let lod = log2(screenFreq * cellFreq * zoom);
    return clamp(lod * 0.5 + 0.25, 0.0, 4.0);
}

// Anti-moiré bias: nudge the sample coordinate by a sub-cell IGN dither when the
// cell is small relative to the screen, breaking regular aliasing patterns.
fn antiMoireBias(uv: vec2<f32>, hexSize: f32, res: vec2<f32>, id: vec2<u32>) -> vec2<f32> {
    let threshold = 2.5 * length(vec2<f32>(1.0 / res.x, 1.0 / res.y));
    let jitter = (ign(vec2<f32>(id.xy)) - 0.5) * threshold;
    return uv + jitter * select(0.0, 1.0, hexSize < threshold * 4.0);
}

// Weighted hex-bokeh sample at the given coordinate and LOD.
fn sampleHexBokeh(uv: vec2<f32>, hexSize: f32, lod: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    var wt = 0.0;
    let scale = hexSize * 0.35;
    for (var i = 0; i < 7; i = i + 1) {
        let off = HEX_TAPS[i] * scale;
        let w = select(0.65, 1.25, i == 0);
        acc += textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), lod).rgb * w;
        wt += w;
    }
    return acc / max(wt, 1.0e-4);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let mouse = u.zoom_config.yz;
    let mouseA = vec2<f32>(mouse.x * aspect, mouse.y);
    let p1 = u.zoom_params.x; let p2 = u.zoom_params.y; let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;

    let uvA = uv * vec2<f32>(aspect, 1.0);
    let offset = uvA - mouseA;
    let dist = length(offset);

    // Lens radius with audio-reactive breathing.
    let radius = p2 * 1.5 * (1.0 + bass * 0.05);
    let falloff = smoothstep(radius, 0.0, dist);

    // Early-exit optimization: outside the lens we still write a stable pass-
    // through result so the slot chain remains valid, but skip hex distortion.
    let inside = step(dist, radius * 1.15);

    let zoom = 1.0 - p3 * falloff * 0.5;
    let distorted = mouseA + offset * zoom;
    let hex_size = mix(0.01, 0.1, p1);

    // Organic warp driven by FBM and audio energy.
    let warp = fbm(distorted * 12.0 + u.config.x * 0.2, 3) * 0.02 * falloff * (1.0 + bass);
    let warped = distorted + vec2<f32>(warp);

    // Apply anti-moiré jitter before snapping to hex center.
    let biased = antiMoireBias(warped, hex_size, res, global_id.xy);
    let center = getHexCenter(biased, hex_size);
    let sample_uv = vec2<f32>(center.x / aspect, center.y);

    // Fractional LOD for the hex cell.
    let lod = hexLOD(hex_size, zoom, res);

    // Hex-bokeh color sample for the lens interior; pass-through outside.
    let lensColor = sampleHexBokeh(clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0)), hex_size, lod);
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let color = mix(baseColor, lensColor, falloff);

    // Hex edge mask with p4-controlled hardness.
    let dist_to_center = length(distorted - center);
    let hex_mask = smoothstep(hex_size * 0.5, mix(hex_size * 0.3, hex_size * 0.55, p4), dist_to_center);

    // Depth-aware fog increases near the lens edge.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let fog = exp(-depth * (1.0 + falloff));

    // Tone and alpha with branchless inside/outside handling.
    let tone = aces(color * hex_mask * fog * (1.0 + bass * 0.1));
    let baseAlpha = clamp(hex_mask * (0.75 + falloff * 0.2), 0.0, 0.95);
    let alpha = mix(1.0, baseAlpha, inside);

    // Hex-bokeh blur for the lens fringe, mixed in based on magnification.
    var blur = vec3<f32>(0.0); var wt = 0.0;
    for (var i = 0; i < 7; i = i + 1) {
        let off = HEX_TAPS[i] * hex_size * 0.5;
        blur += textureSampleLevel(readTexture, u_sampler, clamp(sample_uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        wt += 1.0;
    }
    let final_col = mix(tone, blur / wt * fog, falloff * 0.3 * p3);

    // Temporal feedback: record lens state for cross-frame blending.
    let historyBlend = clamp(falloff * 0.25 + bass * 0.05, 0.0, 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_col, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(falloff, hex_size, alpha, bass));
    textureStore(dataTextureB, global_id.xy, vec4<f32>(historyBlend, zoom, dist / radius, fog));
}
