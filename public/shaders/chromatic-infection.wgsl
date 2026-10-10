// ═══════════════════════════════════════════════════════════════════
//  Chromatic Infection – strong colours spread like a living disease
//  Vibrant hues grow organic tendrils that infect neutral regions.
//  Category: artistic
//  Features: depth-aware, temporal-persistence, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: real contagion through C; inflamed front and scar tissue; patient zero (held pointer) + bass vein throb
//  A packing: raw state — rgb = infection colour, a = 10 + infection level 0..1 (sentinel offset; C alpha outside [10,11] reads as uninfected). Display is ACES RGB in writeTexture only.
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=spreadSpeed, y=intensity, z=satThresh, w=tendrilScale

// ---------------------------------------------------------------
//  Colour utilities
// ---------------------------------------------------------------
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

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

// ---------------------------------------------------------------
//  Organic noise for tendril growth
// ---------------------------------------------------------------
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
    return fract(n * 43758.5453);
}

fn voronoi(uv: vec2<f32>, scale: f32, time: f32) -> f32 {
    var p = uv * scale;
    let i = floor(p);
    let f = fract(p);
    
    var minDist = 1.0;
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let cellCenter = hash22(i + neighbor);
            // Animate cell centers for organic movement
            let animated = cellCenter + 0.3 * sin(time * 0.5 + cellCenter * 6.28);
            let diff = neighbor + animated - f;
            var dist = length(diff);
            minDist = min(minDist, dist);
        }
    }
    return minDist;
}

