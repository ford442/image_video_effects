// ═══════════════════════════════════════════════════════════════════
//  Vinyl Scratch
//  Category: retro-glitch
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-21, 2026-10-19
//  Ideas: eccentric spindle wow; radius-dependent groove pitch + label;
//         stylus scratch marks cut by clicks; bow-tie anisotropic groove
//         sheen; glossy track-gap bands; tangential platter smear
//  A packing: ACES display RGBA. NOTE: HEAD reads C.a back as a sparkle-
//    coherence proxy — that is the semantic alpha being reused, documented
//    here and left intact rather than silently repacked.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

// Temporal film grain
fn temporalGrain(gid: vec2<f32>, time: f32, treble: f32) -> f32 {
    let t1 = hash21(gid + fract(time * 0.7) * 100.0);
    let t2 = hash21(gid * 1.3 + fract(time * 0.3) * 100.0);
    return (mix(t1, t2, 0.5) - 0.5) * (1.0 + treble * 0.3);
}

// Vinyl dust particles: animated on surface
fn vinylDust(uv: vec2<f32>, time: f32, dist: f32, dustAmount: f32) -> f32 {
    let dustUV1 = uv * 8.0 + time * 0.2;
    let dustUV2 = uv * 12.0 - time * 0.15;
    let dust1 = hash21(floor(dustUV1));
    let dust2 = hash21(floor(dustUV2));
    let dust = mix(dust1, dust2, 0.5);
    // Dust is more visible on outer grooves
    let grooveFactor = smoothstep(0.1, 0.5, dist);
    return step(1.0 - dustAmount * 0.3, dust) * grooveFactor * 0.4;
}

// Groove lighting: reflections along concentric grooves
fn grooveReflection(uv: vec2<f32>, dist: f32, time: f32, angle: f32, bass: f32, gloss: f32) -> vec3<f32> {
    let grooveFreq = 80.0;
    let groovePhase = dist * grooveFreq - time * 2.0;
    let groove = sin(groovePhase) * 0.5 + 0.5;
    let grooveSharp = pow(groove, 4.0);
    
    // Light source angle
    let lightAngle = time * 0.5 + bass * 0.3;
    // ── Idea 4: bow-tie anisotropic groove sheen ──────────────────────
    // Concentric grooves reflect a point light as a radial bar through
    // the spindle: two opposite lobes, not one. The angular distance is
    // taken modulo π so the bar keeps tracking the light (HEAD compared an
    // unwrapped lightAngle to atan2 and the sheen died after ~10 s). The
    // lobe tightens outward, where the grooves are straighter.
    var dA = angle - lightAngle;
    dA = dA - 3.14159265359 * floor(dA / 3.14159265359 + 0.5);
    let lobeWidth = mix(2.0, 9.0, smoothstep(0.1, 0.5, dist)) * (1.0 + gloss * 3.0);
    let lightWrap = exp(-dA * dA * lobeWidth) * (1.0 + gloss * 1.5);
    // Track gaps are mirror-smooth: the ridge profile is not needed to catch light.
    let ridge = mix(grooveSharp, 1.0, gloss);
    
    let reflection = ridge * lightWrap * 0.3 * (1.0 + bass * 0.5);
    return vec3<f32>(reflection * 1.0, reflection * 0.95, reflection * 0.85);
}

// Analog warmth: color temperature shift toward orange/yellow
fn analogWarmth(color: vec3<f32>, amount: f32) -> vec3<f32> {
    let warmth = vec3<f32>(1.06, 1.02, 0.94);
    return mix(color, color * warmth, amount);
}

// Saturation roll-off: colors desaturate toward white in highlights
fn saturationRolloff(color: vec3<f32>, amount: f32) -> vec3<f32> {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let highlight = smoothstep(0.5, 1.0, luma);
    return mix(color, vec3<f32>(luma), highlight * amount);
}

// Vignette
fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let center = uv - vec2<f32>(0.5);
    let r = length(center) * 1.4142;
    return pow(1.0 - r * strength, 2.0);
}

