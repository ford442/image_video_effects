// ────────────────────────────────────────────────────────────────────────────────
//  Ethereal Swirl – a 4-D color-space vortex
//  Multi-layer fractal noise creates billowy clouds with viscous swirling motion.
//  Depth acts as a curvature tensor, hue is a physical dimension that folds,
//  and feedback creates silky trails like a living dreamscape.
//  Category: distortion
//  Features: audio-reactive, temporal, upgraded-rgba
//  Upgraded: 2026-10-05
//  Ideas: 1) billow clouds (interpolated value-noise FBM, |n| billow on upper octaves) 2) advected trails (C read upstream along the FBM flow, persistence = decay) 3) depth-folded hue (hue offset by depth × cloud density)
//  A packing: ACES display RGBA (alpha = footage coverage × cloud density); trails mix post-ACES
// ────────────────────────────────────────────────────────────────────────────────
#include "_prelude.wgsl"

// zoom_params: x=cloudScale, y=flowSpeed, z=colorSpeed, w=persistence (JSON order).
// HEAD's struct swapped zoom_params/zoom_config, so sliders drove the secondary knobs
// below and the primary four read time/mouse. Secondary knobs are now fixed at the
// value they had with a slider at its 0.5 default.
const DEPTH_WARP_STR: f32 = 0.05;
const TURBULENCE_AMT: f32 = 0.125;
const DETAIL_MIX: f32 = 0.5;
const BLEND_STR: f32 = 0.55;

// ─────────────────────────────────────────────────────────────────────────────
//  Utility functions
// ─────────────────────────────────────────────────────────────────────────────
fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

// Idea 1: smooth value noise on an integer lattice (HEAD hashed the continuous
// coordinate, which is per-pixel white noise, so the "clouds" were grain).
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Fractal Brownian Motion – 2-D, centred on 0 like HEAD's.
// Idea 1: octaves 0-1 are plain value noise (rolling bulk), octaves 2+ are billowed
// (|2n-1|) so the domain warp folds them into cauliflower cloud edges.
fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 2.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        let n = vnoise(p * freq + vec2<f32>(f32(i) * 17.3, f32(i) * 9.1));
        var oct = n - 0.5;
        if (i >= 2) {
            oct = abs(n * 2.0 - 1.0) - 0.5;
        }
        value = value + amp * oct;
        freq = freq * 2.1;
        amp = amp * 0.5;
    }
    return value;
}

