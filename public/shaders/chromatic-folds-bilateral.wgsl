// ═══════════════════════════════════════════════════════════════════
//  chromatic-folds-bilateral
//  Category: advanced-hybrid
//  Features: chromatic-folds, bilateral-dream, hue-manipulation
//  Complexity: High
//  Chunks From: chromatic-folds, conv-bilateral-dream
//  Created: 2026-04-18
//  By: Agent CB-12 — Chroma & Spectral Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Psychedelic hue folding blended with edge-preserving bilateral
//  dream smoothing. Folds occur on the bilateral-filtered image,
//  producing smooth yet deeply warped chromatic topology.
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

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    let q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    var x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

fn foldHue(h: f32, pivot: f32, strength: f32) -> f32 {
    let delta = h - pivot;
    return fract(pivot + sign(delta) * pow(abs(delta), strength));
}

fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let foldStrength = u.zoom_params.x * 1.5 + 0.5;
    let pivotHue = u.zoom_params.y;
    let satScale = u.zoom_params.z * 0.5 + 0.75;
    let depthInfluence = u.zoom_params.w;

    let spatialSigmaBase = mix(0.1, 1.0, u.zoom_config.x);
    let colorSigma = mix(0.05, 1.0, u.zoom_config.y);
    let hueShiftAmt = u.zoom_config.z;

    // Mouse distance modulation for bilateral
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * u.zoom_config.w;
    let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);

    // Ripple shockwaves
    var rippleSharpness = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.3) * 12.0, 2.0));
            rippleSharpness = rippleSharpness + wave * (1.0 - rElapsed / 3.0);
        }
    }
    let finalSigma = max(spatialSigma * (1.0 - rippleSharpness * 0.8), 0.02);

    // Bilateral filter
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    let radius = i32(ceil(finalSigma * 2.5));
    let maxRadius = min(radius, 5);

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
            let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
            let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));
            let colorDist = length(neighbor.rgb - center.rgb);
            let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));
            let weight = spatialWeight * rangeWeight;
            accumColor += neighbor.rgb * weight;
            accumWeight += weight;
        }
    }

    var srcColor = center.rgb;
    if (accumWeight > 0.001) {
        srcColor = accumColor / accumWeight;
    }

    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Hue gradient on bilateral-smoothed image
    let h = rgb2hsv(srcColor).x;
    let hR = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb).x;
    let hL = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb).x;
    let hU = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).rgb).x;
    let hD = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).rgb).x;

    let gradX = fract(hR - hL + 1.5) - 0.5;
    let gradY = fract(hU - hD + 1.5) - 0.5;
    let hueGrad = vec2<f32>(gradX, gradY);

    let curvature = pow(depthVal, 2.0) * depthInfluence;
    let dispBase = hueGrad * foldStrength * 0.05 * (1.0 + curvature);

    let noise = hash2(uv * 100.0 + time);
    let noiseDisp = vec2<f32>(sin(time + noise * 6.28318), cos(time + noise * 6.28318)) * 0.003;
    var totalDisp = dispBase + noiseDisp;

    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rdist = distance(uv, r.xy);
        let t = time - r.z;
        if (t > 0.0 && t < 3.0) {
            let wave = sin(rdist * 30.0 - t * 4.0);
            let amp = 0.005 * (1.0 - rdist) * (1.0 - t / 3.0);
            if (rdist > 0.001) {
                totalDisp = totalDisp + normalize(uv - r.xy) * wave * amp;
            }
        }
    }

    let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
    let displacedColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    var hsv = rgb2hsv(displacedColor);
    hsv.x = foldHue(hsv.x, pivotHue, foldStrength);
    hsv.y = clamp(hsv.y * satScale, 0.0, 1.0);
    let foldedColor = hsv2rgb(hsv.x, hsv.y, hsv.z);

    // Feedback blend
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let feedbackStrength = 0.85;
    let finalColor = mix(foldedColor, prev, feedbackStrength);

    // Psychedelic hue shift post-processing
    if (hueShiftAmt > 0.0) {
        let hsv2 = rgb2hsv(finalColor);
        let newHue = fract(hsv2.x + hueShiftAmt + mouseDist * 0.3 + time * 0.05);
        finalColor = hsv2rgb(newHue, hsv2.y, hsv2.z);
    }

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
