// ═══════════════════════════════════════════════════════════════════
//  Data Slicer Interactive — Algorithmist Upgrade (2026-07-21)
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-feedback,
//            depth-aware, chromatic-aberration, aces-tone-map,
//            lod-noise, early-exit, branchless-ripple, field-cache,
//            fbm-jitter, shockwave-slice-burst, torn-edge-glow
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
const EPS: f32 = 1e-4;

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

fn fbmLod(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

// Domain warp: feed fBM back into fBM for organic jitter flow
fn domainWarp(p: vec2<f32>, warpStrength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbmLod(p, octaves), fbmLod(p + vec2<f32>(5.2, 1.3), octaves));
    return p + warpStrength * q;
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

    let audio = plasmaBuffer[0];
    let bassRaw = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Bass envelope readback with smooth attack/release
    let prevBass = prev.a;
    let attackK = select(0.15, 0.8, bassRaw > prevBass);
    let bass = mix(prevBass, bassRaw, attackK);

    // ── Slider params (JSON updatedParams index 0–3) ─────────────
    let densityParam = u.zoom_params.x;   // 0: Slice Density
    let dispParam    = u.zoom_params.y;   // 1: Displacement
    let jitterParam  = u.zoom_params.z;   // 2: Jitter Amount
    let shockParam   = u.zoom_params.w;   // 3: Shockwave Strength

    // Bass drives slice density, mids drive displacement magnitude
    let sliceCountBase = mix(4.0, 32.0, densityParam);
    let sliceCount = sliceCountBase * (1.0 + bass * 0.5);
    let sliceWidth = 0.03;
    let fbmWarpAmt = 0.03;
    let colorShift = 0.02;
    let dispMag = mix(0.05, 0.35, dispParam) * (1.0 + mids * 0.8);
    let jitterAmt = jitterParam * 0.25;
    let shockStrength = mix(0.0, 2.0, shockParam);

    // Gravity well (aspect-corrected, boosted while mouse is down)
    let aspect = res.x / max(res.y, 1.0);
    let dMouse = (uv01 - mouse) * vec2<f32>(aspect, 1.0);
    let distMouse = length(dMouse);
    let gravity = (1.0 - smoothstep(0.0, 0.35, distMouse)) * (1.0 + mouseDown * 0.5);

    // Slice construction
    let sliceIndex = floor(uv01.y * sliceCount);
    let invSliceCount = 1.0 / max(sliceCount, EPS);
    let sliceY = sliceIndex * invSliceCount;
    let nextSliceY = (sliceIndex + 1.0) * invSliceCount;

    // LOD: fewer noise octaves far from the mouse interest point
    let lodOct = select(2, 4, distMouse < 0.4);

    // FBM-warped slice edges
    let edgeNoise = fbmLod(vec2<f32>(uv01.x * 8.0, sliceY * 4.0 + time * 0.3), lodOct);
    let warpedSliceWidth = sliceWidth + edgeNoise * fbmWarpAmt;
    let distToSlice = min(abs(uv01.y - sliceY), abs(uv01.y - nextSliceY));
    let strength = 1.0 - smoothstep(0.0, max(warpedSliceWidth, EPS), distToSlice);

    // Early exit: no slice or gravity influence — passthrough with valid state
    if (strength < 0.005 && gravity < 0.01) {
        let base = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
        let alpha = clamp(luma(base) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3);
        textureStore(writeTexture, pixel, vec4<f32>(base, alpha));
        textureStore(dataTextureA, pixel, vec4<f32>(base, bass));
        textureStore(dataTextureB, pixel, vec4<f32>(0.0, 0.0, 0.0, bass));
        textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }

    // ── Click-triggered slice bursts + expanding shockwave rings ──
    // Each mouse-down ripple spawns a ring that locally amplifies slice
    // offsets as it travels outward (branchless accumulation, no divergence).
    var burst = 0.0;
    var shock = 0.0;
    let rippleCount = u32(u.config.y);
    let invAgeMax = 1.0 / 1.2;
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let rDist = length(uv01 - rp.xy);
        let rAge = time - rp.z;
        let rRadius = rAge * 0.5;
        let rBand = abs(rDist - rRadius);
        let inRing = f32(rBand < 0.04 && rAge >= 0.0 && rAge < 1.2);
        let decay = clamp(1.0 - rAge * invAgeMax, 0.0, 1.0);
        let rStrength = max(rp.w, 0.2);
        burst += inRing * decay * rStrength * 0.15 * sin(rDist * 50.0 - rAge * 20.0);
        // Sharp ring envelope peaks exactly on the wavefront
        shock += smoothstep(0.04, 0.0, rBand) * decay * rStrength;
    }
    shock *= shockStrength;

    // Quantized jitter modulated by mids
    let quant = mix(20.0, 70.0, mids);
    let quantY = floor(uv01.y * quant) / quant;
    let n = valueNoise(vec2<f32>(quantY * 10.0, time * 3.0 * (1.0 + treble)));

    // ── Branchless FBM slice-offset jitter ───────────────────────
    // Domain-warped smooth noise perturbs each slice's displacement;
    // blended with the quantized jitter via mix/select, no branches.
    let jitterWarp = domainWarp(vec2<f32>(uv01.x * 6.0, sliceY * 12.0), 0.6, 2);
    let jitterNoise = fbmLod(vec2<f32>(jitterWarp.x, sliceY * 8.0 + time * 0.6), 3);
    let jitter = (jitterNoise - 0.5) * 2.0 * jitterAmt;
    let jitterBlend = clamp(jitterParam * 1.5, 0.0, 1.0);

    // Displacement: quantized noise + fbm jitter + burst, shock-amplified
    var offset = (n - 0.5) * dispMag * strength;
    offset = mix(offset, offset + jitter * strength, jitterBlend);
    offset += burst * strength * (1.0 + shock * 0.5);
    offset *= 1.0 + shock;

    // Alternate slice travel direction (branchless per-slice sign flip)
    let dirSign = select(-1.0, 1.0, fract(sliceIndex * 0.5) < 0.25);
    offset *= mix(1.0, dirSign, 0.8);
    var split = colorShift * strength * (1.0 + bass * 2.0) * (1.0 + shock * 0.75);
    let alphaMod = 1.0 - strength * 0.35;

    // Gravity deformation + depth parallax
    offset += gravity * 0.02 * sin(uv01.x * 20.0 + time);
    split *= 1.0 + depth * 0.5;

    // Radial chromatic aberration
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

    // Torn-edge glow: hot rim pinned to the FBM-warped slice boundary
    let edgeT = 1.0 - smoothstep(0.0, max(warpedSliceWidth * 0.25, EPS), distToSlice);
    let edgeGlow = edgeT * strength * (0.25 + treble * 0.4 + shock * 0.3);
    color += vec3<f32>(edgeGlow * 0.9, edgeGlow * 0.55, edgeGlow * 1.1);

    // Scanline shimmer inside active slices
    let scan = 1.0 + 0.06 * sin(uv01.y * res.y * PI) * strength;
    color *= scan;

    // Treble sparkle + shockwave flash + depth boost + tone map
    color += vec3<f32>(treble * strength * 0.25, treble * strength * 0.15, treble * strength * 0.1);
    color += vec3<f32>(shock * strength * 0.15);
    color = mix(color, color * 1.3, depth * strength * 0.5);
    color = acesToneMap(color * (0.9 + mids * 0.2));

    // Semantic alpha: interaction intensity
    let alpha = clamp(luma(color) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3) * alphaMod;

    // Write outputs: trail cache in A, field cache in B, depth pass-through
    let trail = mix(prevCol.rgb * 0.92, color, 0.15 + bass * 0.15 + shock * 0.1);
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, bass));
    textureStore(dataTextureB, pixel, vec4<f32>(strength, offset, split, bass));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