// Radial chromatic aberration
fn radialChromatic(uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec2<f32> {
    let dir = uv - center;
    let r2 = dot(dir, dir);
    return dir * r2 * strength;
}

// Lens dirt: subtle dust overlay on bright areas
fn lensDirt(uv: vec2<f32>, time: f32, brightness: f32) -> f32 {
    let dirt1 = hash21(uv * 3.0 + time * 0.01);
    let dirt2 = hash21(uv * 7.0 - time * 0.015);
    let dirt = mix(dirt1, dirt2, 0.5);
    return smoothstep(0.6, 0.9, dirt) * brightness * 0.12;
}

// Groove sparkle: tiny bright points on groove ridges
fn grooveSparkle(uv: vec2<f32>, dist: f32, time: f32, treble: f32) -> f32 {
    let sparkleUV = floor(uv * vec2<f32>(200.0, 200.0)) / 200.0;
    let sparkleHash = hash21(sparkleUV + time * 0.5);
    let sparkle = step(1.0 - treble * 0.1, sparkleHash);
    let grooveMask = sin(dist * 300.0) * 0.5 + 0.5;
    return sparkle * grooveMask * 0.3 * treble;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let held = u.zoom_config.w > 0.5;
    let aspect = resolution.x / resolution.y;

    var smoothMouse = mousePos;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[138] > 0.5) {
        smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
        var springPos = smoothMouse;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = mousePos;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 10.0;
            let accel = (mousePos - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
        smoothMouse = springPos;
    }

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let depthGroove = mix(0.7, 1.3, depth);

    let rotationSpeed = (u.zoom_params.x - 0.5) * 4.0 * (1.0 + bass * 0.5);
    let scratchAmount = u.zoom_params.y;
    let wobble = u.zoom_params.z * (1.0 + mids * 0.7);
    let noiseIntensity = u.zoom_params.w * (1.0 + treble * 0.6);

    // Cinematic params
    let caStrength = 0.015 + bass * 0.02;
    let vignetteStrength = 0.5 + bass * 0.15;
    let warmthAmount = 0.2 + mids * 0.1;
    let saturationRoll = 0.25 + treble * 0.15;
    let dustAmount = 0.3 + treble * 0.2;
    let grooveLightAmount = 0.4 + bass * 0.3;

    var rot = time * rotationSpeed;
    let scratchOffset = (smoothMouse.x - 0.5) * 10.0 * scratchAmount;
    rot = rot + scratchOffset;
    if (held) { rot += sin(time * 18.0) * 0.08 * scratchAmount; }

    var clickPop = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.2) {
            let radius = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            clickPop = max(clickPop, exp(-age * 3.0) * (1.0 - smoothstep(0.0, 0.08, radius)));
        }
    }
    rot += clickPop * 0.5;

    // ── Idea 1: eccentric spindle wow ─────────────────────────────────
    // An off-centre spindle hole swings the whole image once per revolution
    // — the wow every warped record has, and the thing a viewer recognises
    // as vinyl before anything else. HEAD's "wobble" was an angular ripple
    // at a fixed 5 Hz, which is flutter: it never locks to the platter.
    // Orbiting the rotation centre itself at the rotation rate does.
    let ecc = 0.014 * wobble * (1.0 + bass * 0.5);
    let spindle = vec2<f32>(cos(rot), sin(rot)) * ecc;

    let center = vec2<f32>(0.5, 0.5) + spindle;
    let dir = uv - center;
    let dirCorrected = vec2<f32>(dir.x * aspect, dir.y);
    let dist = length(dirCorrected);
    let angle = atan2(dirCorrected.y, dirCorrected.x);

    // ── Idea 3: stylus scratch marks ──────────────────────────────────
    // A click used to do nothing but kick the platter. Now the stylus also
    // cuts: the damaged arc sits at the radius that was clicked, rides the
    // platter (its angle advances by age x rotation rate, so it stays put
    // in record space) and wears out over its own lifetime.
    var scratchMark = 0.0;
    for (var si = 0u; si < rippleCount; si = si + 1u) {
        let rp = u.ripples[si];
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let rpDir = vec2<f32>((rp.x - 0.5) * aspect, rp.y - 0.5);
            let rpR = length(rpDir);
            let markAngle = atan2(rpDir.y, rpDir.x) + age * rotationSpeed;
            var dA = angle - markAngle;
            dA = dA - 6.28318530718 * floor((dA + 3.14159265359) / 6.28318530718);
            let arc = exp(-abs(dA) * 9.0);
            let radial = exp(-abs(dist - rpR) * 260.0);
            scratchMark = max(scratchMark, arc * radial * (1.0 - age / 3.0));
        }
    }

    let wobbleOffset = sin(angle * 2.0 + time * 5.0) * 0.02 * wobble * dist * depthGroove;

    let cosA = cos(rot);
    let sinA = sin(rot);
    let rotatedDirX = dirCorrected.x * cosA - dirCorrected.y * sinA;
    let rotatedDirY = dirCorrected.x * sinA + dirCorrected.y * cosA;

    let sampleUV = vec2<f32>(rotatedDirX / aspect, rotatedDirY) + center + vec2<f32>(wobbleOffset, wobbleOffset);

    // Chromatic wobble + radial chromatic aberration
    let caOffset = radialChromatic(uv, center, caStrength);
    let wobbleR = sin(angle * 2.5 + time * 6.0) * 0.003 * wobble * (1.0 + bass);
    let wobbleB = sin(angle * 1.5 + time * 4.0) * 0.003 * wobble * (1.0 + treble);
    let rUV = clamp(sampleUV + vec2<f32>(wobbleR, 0.0) + caOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(sampleUV - vec2<f32>(wobbleB, 0.0) - caOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    var r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    var g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    var b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // ── Idea 6: tangential platter smear ──────────────────────────────
    // A platter turning faster than the eye can follow blurs along the
    // groove, never across it. Two extra taps at ±dθ around the same
    // centre, dθ from the rotation rate already driving the spin.
    let smearA = clamp(abs(rotationSpeed) * 0.012, 0.0, 0.05);
    let cS = cos(smearA);
    let sS = sin(smearA);
    let tapP = vec2<f32>(rotatedDirX * cS - rotatedDirY * sS, rotatedDirX * sS + rotatedDirY * cS);
    let tapM = vec2<f32>(rotatedDirX * cS + rotatedDirY * sS, -rotatedDirX * sS + rotatedDirY * cS);
    let uvP = clamp(vec2<f32>(tapP.x / aspect, tapP.y) + center + vec2<f32>(wobbleOffset), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvM = clamp(vec2<f32>(tapM.x / aspect, tapM.y) + center + vec2<f32>(wobbleOffset), vec2<f32>(0.0), vec2<f32>(1.0));
    let smearRGB = (textureSampleLevel(readTexture, u_sampler, uvP, 0.0).rgb
                  + textureSampleLevel(readTexture, u_sampler, uvM, 0.0).rgb) * 0.5;
    let smearMix = smoothstep(0.0, 0.05, smearA) * 0.5;
    r = mix(r, smearRGB.r, smearMix);
    g = mix(g, smearRGB.g, smearMix);
    b = mix(b, smearRGB.b, smearMix);
    var color = vec4<f32>(r, g, b, textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).a);

    let grooveNoise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);

    // ── Idea 2: radius-dependent groove pitch and label ───────────────
    // Real grooves tighten as the stylus works inward, and they stop dead
    // at the label. sin(dist * 400) is a set of evenly spaced concentric
    // rings; a pitch that scales with 1/radius, bounded by a lead-out edge
    // and a blank label disc, is a record.
    let labelR = 0.09;
    let outerR = 0.52;
    let grooveBand = smoothstep(labelR, labelR + 0.03, dist) * smoothstep(outerR + 0.05, outerR, dist);
    let groovePitch = 300.0 * (1.0 + 0.35 / max(dist, 0.08));
    // ── Idea 5: glossy track-gap bands ────────────────────────────────
    // Between songs the cutter lays an unmodulated silent spiral: a bright,
    // smooth ring with no groove noise. Loud bass widens the modulated
    // (matte) grooves, which narrows the gaps.
    let trackPos = (dist - labelR) / (outerR - labelR) * 5.0;
    let gapDist = abs(fract(trackPos) - 0.5) * 2.0;           // 1 at a gap, 0 mid-track
    let gapWidth = 0.035 * (1.0 - bass * 0.5);
    let trackGap = smoothstep(1.0 - gapWidth * 2.0, 1.0 - gapWidth, gapDist)
                 * step(0.5, trackPos) * step(trackPos, 4.5) * grooveBand;
    let grooveIntensity = (sin(dist * groovePitch) * 0.5 + 0.5) * noiseIntensity * depthGroove * grooveBand * (1.0 - trackGap);

    color = mix(color, vec4<f32>(grooveNoise, grooveNoise, grooveNoise, color.a), grooveIntensity * 0.2);

    let labelMask = 1.0 - smoothstep(labelR - 0.012, labelR + 0.012, dist);
    color = vec4<f32>(mix(color.rgb, color.rgb * 0.55 + vec3<f32>(0.13, 0.07, 0.035), labelMask * 0.8), color.a);

    color = vec4<f32>(color.rgb + vec3<f32>(1.0, 0.96, 0.88) * scratchMark * (0.35 + scratchAmount * 0.5), color.a);

    // ── Vinyl dust particles ──
    let dust = vinylDust(uv, time, dist, dustAmount);
    let dustColor = vec3<f32>(0.85, 0.8, 0.75) * dust;
    color = vec4<f32>(color.rgb + dustColor, color.a);

    // ── Groove lighting / reflections ──
    let reflection = grooveReflection(uv, dist, time, angle, bass, trackGap) * grooveLightAmount;
    color = vec4<f32>(color.rgb + reflection, color.a);

    // ── Groove sparkle ──
    let sparkle = grooveSparkle(uv, dist, time, treble);
    let prevSparkle = textureLoad(dataTextureC, coord, 0).a;
    let sparkleCoherent = mix(sparkle, prevSparkle * 0.9, 0.35);
    color = vec4<f32>(color.rgb + vec3<f32>(sparkleCoherent + clickPop * 0.25), color.a);

    // ── Temporal film grain ──
    let grain = temporalGrain(vec2<f32>(global_id.xy), time, treble);
    color = vec4<f32>(color.rgb + grain * 0.06, color.a);

    // ── Vignette ──
    let vig = vignette(uv, vignetteStrength * 0.7);
    color = vec4<f32>(color.rgb * mix(0.5, 1.0, vig), color.a);

    // ── Analog warmth ──
    color = vec4<f32>(analogWarmth(color.rgb, warmthAmount), color.a);

    // ── Saturation roll-off in highlights ──
    color = vec4<f32>(saturationRolloff(color.rgb, saturationRoll), color.a);

    // ── Lens dirt on bright areas ──
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let brightMask = smoothstep(0.5, 0.9, luma);
    let dirt = lensDirt(uv, time, brightMask);
    color = vec4<f32>(color.rgb + vec3<f32>(0.9, 0.85, 0.7) * dirt, color.a);

    color.a = clamp(color.a + grooveIntensity * 0.15 + clickPop * 0.2 + scratchMark * 0.12 + trackGap * 0.1 + bass * 0.05, 0.0, 1.0);

    var finalColor = acesToneMap(clamp(color.rgb, vec3<f32>(0.0), vec3<f32>(1.5)) * (0.95 + bass * 0.05));
    textureStore(writeTexture, coord, vec4<f32>(finalColor, color.a));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, color.a));

    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}