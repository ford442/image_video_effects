// ═══════════════════════════════════════════════════════════════════
//  chromatic-crawler-structure
//  Category: advanced-hybrid
//  Features: chromatic-crawler, structure-tensor-flow, temporal
//  Ideas: Cauchy tendril bifurcation, photoelastic fringe birefringence, bioluminescent pulse waves
//  A packing: display RGBA (RGB=ACES display color, A=edge coherency confidence)
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

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.9))
    );
    p3 = fract(sin(p3) * 43758.5453);
    return p3;
}

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
    let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
    return dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
    var sum = vec4<f32>(0.0);
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let gx =
                -1.0 * sampleLuma(uv + offset, pixelSize, -1, -1) +
                -2.0 * sampleLuma(uv + offset, pixelSize, -1,  0) +
                -1.0 * sampleLuma(uv + offset, pixelSize, -1,  1) +
                 1.0 * sampleLuma(uv + offset, pixelSize,  1, -1) +
                 2.0 * sampleLuma(uv + offset, pixelSize,  1,  0) +
                 1.0 * sampleLuma(uv + offset, pixelSize,  1,  1);
            let gy =
                -1.0 * sampleLuma(uv + offset, pixelSize, -1, -1) +
                -2.0 * sampleLuma(uv + offset, pixelSize,  0, -1) +
                -1.0 * sampleLuma(uv + offset, pixelSize,  1, -1) +
                 1.0 * sampleLuma(uv + offset, pixelSize, -1,  1) +
                 2.0 * sampleLuma(uv + offset, pixelSize,  0,  1) +
                 1.0 * sampleLuma(uv + offset, pixelSize,  1,  1);
            let Ix2 = gx * gx;
            let Iy2 = gy * gy;
            let Ixy = gx * gy;
            sum += vec4<f32>(Ix2, Iy2, Ixy, 0.0);
        }
    }
    return sum / 9.0;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let coord = vec2<i32>(gid.xy);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let aspect = res.x / max(res.y, 1.0);

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let crawlSpeed = u.zoom_params.x * 2.0 + 0.5;
    let swapIntensity = u.zoom_params.y;
    let feedbackMix = u.zoom_params.z * 0.4 + 0.2;
    let flashRate = u.zoom_params.w * 20.0 + 5.0;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Mouse influence
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let toMouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let distMouse = length(toMouse);
    let mouseAttract = exp(-distMouse * 3.5) * (0.5 + bass * 0.5);

    // Structure tensor for flow-guided crawling
    let tensor = smoothTensor(uv, pixelSize);
    let Jxx = tensor.x;
    let Jyy = tensor.y;
    let Jxy = tensor.z;
    let trace = Jxx + Jyy;
    let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
    let lambda1 = (trace + diff) * 0.5;
    let lambda2 = (trace - diff) * 0.5;
    var eigenvec = vec2<f32>(1.0, 0.0);
    if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
        eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
    }
    let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);

    // Orthogonal normal to flow
    let eigenNormal = vec2<f32>(-eigenvec.y, eigenvec.x);

    // Flow-guided crawling offset with audio acceleration
    let t = time * crawlSpeed * (1.0 + bass * 0.35);
    let flowAngle = atan2(eigenvec.y, eigenvec.x);

    // IDEA 1: Cauchy chromatic tendril bifurcation
    // Red, green, and blue tendril branches propagate with differential dispersion offsets along flow and normal
    let crawlOffsetBase = vec2<f32>(
        sin(flowAngle + t * 5.0 + uv.x * 20.0) * 0.06 * coherency,
        cos(flowAngle + t * 3.0 + uv.y * 15.0) * 0.06 * coherency
    ) + normalize(select(vec2<f32>(0.0), -toMouse / vec2<f32>(aspect, 1.0), distMouse > 0.001)) * mouseAttract * 0.04;

    let dispersionScale = 0.015 * (1.0 + treble * 0.8);
    let crawlOffsetR = crawlOffsetBase + eigenvec * dispersionScale;
    let crawlOffsetG = crawlOffsetBase;
    let crawlOffsetB = crawlOffsetBase + eigenNormal * dispersionScale;

    let crawledUVR = clamp(uv + crawlOffsetR, vec2<f32>(0.0), vec2<f32>(1.0));
    let crawledUVG = clamp(uv + crawlOffsetG, vec2<f32>(0.0), vec2<f32>(1.0));
    let crawledUVB = clamp(uv + crawlOffsetB, vec2<f32>(0.0), vec2<f32>(1.0));

    let region = floor(crawledUVG * vec2<f32>(10.0, 8.0));
    let hash = hash3(vec3<f32>(region.x * 100.0, region.y * 100.0, time * 2.0));
    let swapPattern = u32(hash.x * 6.0);

    // Multi-spectral chromatic sampling along bifurcated tendrils
    let sampleR = textureSampleLevel(readTexture, u_sampler, crawledUVR, 0.0).r;
    let sampleG = textureSampleLevel(readTexture, u_sampler, crawledUVG, 0.0).g;
    let sampleB = textureSampleLevel(readTexture, u_sampler, crawledUVB, 0.0).b;
    let chromaticSample = vec3<f32>(sampleR, sampleG, sampleB);

    var swappedColor = chromaticSample;
    if (swapPattern == 0u) { swappedColor = vec3<f32>(chromaticSample.b, chromaticSample.r, chromaticSample.g); }
    else if (swapPattern == 1u) { swappedColor = vec3<f32>(chromaticSample.g, chromaticSample.b, chromaticSample.r); }
    else if (swapPattern == 2u) { swappedColor = vec3<f32>(1.0) - chromaticSample; }
    else if (swapPattern == 3u) { swappedColor = vec3<f32>(chromaticSample.g, chromaticSample.r, chromaticSample.b); }
    else if (swapPattern == 4u) {
        let channel = u32(hash.y * 3.0);
        if (channel == 0u) { swappedColor = vec3<f32>(chromaticSample.r * 2.0, chromaticSample.g, chromaticSample.b); }
        else if (channel == 1u) { swappedColor = vec3<f32>(chromaticSample.r, chromaticSample.g * 2.0, chromaticSample.b); }
        else { swappedColor = vec3<f32>(chromaticSample.r, chromaticSample.g, chromaticSample.b * 2.0); }
    } else {
        let gray = dot(chromaticSample, vec3<f32>(0.299, 0.587, 0.114));
        swappedColor = vec3<f32>(gray, gray, gray);
    }
    swappedColor = mix(src, swappedColor, swapIntensity * coherency);

    // IDEA 2: Photoelastic fringe birefringence
    // Edge stress (principal stress difference lambda1 - lambda2) produces optical retardation fringe bands
    let stressRetardation = (lambda1 - lambda2) * 28.0;
    let birefringenceFringes = 0.5 + 0.5 * cos(stressRetardation + vec3<f32>(0.0, 2.094, 4.188));
    swappedColor += birefringenceFringes * coherency * 0.35 * (0.8 + mids * 0.5);

    // IDEA 3: Bioluminescent streamline pulse waves
    // High-frequency photon packet pulse propagating along the tensor orientation
    let pulsePhase = fract(flowAngle * 0.3183 + t * 2.0 + depth * 3.0);
    let pulseWave = pow(sin(pulsePhase * 3.14159), 16.0) * coherency * (0.6 + treble * 1.2);
    let pulseColor = vec3<f32>(0.3, 0.8, 1.2) * pulseWave;
    swappedColor += pulseColor;

    // Exact-integer textureLoad from dataTextureC previous frame feedback
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    let animatedMix = feedbackMix + sin(time * 3.0 + uv.x * 5.0) * 0.1;
    swappedColor = mix(swappedColor, prev, clamp(animatedMix, 0.0, 0.95));

    // Flow-colored LIC tint
    let flowNorm = flowAngle * 0.15915 + 0.5;
    let flowColor = palette(flowNorm, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    swappedColor = mix(swappedColor, flowColor * 0.4 + swappedColor * 0.6, coherency * 0.4);

    // Flash modulated by bass
    let flash = step(0.95 - bass * 0.04, fract(time * flashRate + region.x * 10.0 + region.y * 7.0));
    let flashColor = vec3<f32>(flash, flash * 0.5, flash * 0.8);
    let flashIntensity = 0.18;
    var finalColor = mix(swappedColor, flashColor, flash * flashIntensity);

    // Click ripple wavefronts
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 2.5) {
            let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            let rWave = sin(rDist * 40.0 - elapsed * 12.0) * exp(-elapsed * 1.5) * exp(-rDist * 3.0);
            finalColor += vec3<f32>(0.6, 0.3, 0.9) * max(rWave, 0.0) * 0.35;
        }
    }

    let crawlGlow = length(crawlOffsetBase) * 6.0;
    let glowColor = vec3<f32>(0.8, 0.4, 1.0) * crawlGlow * (0.6 + bass * 0.4);
    finalColor = finalColor + glowColor;

    let displayColor = acesFilm(max(finalColor, vec3<f32>(0.0)));
    let confidenceAlpha = clamp(0.7 + coherency * 0.28, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(displayColor, confidenceAlpha));
    textureStore(dataTextureA, coord, vec4<f32>(displayColor, confidenceAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
