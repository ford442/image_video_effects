// ═══════════════════════════════════════════════════════════════════════════════
//  Aurora Rift - Advanced Alpha with Physical Transmittance
//  Category: atmospheric
//  Alpha Mode: Physical Transmittance (Beer's Law) + Depth-Layered
//  Features: audio-reactive, click-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-02
//  Ideas: auroral emission lines on the rift borders (O 557.7 green, O 630 red top, N2+ 427.8 violet base); lifetime afterglow (630 nm lingers, 557.7 nm prompt) in the history diffusion
//  A packing: pre-ACES HDR diffused RGB + Beer alpha; ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════════════════
//  HEAD fixes (2026-11-02): the pasted Uniforms declared zoom_params before zoom_config, so
//  "Scale" read time and the second parameter block read the sliders — hand-migrated to the
//  prelude (sliders → zoom_params; the four extra roles are their mid-slider constants).
//  `spectral` was declared twice (never compiled). fbm summed white hash noise, so the curl
//  was per-pixel random — it now sums smooth value noise. History is an exact textureLoad.

#include "_prelude.wgsl"

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 4: Physical Transmittance (Beer's Law)
fn physicalTransmittance(
    baseColor: vec3<f32>,
    opticalDepth: f32,
    absorptionCoeff: vec3<f32>
) -> vec3<f32> {
    let transmittance = exp(-absorptionCoeff * opticalDepth);
    return baseColor * transmittance;
}

// Volumetric alpha from density and thickness
fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

// Mode 1: Depth-Layered Alpha for atmospheric perspective
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.3, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined atmospheric alpha
fn calculateAtmosphericAlpha(
    uv: vec2<f32>,
    opticalDepth: f32,
    density: f32,
    params: vec4<f32>
) -> f32 {
    let volAlpha = volumetricAlpha(density, opticalDepth);
    let depthAlpha = depthLayeredAlpha(uv, params.z);
    return clamp(volAlpha * depthAlpha, 0.0, 1.0);
}

// Hash functions
fn hash2(p: vec2<f32>) -> f32 {
    var h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash3(p: vec3<f32>) -> f32 {
    var h = dot(p, vec3<f32>(41.0, 289.0, 57.0));
    return fract(sin(h) * 43758.5453123);
}

// 4D gradient noise
fn noise4d(p: vec4<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    
    var sum = 0.0;
    // HEAD weighted corner 0 by u and corner 1 by 1-u (seams at every cell edge) — swapped back
    for (var w: i32 = 0; w <= 1; w = w + 1) {
        for (var z: i32 = 0; z <= 1; z = z + 1) {
            for (var y: i32 = 0; y <= 1; y = y + 1) {
                for (var x: i32 = 0; x <= 1; x = x + 1) {
                    let corner = i + vec4<f32>(f32(x), f32(y), f32(z), f32(w));
                    let wx = select(1.0 - u.x, u.x, x == 1);
                    let wy = select(1.0 - u.y, u.y, y == 1);
                    let wz = select(1.0 - u.z, u.z, z == 1);
                    let ww = select(1.0 - u.w, u.w, w == 1);
                    sum = sum + wx * wy * wz * ww * hash3(corner.xyz);
                }
            }
        }
    }
    return sum * 2.0 - 1.0;
}

// Smooth value noise (fbm used to sum raw hash2, which has no spatial coherence)
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

// FBM
fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum = sum + amp * (vnoise(p * freq + time * 0.1) - 0.5);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

// Curl noise
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.001;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>(n2 - n4, n1 - n3) / (2.0 * eps);
}

// Voronoi cell
// Returns (F1, F2): distances to the nearest and second-nearest feature points.
fn voronoiCell(p: vec2<f32>) -> vec2<f32> {
    var i = floor(p);
    var f = fract(p);
    var best = 1e5;
    var second = 1e5;
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let cellPos = i + vec2<f32>(f32(x), f32(y));
            let seed = vec2<f32>(hash2(cellPos), hash2(cellPos + 13.37));
            let point = cellPos + seed - 0.5;
            let d = length(point - p);
            second = select(min(second, d), best, d < best);
            best = min(best, d);
        }
    }
    return vec2<f32>(best, second);
}

