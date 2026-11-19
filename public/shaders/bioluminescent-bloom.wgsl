// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Bloom v3
//  Category: generative
//  Features: audio-reactive, reaction-diffusion, gray-scott, chemotaxis,
//            quorum-sensing, volumetric-scatter, upgraded-rgba, aces-tone-map,
//            per-tendril-spectrum, spring-damper-nutrient
//  Complexity: Very High
//  Created: 2026-05-31
//  Upgraded: 2026-07-26 (batch 16), 2026-11-19
//  Ideas: Tendril spore shedding (glowing tendril nodes seed v into the Gray-Scott colony); Photophore halos (soft inverse-square bloom around tendril nodes, Glow Radius scales it); Quorum front rim (|grad v| lights the advancing colony front)
//  A packing: dataTextureA = (u, v, glow, density) Gray-Scott state (unchanged)
//
//  Upgrade notes:
//   - Fixed double ACES tonemap (was applied twice, washing highlights).
//     Output path now uses a SINGLE acesToneMap call.
//   - HDR bloom term is hue-preserving-clamped to ~1.2 BEFORE the tonemap
//     so quorum waves bloom without clipping the palette.
//   - Each tendril phase-offsets its pulse from its own FFT bin
//     (plasmaBuffer[(i % 8) + 1].x) instead of following global bands.
//   - Mouse nutrient source is eased through a critically-damped spring
//     (extraBuffer[133..136], init flag [137]) so chemotaxis trails read
//     as pursuit rather than snapping to the cursor.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
const IDEA_1: f32 = 1.0;
const IDEA_2: f32 = 1.0;
const IDEA_3: f32 = 1.0;

// zoom_params: x=TendrilCount, y=PulseSpeed, z=DotDensity, w=GlowRadius

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hue-preserving clamp: scales the HDR color so its brightest channel
// sits at or below `ceiling` while keeping channel ratios (hue) intact.
fn huePreserveClamp(c: vec3<f32>, ceiling: f32) -> vec3<f32> {
    let peak = max(c.r, max(c.g, c.b));
    let scale = min(1.0, ceiling / max(peak, 1e-4));
    return c * scale;
}

