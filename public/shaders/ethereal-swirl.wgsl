// ────────────────────────────────────────────────────────────────────────────────
//  Ethereal Swirl – a 4-D color-space vortex
//  Multi-layer fractal noise creates billowy clouds with viscous swirling motion.
//  Depth acts as a curvature tensor, hue is a physical dimension that folds,
//  and feedback creates silky trails like a living dreamscape.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var historyBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var unusedBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var historyTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
    zoom_params: vec4<f32>,       // x=cloudScale, y=flowSpeed, z=colorSpeed, w=persistence
    zoom_config: vec4<f32>,       // x=depthWarpStr, y=turbulenceAmt, z=detailMix, w=blendStr
    ripples:     array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Utility functions
// ─────────────────────────────────────────────────────────────────────────────
fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

// Fractal Brownian Motion – 2-D
fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 2.0;
    for (var i: i32 = 0; i < 5; i = i + 1) {
        value = value + amp * (hash2(p * freq) - 0.5);
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

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute entry point
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = textureDimensions(videoTex);
    let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
        return;
    }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;

    // ────────────────────────────────────────────────────────────────────────
    //  1️⃣  Parameters
    // ────────────────────────────────────────────────────────────────────────
    let cloudScale = u.zoom_params.x * 7.0 + 1.0;           // 1 - 8
    let flowSpeed = u.zoom_params.y * 0.4;                   // 0 - 0.4
    let colorSpeed = u.zoom_params.z * 0.2;                  // 0 - 0.2
    let persistence = clamp(u.zoom_params.w * 0.95, 0.0, 0.95);
    let depthWarpStr = u.zoom_config.x * 0.1;               // 0 - 0.1
    let turbulenceAmt = u.zoom_config.y * 0.15 + 0.05;      // 0.05 - 0.2
    let detailMix = u.zoom_config.z * 0.5 + 0.25;           // 0.25 - 0.75
    let blendStr = u.zoom_config.w * 0.5 + 0.3;             // 0.3 - 0.8

    // ────────────────────────────────────────────────────────────────────────
    //  2️⃣  Flow field – a swirling vector field derived from FBM
    // ────────────────────────────────────────────────────────────────────────
    // Base flow: a low-frequency noise that drives the main swirl
    let baseFlow = vec2<f32>(
        fbm(uv * cloudScale * 0.3 + vec2<f32>(time * flowSpeed * 0.1, 0.0)),
        fbm(uv * cloudScale * 0.3 + vec2<f32>(0.0, time * flowSpeed * 0.15))
    );

    // Secondary flow: adds turbulence to the base flow
    let turb = vec2<f32>(
        fbm(uv * cloudScale * 1.2 + baseFlow * 2.5 + vec2<f32>(time * flowSpeed * 0.2, 0.0)),
        fbm(uv * cloudScale * 1.2 + baseFlow * 2.5 + vec2<f32>(0.0, time * flowSpeed * 0.25))
    );

    // Final flow vector
    let flowVec = baseFlow * 0.2 + turb * turbulenceAmt;

    // ────────────────────────────────────────────────────────────────────────
    //  3️⃣  Depth-based curvature
    // ────────────────────────────────────────────────────────────────────────
    let depthVal = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    // Farther objects are pulled further into the color manifold
    let depthWarp = depthVal * depthWarpStr;

    // ────────────────────────────────────────────────────────────────────────
    //  4️⃣  Distorted UV – combine flow and depth
    // ────────────────────────────────────────────────────────────────────────
    let distortedUV = uv + flowVec + depthWarp * flowVec;

    // ────────────────────────────────────────────────────────────────────────
    //  5️⃣  Cloud density – multi-layer FBM
    // ────────────────────────────────────────────────────────────────────────
    // Base cloud layer
    let cloudBase = fbm(distortedUV * cloudScale);
    // Detail layer
    let cloudDetail = fbm(distortedUV * cloudScale * 3.0 + vec2<f32>(time * 0.1, time * 0.07));
    // Combine and smooth
    let cloudRaw = mix(cloudBase, cloudDetail, detailMix);
    let cloudDensity = smoothstep(0.2, 0.7, abs(cloudRaw) * 3.0);

    // ────────────────────────────────────────────────────────────────────────
    //  6️⃣  Rainbow gradient – hue is a physical dimension
    // ────────────────────────────────────────────────────────────────────────
    // Base hue that slowly drifts
    let baseHue = fract(distortedUV.x + distortedUV.y * 0.3 + time * colorSpeed);
    // Modulate hue by cloud density to create "rainbow-rain"
    let hue = fract(baseHue + cloudDensity * 0.2);

    // Saturation and value driven by source luminance
    let srcColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let luminance = dot(srcColor, vec3<f32>(0.2126, 0.7152, 0.0722));
    let sat = mix(0.6, 1.0, luminance);
    let val = mix(0.4, 1.0, luminance);

    let cloudColor = hsv2rgb(hue, sat, val);

    // ────────────────────────────────────────────────────────────────────────
    //  7️⃣  Blend clouds with the original footage
    // ────────────────────────────────────────────────────────────────────────
    let blendFactor = cloudDensity * smoothstep(0.1, 0.5, luminance) * blendStr;
    let blendedColor = mix(srcColor, cloudColor, blendFactor);

    // ────────────────────────────────────────────────────────────────────────
    //  8️⃣  Feedback loop – create silky trails
    // ────────────────────────────────────────────────────────────────────────
    let prevFrame = textureSampleLevel(historyTex, videoSampler, uv, 0.0).rgb;
    let finalColor = mix(blendedColor, prevFrame, persistence);

    // Store the current frame for the next pass
    textureStore(historyBuf, gid.xy, vec4<f32>(finalColor, 1.0));

    // ────────────────────────────────────────────────────────────────────────
    //  9️⃣  Output
    // ────────────────────────────────────────────────────────────────────────
    textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
