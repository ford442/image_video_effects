// ═══════════════════════════════════════════════════════════════════
//  Procedural Texture Analyzer
//  Category: image
//  Features: audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-02, 2026-11-01
//  Ideas: golden-ratio vignette; voronoi glitch; structure-tensor gain (§12.2A); anti-halo envelope (§12.2A)
//  A packing: ACES display RGBA (C read with textureLoad as colour history)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let q = p3 + dot(p3, p3.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let q = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(q) * 43758.5453);
}

// Cheap voronoi distance for the glitch effect (1-cell, 3x3 search)
fn voronoiDist(uv: vec2<f32>, scale: f32) -> f32 {
    let p = uv * scale;
    let i = floor(p);
    let f = fract(p);
    var minDist = 8.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i + neighbor);
            let diff = neighbor + point - f;
            let d = dot(diff, diff);
            minDist = min(minDist, d);
        }
    }
    return sqrt(minDist);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn safeSampleRGBA(uv: vec2<f32>) -> vec4<f32> {
    let cuv = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    return textureSampleLevel(readTexture, u_sampler, cuv, 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;

    // Audio reactivity from plasmaBuffer (NOT u.config.yzw)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Domain-specific parameters
    let edgeStrength = u.zoom_params.x;       // Edge Enhance
    let unsharpAmount = u.zoom_params.y;      // Unsharp Mask
    let temporalBlend = u.zoom_params.z;      // Temporal Smooth
    let audioReactivity = u.zoom_params.w;    // Audio Reactivity

    // Texel size for neighborhood sampling
    let texel = 1.0 / max(resolution, vec2<f32>(1.0));

    // Center sample
    let centerSample = safeSampleRGBA(uv);
    let center = centerSample.rgb;
    let inputAlpha = centerSample.a;

    // 3x3 neighborhood
    let n  = safeSampleRGBA(uv + vec2<f32>(0.0, -texel.y)).rgb;
    let s  = safeSampleRGBA(uv + vec2<f32>(0.0,  texel.y)).rgb;
    let e_ = safeSampleRGBA(uv + vec2<f32>( texel.x, 0.0)).rgb;
    let w  = safeSampleRGBA(uv + vec2<f32>(-texel.x, 0.0)).rgb;
    let nw = safeSampleRGBA(uv + vec2<f32>(-texel.x, -texel.y)).rgb;
    let ne = safeSampleRGBA(uv + vec2<f32>( texel.x, -texel.y)).rgb;
    let sw = safeSampleRGBA(uv + vec2<f32>(-texel.x,  texel.y)).rgb;
    let se = safeSampleRGBA(uv + vec2<f32>( texel.x,  texel.y)).rgb;

    // Laplacian edge detection (sum of neighbors - 8*center)
    let laplacian = (n + s + e_ + w + nw + ne + sw + se) - 8.0 * center;
    let edgeBoost = edgeStrength * 1.5;

    // ── Idea 1: structure-tensor gain (§12.2A) — sharpen real edges, quiet flats ──
    let lumaW = vec3<f32>(0.299, 0.587, 0.114);
    let ex = (dot(ne, lumaW) + 2.0 * dot(e_, lumaW) + dot(se, lumaW))
      - (dot(nw, lumaW) + 2.0 * dot(w, lumaW) + dot(sw, lumaW));
    let ey = (dot(sw, lumaW) + 2.0 * dot(s, lumaW) + dot(se, lumaW))
      - (dot(nw, lumaW) + 2.0 * dot(n, lumaW) + dot(ne, lumaW));
    let jxx = ex * ex;
    let jyy = ey * ey;
    let jxy = ex * ey;
    let tr = jxx + jyy;
    let detj = jxx * jyy - jxy * jxy;
    let disc = sqrt(max(tr * tr * 0.25 - detj, 0.0));
    let lam1 = tr * 0.5 + disc;
    let lam2 = max(tr * 0.5 - disc, 0.0);
    let coh = (lam1 - lam2) / max(lam1 + lam2, 1e-4);
    let edgeGain = mix(0.55, 1.35, coh);

    var color = center + laplacian * edgeBoost * edgeGain;

    // Unsharp mask: blur via box average, then add high-pass
    let blur = (n + s + e_ + w + nw + ne + sw + se + center) / 9.0;
    let highPass = center - blur;
    color = color + highPass * (unsharpAmount * 1.2) * edgeGain;

    // ── Idea 2: anti-halo envelope (§12.2A) — stay inside the 3×3 range ──
    let nmin = min(center, min(n, min(s, min(e_, min(w, min(nw, min(ne, min(sw, se))))))));
    let nmax = max(center, max(n, max(s, max(e_, max(w, max(nw, max(ne, max(sw, se))))))));
    let haloR = 0.02 + unsharpAmount * 0.05;
    color = clamp(color, max(nmin - vec3<f32>(haloR), vec3<f32>(0.0)), nmax + vec3<f32>(haloR));

    // Temporal filtering with previous frame from dataTextureC
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    let blendT = clamp(temporalBlend * 0.85, 0.0, 0.85);
    color = mix(color, prev, blendT);

    // ─── Creative addition: golden-ratio vignette with iridescent rim ───
    let phi = 1.61803398875;
    let centered = uv - 0.5;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let elliptic = vec2<f32>(centered.x * aspect, centered.y);
    let r = length(elliptic) * phi;
    // Bass-driven breathing pulse
    let pulse = 1.0 + bass * 0.45 * audioReactivity;
    let vignette = smoothstep(1.05 * pulse, 0.35, r);
    // Iridescent rim shifts hue with luma + time
    let luma = dot(center, vec3<f32>(0.299, 0.587, 0.114));
    let rimBand = smoothstep(0.78, 1.0, r) * (1.0 - smoothstep(1.0, 1.18, r));
    let hueT = luma * 6.2831853 + time * 0.3 + mids * 1.2;
    let rimColor = 0.5 + 0.5 * vec3<f32>(
        cos(hueT),
        cos(hueT + 2.094),
        cos(hueT + 4.188)
    );
    color = color * vignette + rimColor * rimBand * (0.25 + bass * 0.35 * audioReactivity);

    // ─── Audio sparkle on bright regions (treble) ───
    let brightMask = smoothstep(0.55, 0.95, luma);
    let sparkleSeed = hash12(uv * resolution + vec2<f32>(time * 60.0, 0.0));
    let sparkle = step(1.0 - treble * 0.18 * audioReactivity, sparkleSeed) * brightMask;
    color = color + vec3<f32>(sparkle);

    // ─── Creative addition: voronoi glitch on treble spikes ───
    let glitchAmt = smoothstep(0.65, 0.95, treble) * audioReactivity;
    let vd = voronoiDist(uv + vec2<f32>(time * 0.05), 12.0 + bass * 8.0);
    let glitchColor = mix(color, vec3<f32>(1.0 - vd) * (color + 0.15), 0.6);
    color = mix(color, glitchColor, glitchAmt * 0.5);

    // Tone mapping
    color = acesToneMapping(max(color, vec3<f32>(0.0)));

    // Calculated alpha (never hardcoded)
    let outLuma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let presence = smoothstep(0.02, 0.6, outLuma);
    let opacity = 0.9 + bass * 0.1 * audioReactivity;
    let generatedAlpha = presence * opacity;
    let finalAlpha = max(inputAlpha, generatedAlpha);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Persist current frame to dataTextureA for downstream/future passes
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
