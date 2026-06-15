// ═══ Quad Mirror ═══════════════════════════════════════════════════
//  Category: geometric
//  Features: mouse-driven, geometry, upgraded-rgba, fbm-domain-warp,
//            audio-reactive, seam-warp, chromatic-aberration,
//            aces-tone-map, temporal-feedback, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-06-14

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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MIN_ZOOM: f32 = 0.1;

// ── Canonical noise library ───────────────────────────────────────
fn hashf(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453); }
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i: i32 = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}

// ── Color & rotation helpers ──────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn rot2(angle: f32) -> mat2x2<f32> {
    let c = cos(angle); let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}
fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01  = vec2<f32>(pixel) / res;
    let time  = u.config.x;
    let mouse = u.zoom_config.yz;
    let p1    = u.zoom_params.x;
    let p2    = u.zoom_params.y;
    let p3    = u.zoom_params.z;
    let p4    = u.zoom_params.w;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;
    let prev   = textureLoad(dataTextureC, pixel, 0);

    // ── Parameter mapping ─────────────────────────────────────────
    // p1,p2 = horizontal/vertical mirror offsets
    // p3    = seam warp strength
    // p4    = base rotation (animated by bass-driven spin)
    let hOffset = (p1 - 0.5) * 0.4;
    let vOffset = (p2 - 0.5) * 0.4;
    let seamWarpAmt = p3 * 0.05;
    let rotation = p4 * TAU + time * 0.1 * (1.0 + bass * 0.3);
    let warpShimmer = seamWarpAmt * (1.0 + treble * 0.5);

    // ── Quad mirror transform ─────────────────────────────────────
    // Rotate UV around mouse, then mirror on both axes to create 4-way symmetry.
    let rel = uv01 - mouse;
    let r = rot2(rotation) * rel;
    let zoom = max(MIN_ZOOM, 0.5 + mids * 0.1);
    var sampleUV = mouse - vec2<f32>(abs(r.x + hOffset), abs(r.y + vOffset)) / zoom;

    // ── Seam warp with compute-safe anti-moiré LOD bias ───────────
    // dpdx/dpdy are fragment-only, so we approximate procedural LOD from
    // pixel scale and zoom. This keeps high-frequency fbm from shimmering
    // when the mirrored image is small on screen.
    let pxScale = 1.0 / max(res.x, res.y);
    let lod = clamp(log2(pxScale * zoom * 200.0), 0.0, 4.0);
    let noiseFreq = 20.0 * exp2(-lod);

    let seamH = abs(r.x);
    let seamV = abs(r.y);
    let nearSeamH = smoothstep(0.0, 0.05 * zoom, seamH);
    let nearSeamV = smoothstep(0.0, 0.05 * zoom, seamV);
    let nearSeam = max(1.0 - nearSeamH, 1.0 - nearSeamV);

    sampleUV = domainWarp(sampleUV * noiseFreq + time, warpShimmer * nearSeam, 3);

    // ── Sample and color grade ────────────────────────────────────
    var color = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let y = luma(color.rgb);
    let satBoost = 1.0 + mids * 0.4;
    color = vec4<f32>(mix(vec3<f32>(y), color.rgb, satBoost), color.a);

    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    color = vec4<f32>(genChromaticShift(color.rgb, uv01, caStr, time), color.a);
    color = vec4<f32>(acesToneMap(color.rgb * (0.9 + mids * 0.2)), color.a);

    // ── Semantic alpha & temporal feedback ────────────────────────
    let seamAlphaReduction = warpShimmer * nearSeam * 2.0;
    let alpha = clamp(max(0.25, color.a - seamAlphaReduction) * (0.6 + depth * 0.4), 0.2, 0.98);

    let decay = 0.96 - treble * 0.02;
    let trail = mix(prev.rgb * decay, color.rgb, 0.2 + bass * 0.1);

    textureStore(writeTexture, pixel, vec4<f32>(trail, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, alpha));
}
