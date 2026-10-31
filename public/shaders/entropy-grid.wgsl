// ═══════════════════════════════════════════════════════════════════
//  Entropy Grid
//  Category: image
//  Features: mouse-driven, audio-reactive, audio-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-23, 2026-10-31
//  Ideas: cell-locked sample; grid-boundary cracks
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

const PHI = 1.61803398874989484820;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5;
    var s = 0.0;
    var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * vnoise(q);
        q = q * 2.02;
        a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2)), fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0 * r);
}

fn voronoiF2minusF1(p: vec2<f32>) -> f32 {
    var F1 = 1e9;
    var F2 = 1e9;
    let ip = floor(p);
    for (var i = -1; i <= 1; i = i + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            let n = ip + vec2<f32>(f32(i), f32(j));
            let d = length(p - n - hash21(n));
            let lt_F1 = d < F1;
            F2 = select(select(F2, d, d < F2), F1, lt_F1);
            F1 = select(F1, d, lt_F1);
        }
    }
    return F2 - F1;
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    return vec2<f32>(sin(a * p.y) + c * cos(a * p.x), sin(b * p.x) + d * cos(b * p.y));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let uv = vec2<f32>(global_id.xy) / vec2<f32>(u.config.zw);
    let aspect = u.config.z / max(u.config.w, 1.0);
    let uv_c = vec2<f32>(uv.x * aspect, uv.y);
    let mouse = u.zoom_config.yz;
    let mouse_c = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uv_c, mouse_c);
    let t = u.config.x;

    let gridSize = mix(8.0, 80.0, u.zoom_params.x);
    let chaos = u.zoom_params.y;
    let radius = max(u.zoom_params.z, 0.001);
    let invert = u.zoom_params.w > 0.5;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let reactiveChaos = clamp(chaos * (1.0 + bass * 0.5 + mids * 0.25 + treble * 0.1), 0.0, 1.0);

    let gridUV = floor(uv * gridSize);
    let cellCenter = (gridUV + 0.5) / max(gridSize, 0.001);

    let warpSeed = gridUV * 0.37 + t * 0.1;
    let warp = warpedFBM(warpSeed, t) * reactiveChaos;

    let voronoiP = gridUV * 0.15 + vec2<f32>(t * 0.05, t * 0.03);
    let cellRidge = voronoiF2minusF1(voronoiP);

    let attractorScale = mix(0.5, 4.0, reactiveChaos);
    let attr = clifford((uv - cellCenter) * attractorScale + t * 0.2, 1.4, -1.7, 1.1, -0.7);
    let attrStrength = smoothstep(radius * 2.0, 0.0, dist) * reactiveChaos;

    let offset = (vec2<f32>(warp, warp * PHI) * 0.12 + vec2<f32>(cellRidge) * 0.08 * reactiveChaos + attr * 0.06 * attrStrength) * (1.0 + bass);

    var influence = smoothstep(radius, radius * 0.3, dist);
    influence = select(influence, 1.0 - influence, invert);

    // ── Idea 1: cell-locked sample ──────────────────────────────────
    // Chaos 0 keeps the continuous warp. As chaos rises inside the
    // influence, each cell collapses onto one sample.
    let freeUV = clamp(uv + offset * influence, vec2<f32>(0.0), vec2<f32>(1.0));
    let lockedUV = clamp(cellCenter + offset * influence, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleUV = mix(freeUV, lockedUV, clamp(reactiveChaos, 0.0, 1.0) * influence);
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // ── Idea 2: grid-boundary cracks ────────────────────────────────
    let fcell = fract(uv * gridSize);
    let edge = min(min(fcell.x, 1.0 - fcell.x), min(fcell.y, 1.0 - fcell.y));
    let crack = (1.0 - smoothstep(0.0, 0.07, edge)) * reactiveChaos * influence;
    color = vec4<f32>(mix(color.rgb, color.rgb * vec3<f32>(0.12, 0.13, 0.16), crack), color.a);

    let effectIntensity = influence * reactiveChaos;
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(color.a, clamp(luma * 0.35 + 0.65 + cellRidge * 0.2 + crack * 0.15 + mids * 0.05 + treble * 0.03, 0.4, 1.0), effectIntensity);
    let outRgb = aces(max(color.rgb, vec3<f32>(0.0)));
    let finalColor = vec4<f32>(outRgb, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