// Critically-damped spring step toward the nutrient aim point.
// State lives in extraBuffer[133..136] (pos.xy, vel.xy), init flag [137].
fn springStep(pos: vec2<f32>, vel: vec2<f32>, aim: vec2<f32>, omega: f32, dt: f32) -> vec4<f32> {
    let accel = omega * omega * (aim - pos) - 2.0 * omega * vel;
    let newVel = vel + accel * dt;
    let newPos = pos + newVel * dt;
    return vec4<f32>(newPos, newVel);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;

    // ── Slider wiring (zoom_params) ─────────────────────────────────
    // x: Tendril Count  -> number of background tendril strands (3..8)
    // y: Pulse Speed    -> tendril sway + node pulse tempo (0.2..2.2)
    // z: Dot Density    -> fraction of glow-dot cells that ignite + size
    // w: Glow Radius    -> ambient/scatter/bloom falloff radius
    let tendrilCount = 3 + i32(u.zoom_params.x * 5.0);
    let pulseSpeed = 0.2 + u.zoom_params.y * 2.0;
    let dotDensity = u.zoom_params.z;
    let glowRadius = u.zoom_params.w;

    // ── Spring-damper nutrient source ───────────────────────────────
    // The chemotaxis aim glides toward the mouse through a critically
    // damped spring so the colony pursues the cursor with visible lag.
    var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        // First contact: snap the spring onto the cursor, zero velocity.
        springPos = mouse;
        springVel = vec2<f32>(0.0, 0.0);
    }
    let springState = springStep(springPos, springVel, mouse, 6.0, 0.016);
    let nutrientAim = springState.xy;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = springState.x;
        extraBuffer[134] = springState.y;
        extraBuffer[135] = springState.z;
        extraBuffer[136] = springState.w;
        extraBuffer[137] = 1.0;
    }

    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);

    // ── Background bioluminescent tendrils ──────────────────────────
    var bgCol = vec3<f32>(0.0, 0.02, 0.05);
    var bgGlow = 0.0;
    var sporeField = 0.0;
    var halo = 0.0;
    let haloR = 0.010 + glowRadius * 0.020;

    for (var ti = 0; ti < tendrilCount; ti = ti + 1) {
        let tf = f32(ti);
        // Per-tendril spectrum: each strand listens to its own FFT bin
        // and phase-offsets its pulse, so tendrils dance independently.
        // ── Rescue 4: HEAD read plasmaBuffer[(ti%8)+1] (out of range). Each
        // strand now listens to its own blend of bass/mids/treble.
        let bw = fract(tf * 0.37);
        let band = mix(mix(bass, mids, bw), treble, fract(tf * 0.61) * 0.5);
        let baseAngle = (tf / f32(tendrilCount) - 0.5) * 1.5 + 1.5708;
        let wave = sin(uv.x * 8.0 + tf * 2.1 + time * pulseSpeed + band * 3.0) * 0.15;
        let wave2 = cos(uv.x * 15.0 - tf * 1.7 + time * pulseSpeed * 1.3 + band * 5.0) * 0.08;

        var minTendrilDist = 1e9;
        for (var si = 0; si < 20; si = si + 1) {
            let sf = f32(si) / 20.0;
            let ty = -0.4 + sf * 0.9;
            let tx = (baseAngle - 1.5708) * 0.3 * sf + wave * sf + wave2 * sf * sf;
            let tpos = vec2<f32>(tx, ty);
            let td = length(p - tpos);
            let width = 0.008 * (1.0 + sf * 0.5) * (1.0 + band * 0.3);
            let seg = smoothstep(width, 0.0, td);
            minTendrilDist = min(minTendrilDist, td / width);
            bgGlow = bgGlow + seg * (1.0 - sf * 0.3);

            // Node pulse phase-offset by this tendril's own FFT band.
            let pulse = sin(time * 3.0 * pulseSpeed + tf * 5.0 + sf * 10.0 + band * 6.2831) * 0.5 + 0.5;
            let nodeSize = 0.012 * pulse * (1.0 + treble * 0.5 + band * 0.5);
            let node = smoothstep(nodeSize, 0.0, td);
            bgGlow = bgGlow + node * 2.0;
            // ── Idea 2: Photophore halos (Soft inverse-square bloom) ──
            let hq = td / haloR;
            halo = halo + pulse * 0.15 / (1.0 + hq * hq);
            // ── Idea 1: Tendril spore shedding (native) ──
            sporeField = max(sporeField, node * pulse);
        }

        let tendrilCol = vec3<f32>(0.1, 0.8, 0.6) * (0.5 + mids * 0.3 + band * 0.2);
        bgCol = bgCol + tendrilCol * smoothstep(1.0, 0.0, minTendrilDist);
    }
    bgCol = bgCol + IDEA_2 * vec3<f32>(0.15, 0.75, 0.65) * min(halo, 1.5) * (0.6 + treble * 0.6);

    // ── Scattered glow dots ─────────────────────────────────────────
    // Dot Density slider gates how many grid cells ignite, and scales
    // the radius of the ones that do.
    let dotUV = uv * 30.0;
    let dotId = floor(dotUV);
    let dotFract = fract(dotUV) - 0.5;
    let dotGate = step(hash21(dotId + vec2<f32>(7.0, 3.0)), 0.15 + dotDensity * 0.85);
    let dotPhase = hash21(dotId) * 6.28 + time * (0.5 + hash21(dotId + vec2<f32>(1.0, 0.0)) * 2.0);
    let dotPulse = sin(dotPhase) * 0.5 + 0.5;
    let dotSize = 0.08 * dotPulse * (0.3 + dotDensity * 0.7);
    let dot = smoothstep(dotSize, 0.0, length(dotFract)) * dotGate;
    let dotCol = vec3<f32>(0.2, 1.0, 0.7) * dot * (0.3 + bass * 0.7);
    bgCol = bgCol + dotCol;
    bgGlow = bgGlow + dot;

    // Ambient halo — Glow Radius widens the falloff and brightens it.
    let ambient = smoothstep(0.2 + glowRadius * 0.5, 0.0, length(p)) * (0.04 + glowRadius * 0.12);
    bgCol = bgCol + vec3<f32>(0.05, 0.15, 0.2) * ambient;

    // ── Reaction-diffusion Gray-Scott colony layer ──────────────────
    // ── Rescue 5: exact textureLoad on the history (HEAD used a filtering sampler).
    let pix = vec2<i32>(global_id.xy);
    let maxP = vec2<i32>(res) - vec2<i32>(1);
    let prev = textureLoad(dataTextureC, pix, 0);
    let left = textureLoad(dataTextureC, clamp(pix + vec2<i32>(-1, 0), vec2<i32>(0), maxP), 0);
    let right = textureLoad(dataTextureC, clamp(pix + vec2<i32>(1, 0), vec2<i32>(0), maxP), 0);
    let up = textureLoad(dataTextureC, clamp(pix + vec2<i32>(0, 1), vec2<i32>(0), maxP), 0);
    let down = textureLoad(dataTextureC, clamp(pix + vec2<i32>(0, -1), vec2<i32>(0), maxP), 0);

    let Du = 0.18;
    let Dv = 0.09;
    let feed = 0.025 + bass * 0.015;
    let kill = 0.055 - mids * 0.008;

    let uVal = prev.r;
    let vVal = prev.g;

    let lapU = left.r + right.r + up.r + down.r - 4.0 * uVal;
    let lapV = left.g + right.g + up.g + down.g - 4.0 * vVal;

    let uv2 = uVal * vVal * vVal;
    let du = Du * lapU - uv2 + feed * (1.0 - uVal);
    let dv = Dv * lapV + uv2 - (feed + kill) * vVal;

    // Chemotaxis toward the spring-eased nutrient source (pursuit, not snap)
    let gradN = normalize(nutrientAim - uv + vec2<f32>(0.0001));
    let motility = 0.02 + mids * 0.03;
    let chemoU = motility * (gradN.x * (right.r - left.r) + gradN.y * (up.r - down.r));
    let chemoV = motility * (gradN.x * (right.g - left.g) + gradN.y * (up.g - down.g));

    var un = uVal + du + chemoU;
    var vn = vVal + dv + chemoV;

    // Nutrient pellet drop follows the eased spring position
    let pellet = smoothstep(0.03, 0.0, length(uv - nutrientAim)) * u.zoom_config.w;
    un = un + pellet * 0.4;

    // Treble flash events (stress response)
    // ── Rescue 3: HEAD seeded 25 % hash noise into v over the WHOLE frame on
    // loud treble (frame went white). Now only sparse stress cells flash.
    let flashCell = floor(uv * 24.0);
    let flashSpot = smoothstep(0.35, 0.0, length(fract(uv * 24.0) - 0.5));
    let flash = step(0.75, treble) * step(0.97, hash21(flashCell + floor(time * 4.0))) * flashSpot * 0.25;
    vn = vn + flash;
    // Idea 1 cont. / Rescue 2: v never seeded at idle in HEAD (colony dead).
    // Glowing tendril nodes shed spores into the colony.
    vn = vn + IDEA_1 * sporeField * 0.06;

    un = clamp(un, 0.0, 1.0);
    vn = clamp(vn, 0.0, 1.0);

    // ── Idea 3: Quorum front rim (native) ──
    let gradV = length(vec2<f32>(right.g - left.g, up.g - down.g));
    let rim = smoothstep(0.02, 0.10, gradV) * IDEA_3;

    // Quorum sensing glow activation
    let quorum = smoothstep(0.18, 0.28, vn);
    let glow = vn * quorum * 5.0;

    // Depth attenuation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let attenuation = 1.0 - depth * 0.6;

    // Colony density
    let density = clamp(un + vn * 0.5, 0.0, 1.0);

    // Deep ocean bioluminescence palette
    var col = mix(vec3<f32>(0.0, 0.04, 0.08), vec3<f32>(0.0, 0.5, 0.6), glow);
    col = mix(col, vec3<f32>(0.2, 0.9, 0.6), smoothstep(0.4, 1.0, glow));

    // Blend background tendrils behind colony
    col = col + bgCol * (1.0 - density);

    // Volumetric light scatter — Glow Radius widens the scatter cone
    let scatter = smoothstep(0.2 + glowRadius * 0.5, 0.0, length(uv - 0.5)) * glow * (0.15 + glowRadius * 0.3);
    col = col + vec3<f32>(0.1, 0.3, 0.4) * scatter;

    // HDR bloom on quorum activation waves.
    // Hue-preserving clamp at ~1.2 BEFORE the tonemap keeps the wave
    // crests hot without clipping the bioluminescent palette.
    let bloom = pow(quorum, 2.0) * 2.5 * (1.0 + bass);
    let bloomCol = huePreserveClamp(vec3<f32>(0.4, 0.8, 1.0) * bloom, 1.2);
    col = col + bloomCol;

    col = col + rim * vec3<f32>(0.35, 0.55, 1.0) * (0.8 + mids * 0.6);

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // Single ACES tone map (the old second pass washed out highlights)
    col = acesToneMap(max(col, vec3<f32>(0.0)));

    let alpha = clamp(density * glow * attenuation + bgGlow * 0.1, 0.0, 1.0);

    
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let rAspect = u.config.z / max(u.config.w, 1.0);
    let screenUV = vec2<f32>(vec2<i32>(global_id.xy)) / vec2<f32>(u.config.z, u.config.w);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((screenUV - event.xy) * vec2<f32>(rAspect, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(screenUV - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let finalRGB = vec4<f32>(col, alpha).rgb + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, vec4<f32>(col, alpha).a));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(un, vn, glow, density));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(glow * 0.4 * attenuation, 0.0, 0.0, 0.0));
}
