// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Diffusion
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, semantic-alpha, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: edge-energy dilation across the tile neighbours; luma²-weighted hex taps (bokeh discs behind the neon); tangent-stretched hex (1.6× along / 0.6× across the edge)
//  A packing: ACES display RGBA (no history is read back; B unused)
// ═══════════════════════════════════════════════════════════════════
//  Shared-tile RGB edge magnitude turned into a fixed R/G/B neon ramp and
//  diffused through a 7-tap hex bokeh. Click ripples flash the lit edges.
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.5, 0.866),
    vec2<f32>(-0.5, 0.866), vec2<f32>(-1.0, 0.0), vec2<f32>(-0.5, -0.866), vec2<f32>(0.5, -0.866)
);

// 18x18 shared tile (16x16 workgroup + 1-pixel halo on each side).
var<workgroup> tile: array<array<vec3<f32>, 18>, 18>;

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }

// Fractional LOD bias based on the glow radius. A larger diffusion radius reads
// from a higher mip, suppressing moiré in fine high-contrast details.
fn glowLOD(radius: f32, res: vec2<f32>) -> f32 {
    let freq = radius * max(res.x, res.y);
    return clamp(log2(freq + 1.0) * 0.4 - 0.2, 0.0, 3.0);
}

// Shared-tile read with the index clamped to the 18x18 halo.
fn tileAt(x: i32, y: i32) -> vec3<f32> {
    return tile[clamp(y, 0, 17)][clamp(x, 0, 17)];
}

// Sobel-style RGB edge magnitude at a tile position (HEAD's formula).
fn edgeAt(x: i32, y: i32) -> f32 {
    let gx = length(tileAt(x + 1, y) - tileAt(x - 1, y));
    let gy = length(tileAt(x, y + 1) - tileAt(x, y - 1));
    return sqrt(gx * gx + gy * gy);
}

// Branchless 7-tap hex-bokeh glow. Center tap is weighted so the source color
// remains visible through the diffusion.
//  Idea 2: every tap is additionally weighted by luma² so the brightest
//  neighbours dominate and bokeh discs form behind the neon.
//  Idea 3: the hex is stretched 1.6× along the edge tangent and squeezed
//  0.6× across it (blended in by `stretch`, 0 = isotropic in flat regions).
fn hexGlow(uv: vec2<f32>, radius: f32, lod: f32, tangent: vec2<f32>, stretch: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    var wt = 0.0;
    let normal = vec2<f32>(-tangent.y, tangent.x);
    let along = mix(1.0, 1.6, stretch);
    let across = mix(1.0, 0.6, stretch);
    for (var i = 0; i < 7; i = i + 1) {
        let tap = HEX_TAPS[i];
        let off = (tangent * dot(tap, tangent) * along + normal * dot(tap, normal) * across) * radius;
        let s = textureSampleLevel(readTexture, u_sampler, clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0)), lod).rgb;
        let l = luma(s);
        let w = select(0.5, 1.0, i == 0) * (0.05 + l * l);
        acc += s * w;
        wt += w;
    }
    return acc / max(wt, 1.0e-4);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>, @builtin(local_invocation_id) lid: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    let pixel = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;
    let p1 = u.zoom_params.x; let p2 = u.zoom_params.y; let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;
    let bass = plasmaBuffer[0].x; let treble = plasmaBuffer[0].z;

    // Cooperative load: fill the 18x18 shared tile so Sobel reads stay in LDS.
    let base = vec2<i32>(gid.xy) - vec2<i32>(lid.xy) - vec2<i32>(1);
    for (var y = 0; y < 18; y = y + 1) {
        for (var x = 0; x < 18; x = x + 1) {
            let sp = clamp(base + vec2<i32>(x, y), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
            tile[y][x] = textureLoad(readTexture, sp, 0).rgb;
        }
    }
    workgroupBarrier();

    // FIX: bounds guard after the barrier (uniform control flow).
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let lx = i32(lid.x) + 1; let ly = i32(lid.y) + 1;
    let edgeC = edgeAt(lx, ly);

    // ── Idea 1: edge-energy dilation — the edge is also measured at the four
    // tile neighbours and the weighted max bleeds it one texel outward.
    let edgeN = max(max(edgeAt(lx - 1, ly), edgeAt(lx + 1, ly)), max(edgeAt(lx, ly - 1), edgeAt(lx, ly + 1)));
    var edge = max(edgeC, edgeN * 0.65);

    // Signed luma gradient → edge tangent for the stretched hex (Idea 3).
    let gxs = luma(tileAt(lx + 1, ly)) - luma(tileAt(lx - 1, ly));
    let gys = luma(tileAt(lx, ly + 1)) - luma(tileAt(lx, ly - 1));
    let gmag = length(vec2<f32>(gxs, gys));
    let tangent = select(vec2<f32>(1.0, 0.0), vec2<f32>(-gys, gxs) / max(gmag, 1e-5), gmag > 1e-5);
    let stretch = smoothstep(0.0, 0.06, gmag);

    // Mouse hotspot boosts edge response near the cursor (FIX: ascending smoothstep).
    let mouse = u.zoom_config.yz;
    edge *= 1.0 + (1.0 - smoothstep(0.0, 0.2, distance(uv, mouse))) * 2.0 * (1.0 + bass * 0.5);

    // Early-exit hint: pixels with negligible edge and no mouse proximity can
    // still emit a dim ambient glow, but we skip the expensive ripple loop.
    let edgeThreshold = 0.015;
    let hasEdge = step(edgeThreshold, edge);
    let nearMouse = step(distance(uv, mouse), 0.25);

    // Diffusion radius with audio-reactive expansion.
    let radius = (0.003 + p2 * 0.015) * (1.0 + bass * 0.2);
    let lod = glowLOD(radius, res);

    // Hex-bokeh sampled glow (Ideas 2 + 3 live inside hexGlow).
    let glow = hexGlow(uv, radius, lod, tangent, stretch);

    // Neon emission color derived from edge magnitude and color-shift param.
    var emission = vec3<f32>(edge * 4.0, edge * (1.1 - p4) * 3.0, edge * (0.3 + p4) * 5.0) * (1.0 + p1);
    emission = mix(emission, glow * edge * 5.0 * (1.0 + treble), 0.5);

    // Click ripple field. The branchless `hasEdge | nearMouse` gate keeps the
    // loop from adding energy in flat regions. FIX: amplitude 1 at the default
    // Ripple Strength (p3 * 2), age from r.z, loop capped at rippleCount.
    var ripple = vec3<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let a = time - r.z;
        let hit = step(0.0, r.z) * step(0.0, a) * step(a, 2.0);
        let pulse = sin(distance(uv, r.xy) * 50.0 - a * 10.0) * exp(-a) * hit;
        let gated = pulse * max(hasEdge, nearMouse);
        ripple += vec3<f32>(gated * (1.0 + p3), gated * 0.7, gated * 1.3);
    }
    emission += ripple * (p3 * 2.0);

    emission = aces(max(emission, vec3<f32>(0.0)) * (1.0 + bass * 0.2));
    let intensity = luma(emission);
    let alpha = clamp(intensity * (0.2 + p1 * 0.6), 0.0, 0.95);

    // Depth-aware compositing: neon glow softens the depth buffer where it is
    // brightest, letting the effect sit on top of the scene in the slot chain.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOut = depth * (1.0 - alpha * 0.5);

    let dither = (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;

    let outCol = vec4<f32>(emission + dither, alpha);
    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
