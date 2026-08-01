// ═══════════════════════════════════════════════════════════════════
//  spec-histogram-equalize
//  Category: image
//  Features: cooperative-workgroup, histogram, CLAHE
//  Complexity: High
//  Upgraded: 2026-05-23
//  upgraded-rgba
//  b21: real CLAHE clip + redistribute, tile seam blend, mouse
//       contrast lens, ripple clip pulses, display color -> A slot
// ═══════════════════════════════════════════════════════════════════
//  Real-Time Histogram Equalization via Workgroup Reduction
//  Computes a local histogram within each 16x16 workgroup tile, clips
//  every bin at the Clip Limit height, redistributes the clipped excess
//  uniformly across all bins, and remaps pixel intensities via the
//  clipped CDF (true CLAHE-style adaptive contrast enhancement).
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
  zoom_params: vec4<f32>,  // x=ClipLimit, y=Strength, z=TileBlend, w=ColorPreserve
  ripples: array<vec4<f32>, 50>,
};

var<workgroup> localHistogram: array<atomic<u32>, 256>;

@compute @workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(local_invocation_index) lidx: u32
) {
    let res = u.config.zw;
    let inBounds = gid.x < u32(res.x) && gid.y < u32(res.y);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let texel = 1.0 / res;
    let bass = plasmaBuffer[0].x;
    let time = u.config.x;
    let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);

    // Slider map (u.zoom_params):
    //   x = Clip Limit     -> CLAHE histogram clip height (1..8 counts/bin)
    //   y = Effect Strength-> blend original <-> equalized luminance
    //   z = Tile Blend     -> seam softening toward 4-tap neighbor remap
    //   w = Color Preserve -> hue-preserving luma scale vs plain RGB mix
    // Bass loosens contrast clip — beat opens up tonal range
    let clipLimit = mix(1.0, 8.0, u.zoom_params.x) * (1.0 + bass * 0.3);
    let strength = mix(0.0, 1.0, u.zoom_params.y);
    let tileBlend = mix(0.0, 1.0, u.zoom_params.z);
    let colorPreserve = mix(0.0, 1.0, u.zoom_params.w);

    // Mouse contrast lens: pointer peels open local contrast
    let mousePos = u.zoom_config.yz;
    let mouseDist = length((uv - mousePos) * aspect);
    let lensBoost = 0.3 * smoothstep(0.3, 0.0, mouseDist);
    let strengthEff = clamp(strength + lensBoost, 0.0, 1.0);

    // Ripple clip pulses: each click temporarily loosens the clip limit
    // near its point (~1.5s fade), popping the local tonal range.
    var clipPulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.5) {
            let rDist = length((uv - ripple.xy) * aspect);
            let fade = 1.0 - age / 1.5;
            clipPulse += smoothstep(0.25, 0.0, rDist) * fade;
        }
    }
    let clipLimitEff = clipLimit * (1.0 + clipPulse);
    let clipU = max(u32(clipLimitEff), 1u);

    // Phase 1: Clear histogram (cooperative clear)
    for (var i = lidx; i < 256u; i = i + 256u) {
        atomicStore(&localHistogram[i], 0u);
    }
    workgroupBarrier();

    // Read color and compute luma
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = clamp(dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114)), 0.0, 1.0);
    let bin = u32(luma * 255.0);

    // Phase 2: Vote into histogram
    atomicAdd(&localHistogram[bin], 1u);
    workgroupBarrier();

    // Phase 3: REAL CLAHE — clip each bin, redistribute the excess.
    // A single 256-iteration sweep per thread computes, for its own bin:
    //   cdfClip = sum over i<=bin of min(count[i], clipU)
    //   excess  = sum over all i of (count[i] - min(count[i], clipU))
    // The excess is spread uniformly over all 256 bins, so the
    // redistributed CDF at bin b additionally gains excess*(b+1)/256.
    let totalPixels = 256u; // 16x16 workgroup
    var cdfClip = 0u;
    var excess = 0u;
    for (var i = 0u; i < 256u; i = i + 1u) {
        let cnt = atomicLoad(&localHistogram[i]);
        let clipped = min(cnt, clipU);
        if (i <= bin) {
            cdfClip = cdfClip + clipped;
        }
        excess = excess + (cnt - clipped);
    }
    let cdfNorm = (f32(cdfClip) + f32(excess) * f32(bin + 1u) / 256.0) / f32(totalPixels);
    let equalizedLuma = clamp(cdfNorm, 0.0, 1.0);

    // Phase 4: Remap using the clipped + redistributed CDF
    let originalLuma = max(luma, 0.001);
    let scaleFactor = equalizedLuma / originalLuma;
    let scaleMix = mix(1.0, scaleFactor, strengthEff);

    // Blend between equalized and original
    var outColor: vec3<f32>;
    if (colorPreserve > 0.5) {
        // Preserve hue, adjust luminance
        outColor = color.rgb * scaleMix;
    } else {
        outColor = mix(color.rgb, color.rgb * scaleFactor, strengthEff);
    }

    // Tile Blend: soften 16x16 tile seams by mixing the result toward a
    // 4-tap neighbor average remapped with the same scale factor.
    // 0 = crisp per-tile CLAHE, 1 = spatially smoothed.
    if (tileBlend > 0.001) {
        let uvMin = vec2<f32>(0.0);
        let uvMax = vec2<f32>(1.0);
        let cL = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-texel.x, 0.0), uvMin, uvMax), 0.0).rgb;
        let cR = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), uvMin, uvMax), 0.0).rgb;
        let cD = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -texel.y), uvMin, uvMax), 0.0).rgb;
        let cU = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), uvMin, uvMax), 0.0).rgb;
        let neighborAvg = (cL + cR + cD + cU) * 0.25;
        outColor = mix(outColor, neighborAvg * scaleMix, tileBlend * 0.5);
    }

    // Tone map and clamp
    outColor = clamp(outColor, vec3<f32>(0.0), vec3<f32>(3.0));

    // Preserve input alpha. Display color goes to the A slot; the debug
    // quad (equalizedLuma, luma, scaleFactor, cdfNorm) moves to B.
    if (inBounds) {
        textureStore(writeTexture, gid.xy, vec4<f32>(outColor, color.a));
        textureStore(dataTextureA, gid.xy, vec4<f32>(outColor, color.a));
        textureStore(dataTextureB, gid.xy, vec4<f32>(equalizedLuma, luma, scaleFactor, cdfNorm));
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0, 0, 0.0));
    }
}