fn tendrilNoise(uv: vec2<f32>, time: f32, scale: f32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = scale;
    
    for (var i: i32 = 0; i < 4; i++) {
        value += amplitude * voronoi(uv, frequency, time);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// ---------------------------------------------------------------
//  Main
// ---------------------------------------------------------------
// ─────────────────────────────────────────────────────────────────────────────
// ACES Tone Mapping
// ─────────────────────────────────────────────────────────────────────────────
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    let m2 = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    let v = m1 * color;
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ---------------------------------------------------------------
//  Infection state (A/C) helpers
// ---------------------------------------------------------------
const INF_SENTINEL: f32 = 10.0;

// Idea 1: decode one C texel of infection state with an exact load.
// Anything that is not a well-formed infection texel — the all-zero first frame,
// another shader's display RGBA left in C after a switch, NaN — reads as uninfected.
fn loadInfection(coord: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    let c = clamp(coord, vec2<i32>(0), dims - vec2<i32>(1));
    let s = textureLoad(dataTextureC, c, 0);
    let lvl = s.a - INF_SENTINEL;
    let okA = (lvl >= 0.0) && (lvl <= 1.0);
    let okC = all(s.rgb >= vec3<f32>(0.0)) && all(s.rgb <= vec3<f32>(1.0));
    if (okA && okC) { return vec4<f32>(s.rgb, lvl); }
    return vec4<f32>(0.0);
}

// HEAD's mutation step, shared by the ring-sampled strain and the contagion strain.
fn mutateStrain(col: vec3<f32>, tendril: f32, time: f32, hueShift: f32, mutationRate: f32) -> vec3<f32> {
    let hsv = rgb2hsv(col);
    let h = fract(hsv.x + hueShift + mutationRate * sin(time * 0.5 + tendril * 5.0) * 0.1);
    return hsv2rgb(h, min(hsv.y * 1.3, 1.0), min(hsv.z * 1.2, 1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;
    let coord = vec2<i32>(gid.xy);

    // -----------------------------------------------------------------
    //  1️⃣  Read source
    // -----------------------------------------------------------------
    let srcRGBA = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let src = srcRGBA.rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // -----------------------------------------------------------------
    //  2️⃣  Uniforms
    // -----------------------------------------------------------------
    let spreadSpeed   = u.zoom_params.x * 2.0;
    let intensity     = u.zoom_params.y;
    let satThresh     = u.zoom_params.z * 0.4 + 0.2;
    let tendrilScale  = u.zoom_params.w * 15.0 + 5.0;
    // Floor fix: HEAD read zoom_config (time, mouseX, mouseY, mouseDown) as four hidden
    // params — pulseSpeed = time*3 made sin(t*pulseSpeed) a sin(3t²) chirp. Constants now;
    // the pointer gets a real role in Idea 3.
    let pulseSpeed    = 1.5;
    let depthInf      = 0.5;
    let hueShift      = 0.0;
    let mutationRate  = 0.3;
    let bass          = plasmaBuffer[0].x;
    let mouse         = u.zoom_config.yz;
    let mouseDown     = u.zoom_config.w > 0.5;

    // -----------------------------------------------------------------
    //  3️⃣  Classify this pixel
    // -----------------------------------------------------------------
    let hsv = rgb2hsv(src);
    let sat = hsv.y;
    let val = hsv.z;
    let isNeutral = (sat < satThresh) || (val < 0.15) ||
                    ((hsv.x > 0.08) && (hsv.x < 0.15) && (sat < 0.5));

    // -----------------------------------------------------------------
    //  4️⃣  Sample nearby pixels to find infection sources
    // -----------------------------------------------------------------
    var infectionColor = vec3<f32>(0.0);
    var infectionStrength = 0.0;

    let sampleRadius = 8;
    let sampleCount = 16;

    for (var i: i32 = 0; i < sampleCount; i++) {
        let angle = f32(i) / f32(sampleCount) * 6.28318;
        let radius = f32(sampleRadius) * texel.x;

        // Organic, irregular sampling pattern
        let noise = hash21(uv * 100.0 + f32(i));
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius * (0.5 + noise);

        let sampleUV = uv + offset;
        let sampleCol = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let sampleHSV = rgb2hsv(sampleCol);

        // Check if sample is a strong color (infection source)
        let sampleSat = sampleHSV.y;
        let sampleVal = sampleHSV.z;
        let isSaturated = (sampleSat > satThresh) && (sampleVal > 0.2);

        if (isSaturated) {
            let dist = length(offset);
            let falloff = 1.0 - smoothstep(0.0, radius, dist);
            infectionStrength += falloff * sampleSat;
            infectionColor += sampleCol * falloff * sampleSat;
        }
    }

    // Normalize
    if (infectionStrength > 0.01) {
        infectionColor /= infectionStrength;
        infectionStrength = min(infectionStrength / f32(sampleCount) * 4.0, 1.0);
    }

    // -----------------------------------------------------------------
    //  5️⃣  Tendril growth pattern
    // -----------------------------------------------------------------
    let tendril = tendrilNoise(uv, time * spreadSpeed, tendrilScale);

    // Tendrils pulse and breathe.
    // Idea 3 (audio): bass throbs the vein pulse — amplitude, not frequency, so no phase jumps.
    let throb = 1.0 + bass * 0.6;
    let pulse = (0.5 + 0.5 * sin(time * pulseSpeed + tendril * 10.0)) * throb;

    // Sharpen tendrils into vein-like structures
    let veinPattern = smoothstep(0.3, 0.1, tendril) * smoothstep(0.0, 0.05, tendril);

    // Combine with infection strength
    let spreadMask = veinPattern * infectionStrength * pulse;

    // -----------------------------------------------------------------
    //  6️⃣  Depth influence (foreground spreads faster)
    // -----------------------------------------------------------------
    let depthBoost = mix(1.0, 1.5, (1.0 - depth) * depthInf);
    let finalSpread = spreadMask * depthBoost * intensity;

    // -----------------------------------------------------------------
    //  7️⃣  Idea 1: Real contagion through C
    //  Infection level advances pixel to pixel each frame: the strongest of the
    //  4 neighbours (exact loads) × a conductance that is high along the tendril
    //  channels and low in the flesh between them. Only neutral pixels conduct;
    //  saturated pixels are the reservoir. HEAD's 16-tap ring still seeds, so an
    //  all-zero C (first frame / shader switch) starts correctly.
    // -----------------------------------------------------------------
    let dimsC = vec2<i32>(textureDimensions(dataTextureC));
    let selfC = loadInfection(coord, dimsC);
    let prevLvl = selfC.a;
    var nb = loadInfection(coord + vec2<i32>(1, 0), dimsC);
    var cand = loadInfection(coord + vec2<i32>(-1, 0), dimsC);
    if (cand.a > nb.a) { nb = cand; }
    cand = loadInfection(coord + vec2<i32>(0, 1), dimsC);
    if (cand.a > nb.a) { nb = cand; }
    cand = loadInfection(coord + vec2<i32>(0, -1), dimsC);
    if (cand.a > nb.a) { nb = cand; }

    let channel = smoothstep(0.42, 0.12, tendril);
    let conduct = mix(0.90, 0.998, channel);
    // Front speed ≈ rate px/frame: slider 0.5 (default, spreadSpeed 1.0) → rate 0.5.
    let rate = 0.15 + spreadSpeed * 0.35;

    var tgtLvl = 0.0;
    var tgtCol = vec3<f32>(0.0);
    if (!isNeutral) {
        tgtLvl = smoothstep(satThresh, min(satThresh + 0.25, 1.0), sat) * smoothstep(0.15, 0.3, val);
        tgtCol = src;
    } else {
        tgtLvl = nb.a * conduct;
        tgtCol = nb.rgb;
        if (infectionStrength > 0.01 && infectionStrength > tgtLvl) {
            tgtLvl = infectionStrength;
            tgtCol = infectionColor;
        }
    }

    // Idea 3: Patient zero — holding the mouse injects infection at the cursor with the
    // cursor pixel's colour (a vivid mutated strain when that pixel is grey).
    let aspect = resolution.x / resolution.y;
    let dm = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let inject = select(0.0, exp(-dot(dm, dm) / (0.035 * 0.035)), mouseDown);
    if (inject > 0.01 && inject > tgtLvl) {
        let cursorCol = textureSampleLevel(readTexture, u_sampler, clamp(mouse, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let cHSV = rgb2hsv(cursorCol);
        var strain = clamp(cursorCol, vec3<f32>(0.0), vec3<f32>(1.0));
        if (cHSV.y < satThresh || cHSV.z < 0.2) {
            strain = hsv2rgb(fract(time * 0.07 + hash21(floor(mouse * 37.0))), 0.95, 0.95);
        }
        tgtLvl = inject;
        tgtCol = strain;
    }

    var lvl = prevLvl;
    var col = selfC.rgb;
    if (tgtLvl >= prevLvl) {
        lvl = prevLvl + (tgtLvl - prevLvl) * rate;
        // Fresh tissue takes the incoming strain; established tissue drifts toward it slowly.
        col = mix(selfC.rgb, tgtCol, select(0.08, 1.0, prevLvl < 0.02));
    } else {
        // Infected areas persist: slow remission (HEAD's 0.95 colour trail, now on the level).
        lvl = prevLvl + (tgtLvl - prevLvl) * 0.006;
    }
    lvl = clamp(lvl, 0.0, 1.0);
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    // -----------------------------------------------------------------
    //  8️⃣  Mutate the infection colour (display only — never stored, so no drift)
    // -----------------------------------------------------------------
    let mutatedColor = mutateStrain(infectionColor, tendril, time, hueShift, mutationRate);
    let lvlStrain    = mutateStrain(col, tendril, time, hueShift, mutationRate);

    // Idea 2: inflamed front / scar tissue. The front is where the level still lags its
    // target (rising); scar is mature tissue that has plateaued near full infection.
    let deficit = max(tgtLvl - prevLvl, 0.0);
    let front = smoothstep(0.03, 0.35, deficit) * smoothstep(0.02, 0.15, lvl);
    let scar = smoothstep(0.55, 0.95, lvl) * (1.0 - front);

    // -----------------------------------------------------------------
    //  9️⃣  Composite: infect neutral areas, boost saturated areas
    // -----------------------------------------------------------------
    var outCol = src;
    var coverage = 0.0;

    if (isNeutral && (infectionStrength > 0.01 || lvl > 0.01)) {
        if (infectionStrength > 0.01) {
            // Neutral pixels get infected
            // Weight clamped: pulse×throb (≤1.6) × depthBoost (≤1.25) × intensity can exceed 1 → extrapolation.
            outCol = mix(src, mutatedColor, min(finalSpread * 0.8, 1.0));

            // Add glow around infection
            let glow = veinPattern * infectionStrength * 0.3;
            outCol += mutatedColor * glow * pulse;
        }

        // Idea 1: contagion carried in from C, breathing with the vein pulse.
        let lvlSpread = clamp(lvl * depthBoost * intensity * (0.55 + 0.45 * pulse), 0.0, 1.0);
        // Idea 2: scar — long-infected tissue desaturates and darkens slightly.
        let scarCol = mix(vec3<f32>(dot(lvlStrain, vec3<f32>(0.299, 0.587, 0.114))), lvlStrain, 0.45) * 0.78;
        let tissue = mix(lvlStrain, scarCol, scar);
        outCol = mix(outCol, tissue, lvlSpread * 0.7);
        // Idea 2: inflamed front — the advancing edge glows hot (HDR, ACES rolls it off).
        let hot = mix(lvlStrain, vec3<f32>(1.0, 0.45, 0.25), 0.4);
        outCol += hot * front * lvl * intensity * 1.2 * throb;

        coverage = max(finalSpread, lvlSpread);
    } else if (!isNeutral) {
        // Already saturated pixels pulse with life
        let selfPulse = 0.5 + 0.5 * sin(time * pulseSpeed * 0.5 + hsv.x * 10.0);
        outCol = mix(src, mutatedColor, veinPattern * selfPulse * intensity * 0.3);

        // Boost saturation slightly
        let boostedHSV = rgb2hsv(outCol);
        outCol = hsv2rgb(boostedHSV.x, min(boostedHSV.y * 1.1, 1.0), boostedHSV.z);
        coverage = veinPattern * selfPulse * intensity;
    }

    // -----------------------------------------------------------------
    //  🔟  Output — A holds raw infection state for next frame's C
    // -----------------------------------------------------------------
    textureStore(dataTextureA, coord, vec4<f32>(col, INF_SENTINEL + lvl));

    let alpha = mix(srcRGBA.a, 1.0, clamp(coverage, 0.0, 1.0));
    textureStore(writeTexture, coord, vec4<f32>(aces_tonemap(max(outCol, vec3<f32>(0.0))), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
