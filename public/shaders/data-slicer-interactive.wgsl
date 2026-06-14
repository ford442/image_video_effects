// ═══════════════════════════════════════════════════════════════════
//  Data Slicer Interactive — June 2026 Interactivist Upgrade
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-feedback,
//            depth-aware, chromatic-aberration, aces-tone-map
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Core math ────────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Entry ────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let bassRaw = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Bass envelope stored in dataTextureC alpha for smooth attack/release
    let prevBass = prev.a;
    let k = select(0.15, 0.8, bassRaw > prevBass);
    let bass = mix(prevBass, bassRaw, k);

    // Parameters
    let sliceCountBase = mix(4.0, 32.0, u.zoom_params.x);
    let sliceCount = sliceCountBase * (1.0 + bass * 0.5);
    let sliceWidth = mix(0.005, 0.08, u.zoom_params.y);
    let fbmWarpAmt = u.zoom_params.z * 0.06;
    let colorShift = u.zoom_params.w * 0.1;

    // Gravity well pulls slices toward mouse
    let dMouse = uv01 - mouse;
    let distMouse = length(dMouse);
    let gravity = 1.0 - smoothstep(0.0, 0.35, distMouse);

    // Slice construction
    let sliceIndex = floor(uv01.y * sliceCount);
    let sliceY = sliceIndex / sliceCount;
    let nextSliceY = (sliceIndex + 1.0) / sliceCount;

    // FBM warp on slice edges
    let edgeNoise = fbm(vec2<f32>(uv01.x * 8.0, sliceY * 4.0 + time * 0.3), 4);
    let warpedSliceWidth = sliceWidth + edgeNoise * fbmWarpAmt;

    let distToSlice = min(abs(uv01.y - sliceY), abs(uv01.y - nextSliceY));
    let strength = 1.0 - smoothstep(0.0, max(warpedSliceWidth, 1e-3), distToSlice);

    // Click-triggered slice bursts
    var burst = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let rDist = length(uv01 - rp.xy);
        let rAge = time - rp.z;
        let rRad = rAge * 0.5;
        let rBand = abs(rDist - rRad);
        let isActive = select(0.0, 1.0, rBand < 0.04 && rAge >= 0.0 && rAge < 1.2);
        let decay = clamp(1.0 - rAge / 1.2, 0.0, 1.0);
        burst += isActive * decay * 0.15 * sin(rDist * 50.0 - rAge * 20.0);
    }

    // Quantized jitter modulated by mids
    let quant = mix(20.0, 70.0, mids);
    let quantY = floor(uv01.y * quant) / quant;
    let t = time * 3.0 * (1.0 + treble);
    let n = valueNoise(vec2<f32>(quantY * 10.0, t));

    var offset = (n - 0.5) * 0.3 * strength + burst * strength;
    var split = colorShift * strength * (1.0 + bass * 2.0);
    let alphaMod = 1.0 - strength * 0.35;

    // Gravity deformation + depth parallax on RGB split
    offset += gravity * 0.02 * sin(uv01.x * 20.0 + time);
    split *= 1.0 + depth * 0.5;

    // Radial chromatic aberration folded into RGB channel offsets
    let center = vec2<f32>(0.5);
    let delta = uv01 - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * inverseSqrt(lenSq);
    let caStr = (0.003 * (1.0 + bass) + depth * 0.001) * strength;

    let rUv = clamp(uv01 + vec2<f32>(offset + split, 0.0) + dir * caStr, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUv = clamp(uv01 + vec2<f32>(offset - split, 0.0) - dir * caStr * 0.6, vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv01 + vec2<f32>(offset, 0.0), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUv, 0.0).b;

    // Temporal feedback trails
    let feedbackUV = clamp(uv01 + vec2<f32>(offset * 0.3, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let prevCol = textureSampleLevel(dataTextureC, u_sampler, feedbackUV, 0.0);
    let fbAmt = 0.12 * strength + mouseDown * 0.25;
    var color = vec3<f32>(r, g, b);
    color = mix(color, prevCol.rgb, fbAmt);

    // Treble sparkle additive
    color += vec3<f32>(treble * strength * 0.25, treble * strength * 0.15, treble * strength * 0.1);

    // Depth-aware intensity boost
    color = mix(color, color * 1.3, depth * strength * 0.5);

    // ACES tone map
    color = acesToneMap(color * (0.9 + mids * 0.2));

    // Semantic alpha: interaction intensity (slice strength + gravity + depth)
    let alpha = clamp(luma(color) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3) * alphaMod;

    // Write outputs
    let decay = 0.92;
    let trail = mix(prevCol.rgb * decay, color, 0.15 + bass * 0.15);
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, bass));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