// Quaternion rotation
fn quaternionRotate(col: vec3<f32>, angle: f32, axis: vec3<f32>) -> vec3<f32> {
    let s = sin(angle * 0.5);
    let c = cos(angle * 0.5);
    let q = vec4<f32>(normalize(axis) * s, c);
    let t = 2.0 * cross(q.xyz, col);
    return col + q.w * t + cross(q.xyz, t);
}

// HSV to RGB
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    var c = v * s;
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

// Spectral power
fn spectralPower(col: vec3<f32>, pattern: f32) -> vec3<f32> {
    let safeCol = max(col, vec3<f32>(0.001));
    let k = clamp(pattern, 0.0, 1.0);   // pattern reaches ~2.5; mix() past 1 extrapolated to negative RGB
    let high = pow(safeCol, vec3<f32>(2.0));
    let low = sqrt(safeCol);
    let band = sin(safeCol * 3.14159);
    return mix(low, high, k) + band * k * 0.12;
}

// Idea 1 helper: auroral emission colour by altitude (0 = lower border, 1 = top of the arc).
// O I 557.7 nm dominates mid altitude; the forbidden O I 630.0 nm red takes over high up where
// collisions are rare; N2+ 427.8 nm violet fringes the lower edge where the electrons stop.
fn auroraEmission(alt: f32) -> vec3<f32> {
    let green = vec3<f32>(0.32, 1.0, 0.45);   // 557.7 nm
    let red = vec3<f32>(1.0, 0.1, 0.16);      // 630.0 nm
    let violet = vec3<f32>(0.42, 0.22, 1.0);  // 427.8 nm
    let wRed = smoothstep(0.62, 0.95, alt);
    let wViolet = smoothstep(0.3, 0.05, alt);
    return mix(mix(green, red, wRed), violet, wViolet * 0.8);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;

    var uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;


    // Parameters
    let scale = u.zoom_params.x * 3.5 + 0.5;
    let flowSpeed = u.zoom_params.y * 2.8 + 0.2;
    let diffusionRate = u.zoom_params.z * 0.8 + 0.1;
    let fbmOctaves = i32(u.zoom_params.w * 5.0 + 2.0);
    // HEAD read these from the mis-ordered struct's last block; there are only four sliders,
    // so they take the value a centred slider gave.
    let rotSpeed = 1.05;
    let depthParallax = 0.4;
    let emitThresh = 0.175;
    let chromaSpread = 0.25;

    let srcCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Curl flow field
    let curl = curlNoise(uv * scale + depth * depthParallax, time * flowSpeed);

    // Multi-layer parallax
    var totalWarp = vec2<f32>(0.0);
    var totalWeight = 0.0;
    for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
        let layerDepth = f32(layer) / 2.0;
        let layerWeight = 1.0 / (1.0 + abs(depth - layerDepth) * 12.0);
        let advected = curlNoise(uv * scale + curl * 0.3, time * flowSpeed * (1.0 + f32(layer)));
        let offset = advected * depthParallax * layerWeight;
        totalWarp = totalWarp + offset * layerWeight;
        totalWeight = totalWeight + layerWeight;
    }
    totalWarp = totalWarp / max(totalWeight, 0.0001);

    // Voronoi + FBM hybrid
    let vor = voronoiCell(uv * scale * 2.0 + totalWarp);
    let cellDist = vor.x;
    let fbmVal = fbm(uv * scale * 4.0 + curl, time, fbmOctaves);
    let foamPattern = smoothstep(0.0, 0.12, cellDist) * 0.6 + smoothstep(0.2, 0.4, fbmVal) * 0.4;

    // 4D hyper-noise
    let hyper = noise4d(vec4<f32>(uv * scale * 1.5, time * 0.4, depth * 2.0));
    let hyperMod = (hyper + 1.0) * 0.5;

    // Phase interference
    let waveA = sin(length(uv - 0.5) * 28.0 - time * 3.2);
    let waveB = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 22.0 + time * 2.7);
    let waveC = sin(dot(uv - 0.5, vec2<f32>(1.1, 0.9)) * 30.0 - time * 4.1);
    let interference = (waveA * waveB * waveC + 1.0) * 0.5;

    // Pattern
    let pattern = (foamPattern * 0.4 + hyperMod * 0.3 + interference * 0.3) *
                  (1.0 + (1.0 - depth) * 1.5);

    // Quaternion rotation
    let axis = normalize(srcCol + vec3<f32>(0.12, 0.07, 0.04));
    let angle = time * rotSpeed + pattern * 3.2;
    let quatCol = quaternionRotate(srcCol, angle, axis);

    // Chromatic dispersion
    let disp = pattern * chromaSpread * texel * 28.0;
    let rUV = clamp(uv + totalWarp * disp + curl * 0.018, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + totalWarp * disp * 0.93 + curl * 0.012, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + totalWarp * disp * 1.07 - curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let dispersed = vec3<f32>(r, g, b);

    // Emissive plasma
    // Rift borders: the F2−F1 gap is ~0 on the Voronoi edges. HEAD keyed this on F1 (≈1 inside
    // every cell) times the depth-boosted pattern, which washed half the frame at depth 0 and
    // vanished at depth 1; the pattern here is taken without its depth factor.
    let patternBase = foamPattern * 0.4 + hyperMod * 0.3 + interference * 0.3;
    let edge = 1.0 - smoothstep(0.0, 0.15, vor.y - vor.x);
    let border = smoothstep(emitThresh, 1.0, edge * patternBase * (0.6 + length(curl)) * 2.2);
    // Idea 1: the rift borders glow in auroral emission lines instead of an HSV rainbow.
    // Altitude is mostly screen height (uv.y = 0 is the top: red 630 nm crown up there, violet
    // N2+ near the bottom), shifted per rift by its foam density so denser rifts climb redder.
    let altitude = clamp((1.0 - uv.y) * 0.75 + (patternBase - 0.55) * 0.6 + hyper * 0.1, 0.0, 1.0);
    let plasma = auroraEmission(altitude) * (1.5 + bass * 0.6) * (0.8 + 0.2 * sin(time * 0.9 + hyper * 4.0));
    let emissive = mix(dispersed, plasma, border * 0.55);

    // Anisotropic diffusion
    let historyUV = clamp(uv + totalWarp * 0.28, vec2<f32>(0.0), vec2<f32>(1.0));
    let historyCoord = clamp(vec2<i32>(historyUV * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
    let history = textureLoad(dataTextureC, historyCoord, 0).rgb;
    let flowDir = normalize(totalWarp + curl + vec2<f32>(0.001));
    let anisotropy = 1.0 - abs(dot(flowDir, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.28;
    // Idea 2: lifetime afterglow — O 630 nm (red) is a forbidden line with a ~110 s lifetime,
    // 557.7 nm (green) lasts ~0.7 s, so the red channel of the history persists longest and the
    // green the shortest; fading rifts leave crimson trails. A static picture is unaffected
    // (the fixed point of the mix is the emissive colour for any per-channel rate).
    let lifetime = vec3<f32>(1.3, 0.72, 1.0);
    let diffused = mix(emissive, history, clamp(diffusionRate * anisotropy * lifetime, vec3<f32>(0.0), vec3<f32>(0.95)));

    // Spectral power
    let spectral = spectralPower(diffused, pattern);

    // Final blend
    let finalCol = mix(srcCol, spectral, 1.0);

    // ═══ ADVANCED ALPHA CALCULATION - Physical Transmittance ═══
    // Calculate optical depth based on pattern density
    let density = pattern * 2.0;
    let opticalDepth = foamPattern * (1.0 + hyperMod);
    // params.z is the depth-layer weight; HEAD passed the mis-ordered block, use its centre value
    let alpha = calculateAtmosphericAlpha(uv, opticalDepth, density, vec4<f32>(0.0, 0.0, 0.5, 0.0));

    
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let aspect = u.config.z / max(u.config.w, 1.0);
    let screenUV = vec2<f32>(vec2<i32>(gid.xy)) / vec2<f32>(u.config.z, u.config.w);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((screenUV - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(screenUV - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let ringTint = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let hdrOut = finalCol + ringTint * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(aces(max(hdrOut, vec3<f32>(0.0))), alpha));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(diffused, alpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
