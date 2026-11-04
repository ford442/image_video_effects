// ═══════════════════════════════════════════════════════════════════
//  Chromatic Folds Bilateral
//  Category: advanced-hybrid
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-06, 2026-11-01
//  Ideas: multi-spectral split hue folding; joint depth-bilateral edge preservation; contour standing resonance waves; bilateral base feeds the fold; edge-gated resonance; pointer-radial dispersion
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let pixel = vec2<i32>(gid.xy);

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let foldStrength = u.zoom_params.x * 1.5 + 0.5;
    let pivotHue = u.zoom_params.y;
    let satScale = u.zoom_params.z * 0.5 + 0.75;
    let depthInfluence = u.zoom_params.w;

    // zoom_config.x is engine TIME: mix() extrapolated past 1.0 and the blur radius grew without
    // bound (~54 after a minute). Held at the old slider midpoint, as the sibling chromatic shaders were.
    let spatialSigmaBase = 0.55; // mix(0.1, 1.0, 0.5)
    let colorSigma = mix(0.05, 1.0, u.zoom_config.y);
    let hueShiftAmt = u.zoom_config.z;

    // Mouse distance modulation for bilateral
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * u.zoom_config.w;
    let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);

    // Ripple shockwaves
    var rippleSharpness = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
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

    // ─── Native Idea 2: Joint Depth-Bilateral Preservation ───
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    var spatialSum = 0.0;
    let radius = i32(ceil(finalSigma * 2.5));
    let maxRadius = min(radius, 5);

    for (var dy = -maxRadius; dy <= maxRadius; dy = dy + 1) {
        for (var dx = -maxRadius; dx <= maxRadius; dx = dx + 1) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
            let neighborDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset, 0.0).r;

            let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
            let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));
            let colorDist = length(neighbor.rgb - center.rgb);
            let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));

            // Joint depth range term preserves physical depth boundaries
            let depthDist = abs(neighborDepth - centerDepth);
            let depthWeight = exp(-depthDist * depthDist / (0.04 * (depthInfluence + 0.1) + 0.001));

            let weight = spatialWeight * rangeWeight * depthWeight;
            accumColor += neighbor.rgb * weight;
            accumWeight += weight;
            spatialSum += spatialWeight;
        }
    }

    var srcColor = center.rgb;
    if (accumWeight > 0.001) {
        srcColor = accumColor / accumWeight;
    }

    let depthVal = centerDepth;

    // ─── 2026-11 Idea 1 (bilateral base feeds the fold): agreement statistic ───
    // accumWeight / spatialSum is 1 where every neighbour agrees in colour and depth
    // and falls at the edges the kernel preserved. It was computed and thrown away.
    let agreement = clamp(accumWeight / max(spatialSum, 1e-4), 0.0, 1.0);
    let flatness = smoothstep(0.35, 0.9, agreement);

    // Hue gradient on bilateral-smoothed image
    let hR = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb).x;
    let hL = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb).x;
    let hU = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).rgb).x;
    let hD = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).rgb).x;

    let gradX = fract(hR - hL + 1.5) - 0.5;
    let gradY = fract(hU - hD + 1.5) - 0.5;
    let hueGrad = vec2<f32>(gradX, gradY);
    let gradMagnitude = length(hueGrad);

    let curvature = pow(depthVal, 2.0) * depthInfluence;
    let dispBase = hueGrad * foldStrength * 0.05 * (1.0 + curvature);

    let noise = hash2(uv * 100.0 + time);
    let noiseDisp = vec2<f32>(sin(time + noise * 6.28318), cos(time + noise * 6.28318)) * 0.003;

    // ─── Native Idea 3: Contour Standing Resonance Waves ───
    let resonancePhase = gradMagnitude * 38.0 - time * 3.5 + depthVal * 8.0;
    // ─── 2026-11 Idea 2: edge-gated resonance ───
    // Nodes sit in flat (high-agreement) regions, antinodes ride the preserved boundaries.
    let resonanceGate = mix(1.0, 0.35, flatness);
    let resonance = sin(resonancePhase) * (0.006 + bass * 0.012) * foldStrength * resonanceGate;
    let resonanceDisp = normalize(hueGrad + vec2<f32>(1e-4, 0.0)) * resonance;

    var totalDisp = dispBase + noiseDisp + resonanceDisp;

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
    let rawDisplaced = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
    // 2026-11 Idea 1: flat regions fold the edge-preserved bilateral base, edges keep the raw tap.
    let displacedColor = mix(rawDisplaced, srcColor, flatness * 0.6);

    // ─── Native Idea 1: Multi-Spectral Split Hue Folding ───
    var hsv = rgb2hsv(displacedColor);
    // 2026-11 Idea 3: pointer-radial dispersion — lateral dispersion grows off-axis, so the
    // split pivots tighten near the cursor and open outward.
    let splitDelta = 0.035 * (1.0 + treble * 0.35) * (0.55 + 1.3 * clamp(mouseDist, 0.0, 1.0));
    let foldR = foldHue(hsv.x, fract(pivotHue + splitDelta), foldStrength);
    let foldG = foldHue(hsv.x, pivotHue, foldStrength);
    let foldB = foldHue(hsv.x, fract(pivotHue - splitDelta), foldStrength);
    let foldedSat = clamp(hsv.y * satScale, 0.0, 1.0);

    let colR = hsv2rgb(foldR, foldedSat, hsv.z).r;
    let colG = hsv2rgb(foldG, foldedSat, hsv.z).g;
    let colB = hsv2rgb(foldB, foldedSat, hsv.z).b;
    let foldedColor = vec3<f32>(colR, colG, colB);

    // Exact dataTextureC feedback blend
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    let feedbackStrength = 0.85;
    var finalColor = mix(foldedColor, prev, feedbackStrength);

    // Psychedelic hue shift post-processing
    if (hueShiftAmt > 0.0) {
        let hsv2 = rgb2hsv(finalColor);
        let newHue = fract(hsv2.x + hueShiftAmt + mouseDist * 0.3 + time * 0.05);
        finalColor = hsv2rgb(newHue, hsv2.y, hsv2.z);
    }

    let outDisplay = acesToneMap(finalColor);
    let alpha = clamp(center.a * 0.8 + gradMagnitude * 0.4 + resonance * 5.0, 0.2, 1.0);
    let outRGBA = vec4<f32>(outDisplay, alpha);

    textureStore(writeTexture, pixel, outRGBA);
    textureStore(dataTextureA, pixel, outRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
