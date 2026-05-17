// ═══════════════════════════════════════════════════════════════════
//  Entropy Grid
//  Category: image
//  Features: mouse-driven, audio-reactive, audio-driven
//  Complexity: High
//  Chunks From: Algorithmist upgrade — domain-warped FBM, Voronoi F2-F1, Clifford attractor
//  Created: 2026-05-10
//  By: Phase A Upgrade Agent
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

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
            if (d < F1) { F2 = F1; F1 = d; } else if (d < F2) { F2 = d; }
        }
    }
    return F2 - F1;
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    return vec2<f32>(sin(a * p.y) + c * cos(a * p.x), sin(b * p.x) + d * cos(b * p.y));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);
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

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let reactiveChaos = clamp(chaos * (1.0 + bass * 0.5 + mids * 0.25), 0.0, 1.0);

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

    let sampleUV = uv + offset * influence;
    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    let effectIntensity = influence * reactiveChaos;
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(color.a, clamp(luma * 0.35 + 0.65 + cellRidge * 0.2, 0.4, 1.0), effectIntensity);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color.rgb, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