// HSV → RGB
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Exact history read: bilinear by hand from four textureLoads (no sampler on rgba32float),
// so sub-pixel advection still moves the trail.
fn loadHistory(pos: vec2<f32>, dims: vec2<f32>) -> vec4<f32> {
    let maxC = vec2<i32>(dims) - vec2<i32>(1);
    let px = clamp(pos * dims - 0.5, vec2<f32>(0.0), dims - 1.0);
    let i0 = vec2<i32>(floor(px));
    let i1 = min(i0 + vec2<i32>(1), maxC);
    let f = px - floor(px);
    let c00 = textureLoad(dataTextureC, i0, 0);
    let c10 = textureLoad(dataTextureC, vec2<i32>(i1.x, i0.y), 0);
    let c01 = textureLoad(dataTextureC, vec2<i32>(i0.x, i1.y), 0);
    let c11 = textureLoad(dataTextureC, i1, 0);
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute entry point
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let aspect = dims.x / max(dims.y, 1.0);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ────────────────────────────────────────────────────────────────────────
    //  1️⃣  Parameters
    // ────────────────────────────────────────────────────────────────────────
    let cloudScale = u.zoom_params.x * 7.0 + 1.0;           // 1 - 8
    let flowSpeed = u.zoom_params.y * 0.4;                   // 0 - 0.4
    let colorSpeed = u.zoom_params.z * 0.2;                  // 0 - 0.2
    let persistence = clamp(u.zoom_params.w * 0.95, 0.0, 0.95);

    // Noise lives in aspect-correct space so clouds are not stretched on wide frames.
    let np = vec2<f32>(uv.x * aspect, uv.y);
    // Bass shoves the flow phase forward additively (never scales absolute time).
    let flowT = time * flowSpeed + bass * 0.15;

    // ────────────────────────────────────────────────────────────────────────
    //  2️⃣  Flow field – a swirling vector field derived from FBM
    // ────────────────────────────────────────────────────────────────────────
    let baseFlow = vec2<f32>(
        fbm(np * cloudScale * 0.3 + vec2<f32>(flowT * 0.1, 0.0)),
        fbm(np * cloudScale * 0.3 + vec2<f32>(0.0, flowT * 0.15) + vec2<f32>(5.2, 1.3))
    );

    let turb = vec2<f32>(
        fbm(np * cloudScale * 1.2 + baseFlow * 2.5 + vec2<f32>(flowT * 0.2, 0.0)),
        fbm(np * cloudScale * 1.2 + baseFlow * 2.5 + vec2<f32>(0.0, flowT * 0.25) + vec2<f32>(8.3, 2.8))
    );

    let flowVec = baseFlow * 0.2 + turb * TURBULENCE_AMT;

    // ────────────────────────────────────────────────────────────────────────
    //  3️⃣  Depth-based curvature
    // ────────────────────────────────────────────────────────────────────────
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthWarp = depthVal * DEPTH_WARP_STR;

    // ────────────────────────────────────────────────────────────────────────
    //  4️⃣  Distorted UV – combine flow and depth
    // ────────────────────────────────────────────────────────────────────────
    let distortedUV = uv + flowVec + depthWarp * flowVec;
    let distortedP = vec2<f32>(distortedUV.x * aspect, distortedUV.y);

    // ────────────────────────────────────────────────────────────────────────
    //  5️⃣  Cloud density – multi-layer FBM
    // ────────────────────────────────────────────────────────────────────────
    let cloudBase = fbm(distortedP * cloudScale);
    let cloudDetail = fbm(distortedP * cloudScale * 3.0 + vec2<f32>(time * 0.1, time * 0.07));
    let cloudRaw = mix(cloudBase, cloudDetail, DETAIL_MIX + treble * 0.1);
    let cloudDensity = smoothstep(0.2, 0.7, abs(cloudRaw) * 3.0);

    // ────────────────────────────────────────────────────────────────────────
    //  6️⃣  Rainbow gradient – hue is a physical dimension
    // ────────────────────────────────────────────────────────────────────────
    let baseHue = fract(distortedUV.x + distortedUV.y * 0.3 + time * colorSpeed + mids * 0.05);
    // Idea 3: depth-folded hue — dense cloud near the camera swings round the colour
    // wheel away from the same cloud far away, so the hue reads as a layered volume.
    let depthFold = (depthVal - 0.5) * cloudDensity * 0.35;
    let hue = fract(baseHue + cloudDensity * 0.2 + depthFold + 1.0);

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let srcColor = src.rgb;
    let luminance = dot(srcColor, vec3<f32>(0.2126, 0.7152, 0.0722));
    let sat = mix(0.6, 1.0, luminance);
    let val = mix(0.4, 1.0, luminance);

    let cloudColor = hsv2rgb(hue, sat, val);

    // ────────────────────────────────────────────────────────────────────────
    //  7️⃣  Blend clouds with the original footage
    // ────────────────────────────────────────────────────────────────────────
    let blendFactor = clamp(cloudDensity * smoothstep(0.1, 0.5, luminance) * BLEND_STR * (1.0 + bass * 0.3), 0.0, 1.0);
    let blendedColor = mix(srcColor, cloudColor, blendFactor);

    // ACES on display RGB; history in C is already display, so trails mix post-ACES.
    let display = acesToneMap(blendedColor * 1.1);
    // Semantic alpha: footage coverage, thickened where cloud sits on it.
    let alphaNow = clamp(src.a * mix(0.75, 1.0, cloudDensity), 0.0, 1.0);

    // ────────────────────────────────────────────────────────────────────────
    //  8️⃣  Feedback loop – create silky trails
    // ────────────────────────────────────────────────────────────────────────
    // Idea 2: advected trails — read last frame upstream along the FBM flow so trails
    // stream with the clouds; persistence is the decay of what is carried.
    let upstream = uv - flowVec * (0.01 + flowSpeed * 0.04) * vec2<f32>(1.0 / aspect, 1.0);
    let prev = loadHistory(upstream, dims);
    let finalRGB = mix(display, prev.rgb, persistence);
    let finalA = mix(alphaNow, prev.a, persistence * 0.5);
    let outColor = vec4<f32>(finalRGB, finalA);

    // ────────────────────────────────────────────────────────────────────────
    //  9️⃣  Output
    // ────────────────────────────────────────────────────────────────────────
    textureStore(dataTextureA, vec2<i32>(gid.xy), outColor);
    textureStore(writeTexture, vec2<i32>(gid.xy), outColor);
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
