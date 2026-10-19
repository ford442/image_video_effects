// ═══════════════════════════════════════════════════════════════════
//  Neural Dust
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-19
//  Ideas: leaky integrate-and-fire motes with a sharp action-potential flash and refractory bioluminescent afterglow, click ripples acting as stimulus electrodes that force-fire the motes they cross; axon filaments wiring neighbouring motes that conduct a travelling spike pulse with conduction delay;
//         synaptic relay (an arriving pulse fires the postsynaptic mote after a synaptic delay -> two-hop cascades); saltatory conduction along myelinated axons (sheath internodes, nodes of Ranvier, node-to-node hops)
//  A packing: ACES display RGBA in A (comet trail decoded with acesInverse)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Dust Density, y=Flow Speed, z=Glow Radius, w=Hue Shift

const DISPLAY_EXPOSURE: f32 = 1.2;

// ── Chunk: hash12 (from gen_grid.wgsl) ────────────────────────────
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Chunk: valueNoise (from gen_grid.wgsl) ────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uS = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, uS.x), mix(c, d, uS.x), uS.y);
}

// ── Chunk: fbm2 (from gen_grid.wgsl / chunk-library) ──────────────
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ── Chunk: palette (cosine, from chunk-library) ───────────────────
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ── Chunk: glow (from anamorphic-flare.wgsl) ──────────────────────
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius + 1e-6)) * intensity;
}

// ── ACES filmic tone map and its exact analytic inverse ───────────
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Solves y = x(ax+b)/(x(cx+d)+e) for x so the comet-trail feedback stays
// in linear light even though A carries the tone-mapped display colour.
fn acesInverse(y: vec3<f32>) -> vec3<f32> {
    let yc = clamp(y, vec3<f32>(0.0), vec3<f32>(0.98));
    let qa = 2.51 - 2.43 * yc;
    let qb = 0.03 - 0.59 * yc;
    let qc = -0.14 * yc;
    return (-qb + sqrt(max(qb * qb - 4.0 * qa * qc, vec3<f32>(0.0)))) / (2.0 * qa);
}

// ── Per-cell band response ────────────────────────────────────────
// Each dust cell listens to its own band (bass / mids / treble of
// plasmaBuffer[0]) instead of the whole field following one band.
fn cellBandEnergy(cellId: vec2<f32>) -> f32 {
    let band = plasmaBuffer[0];
    let laneHash = hash12(cellId + vec2<f32>(4.2, 9.9));
    var energy = band.x;
    if (laneHash > 0.666) {
        energy = band.z;
    } else if (laneHash > 0.333) {
        energy = band.y;
    }
    return clamp(energy, 0.0, 1.0);
}

// Mote centre in grid space. The per-mote drift phase is static (HEAD hashed
// a continuously moving time, so the phase jumped whenever the hash wrapped).
fn moteCenter(cellId: vec2<f32>, time: f32, flowSpeed: f32) -> vec2<f32> {
    let rnd = hash12(cellId + vec2<f32>(0.37, 0.0));
    let offset = (hash12(cellId + vec2<f32>(1.0, 2.0)) - 0.5) * 0.6;
    let drift = vec2<f32>(
        sin(time * flowSpeed * 2.0 + rnd * 6.28318),
        cos(time * flowSpeed * 1.5 + rnd * 6.28318)
    ) * 0.25;
    return cellId + vec2<f32>(0.5) + vec2<f32>(offset) - drift;
}

// Leaky integrate-and-fire: the membrane charges at a fixed per-mote rate;
// on crossing threshold it fires and resets. Extra input current (the
// mote's FFT band, bass, a held pointer) is a bounded depolarising kick that
// pushes near-threshold motes over now. (HEAD multiplied the rate by audio,
// so fract(time*rate) jumped ~a cycle per frame under music: strobing.)
// Returns (seconds since the last spike, inter-spike period).
fn sinceSpike(cellId: vec2<f32>, time: f32, kick: f32) -> vec2<f32> {
    let rate = mix(0.3, 1.0, hash12(cellId + vec2<f32>(3.3, 7.1)));
    let phase = fract(time * rate + hash12(cellId + vec2<f32>(11.0, 5.0)) + kick);
    return vec2<f32>(phase / rate, 1.0 / rate);
}

// Axon link src -> dst exists (hash-gated wiring, denser with Dust Density).
fn linkOn(src: vec2<f32>, dst: vec2<f32>, densityNorm: f32) -> bool {
    return hash12(src * 2.1 + dst * 0.7 + vec2<f32>(13.0, 29.0)) < mix(0.35, 0.7, densityNorm);
}

fn segDist(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let ab = b - a;
    let h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    return vec2<f32>(length(p - a - ab * h), h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(gid.xy);
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / max(res.y, 1.0);
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;

    // Audio (global aggregates)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Clamp/normalize zoom_params (existing slider contract preserved)
    let densityNorm = clamp(u.zoom_params.x, 0.0, 1.0);
    let speedNorm = clamp(u.zoom_params.y, 0.0, 1.0);
    let glowNorm = clamp(u.zoom_params.z, 0.0, 1.0);
    let hueNorm = clamp(u.zoom_params.w, 0.0, 1.0);
    let dustDensity = densityNorm;
    let flowSpeed = mix(0.1, 1.2, speedNorm);
    let glowRadius = mix(0.008, 0.06, glowNorm);
    let hueShift = hueNorm;

    // Mouse influence (engine convention: zoom_config = [time, mx, my, down])
    let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDown = step(0.5, u.zoom_config.w);

    // Depth-aware parallax: gradient of the input frame's depth pushes
    // the dust field so motes drift around foreground silhouettes.
    let texel = vec2<f32>(1.0) / res;
    let depthC = textureSampleLevel(readDepthTexture, u_sampler, uv, 0.0).r;
    let depthDX = textureSampleLevel(readDepthTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r - depthC;
    let depthDY = textureSampleLevel(readDepthTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r - depthC;
    let depthGrad = vec2<f32>(depthDX, depthDY);
    // Dust Density also sets how strongly motes skirt silhouettes.
    let pDust = p + depthGrad * mix(0.5, 2.5, densityNorm);

    // Domain-warped drifting field (samples the parallaxed position)
    let t = time * flowSpeed;
    let q = vec2<f32>(
        fbm2(pDust * (2.0 + dustDensity * 4.0) + vec2<f32>(0.0, t * 0.1), 4),
        fbm2(pDust * (2.0 + dustDensity * 4.0) + vec2<f32>(5.2, 1.3 + t * 0.1), 4)
    );
    let warped = pDust + vec2<f32>(
        fbm2(pDust * 3.0 + 4.0 * q + vec2<f32>(1.7 - t * 0.15, 9.2), 4),
        fbm2(pDust * 3.0 + 4.0 * q + vec2<f32>(8.3 - t * 0.15, 2.8), 4)
    ) * 0.3;

    // Particle grid layer. HEAD fix: the grid follows a gentle share of the
    // domain warp (the full warp's Jacobian is >10x, which folded cells into
    // slivers and turned motes into speckle); the drift field is unchanged.
    let gridScale = mix(8.0, 24.0, dustDensity);
    let gridPos = (pDust + (warped - pDust) * 0.12) * gridScale;
    let cellId = floor(gridPos);

    // HEAD fix: Glow Radius is in screen-height units but distances are in
    // grid cells, so motes/axons were sub-pixel. Convert once.
    let rCell = glowRadius * gridScale * 0.3;

    // Mouse gravity attracts nearby particles (screen space, unparallaxed)
    let toMouse = mouse - p;
    let mouseDist = length(toMouse);
    let mousePull = exp(-mouseDist * 3.0) * mouseDown * 0.15;
    let mouseGlow = glow(mouseDist, 0.4 + mids * 0.3, 0.35 * mouseDown);
    // Holding the mouse depolarises nearby motes (extra input current).
    let mouseKick = exp(-mouseDist * 4.0) * mouseDown * 0.5;

    // Click ripples are stimulus electrodes: the expanding front force-fires
    // every mote it crosses (the most recent crossing wins).
    var crossedPix = 1e4;
    var electrode = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let rpos = (rp.xy - 0.5) * vec2<f32>(aspect, 1.0);
            let rdist = length(p - rpos);
            let front = age * 0.45;
            let crossed = age - rdist / 0.45;
            if (crossed >= 0.0) {
                crossedPix = min(crossedPix, crossed);
            }
            let fd = (rdist - front) * 40.0;
            electrode += exp(-fd * fd) * exp(-age * 1.2);
        }
    }

    // ── Idea 1: integrate-and-fire motes, evaluated on a 4x4 cell window ─
    // (offsets -2..1) so neighbouring motes are not clipped at the cell wall
    // and every incoming synapse of the 3x3 motes is known.
    var wCenter: array<vec2<f32>, 16>;
    var wSince: array<f32, 16>;
    var wPeriod: array<f32, 16>;
    var wEnergy: array<f32, 16>;
    for (var j = 1; j < 16; j = j + 1) {   // j = 0, the (-2,-2) corner, is never read
        let c = cellId + vec2<f32>(f32(j % 4) - 2.0, f32(j / 4) - 2.0);
        let e = cellBandEnergy(c);
        let sp = sinceSpike(c, time, e * 0.25 + bass * 0.15 + mouseKick);
        wCenter[j] = moteCenter(c, time, flowSpeed);
        wSince[j] = sp.x;
        wPeriod[j] = sp.y;
        wEnergy[j] = e;
    }

    let conduction = 2.5 * (1.0 + treble * 0.6);
    // ── Idea 3: synaptic relay ───────────────────────────────────────
    // A pulse that reaches the end of an axon (conduction delay + 40 ms
    // synaptic delay) fires the postsynaptic mote, so spikes cascade through
    // the wiring. relay[k] = time since the 3x3 mote k last fired, own or relayed.
    var relay: array<f32, 9>;
    for (var k = 0; k < 9; k = k + 1) {
        let ox = k % 3 - 1;
        let oy = k / 3 - 1;
        let wi = (ox + 2) + (oy + 2) * 4;
        let c = cellId + vec2<f32>(f32(ox), f32(oy));
        var since = wSince[wi];
        for (var m = 0; m < 2; m = m + 1) {
            let si = select(wi - 4, wi - 1, m == 0);
            let src = select(c - vec2<f32>(0.0, 1.0), c - vec2<f32>(1.0, 0.0), m == 0);
            if (linkOn(src, c, densityNorm) && hash12(src * 1.3 + c * 0.9 + vec2<f32>(7.0, 3.0)) > 0.3) {
                let delay = length(wCenter[wi] - wCenter[si]) / conduction + 0.04;
                var arrived = wSince[si] - delay;
                if (arrived < 0.0) { arrived += wPeriod[si]; }
                since = min(since, arrived);
            }
        }
        relay[k] = since;
    }

    // Layered glow field (per-band energy boosts each mote's glow)
    let density = mix(0.3, 1.2, dustDensity);
    let spikeColor = vec3<f32>(0.7, 0.95, 1.0);
    let jitterG = 1.0 + (bass + treble) * 0.2;
    var particleGlow = 0.0;
    var softField = 0.0;
    var firing = 0.0;
    var phaseAcc = 0.0;
    var flashAcc = 0.0;
    for (var k = 0; k < 9; k = k + 1) {
        let ox = k % 3 - 1;
        let oy = k / 3 - 1;
        let wi = (ox + 2) + (oy + 2) * 4;
        let c = cellId + vec2<f32>(f32(ox), f32(oy));
        let e = wEnergy[wi];
        let dRaw = length(gridPos - wCenter[wi]);
        let d = dRaw / (jitterG + e * 0.55);
        let since = min(relay[k], crossedPix);
        let spikeFlash = exp(-since * 16.0);
        // Luciferin-like afterglow fades through the refractory window.
        let excite = spikeFlash + exp(-since * 2.2) * 0.45;
        let bandBoost = (0.7 + e * 0.9) * (0.55 + excite * 0.9);
        let g = glow(d, rCell * (1.0 + spikeFlash * 0.8), density * bandBoost);
        // Halo keeps its size under audio (only the core jitters).
        let sf = glow(dRaw, rCell * 2.0, density * 0.2 * bandBoost);
        // Per-mote palette phase, glow-weighted (one palette eval per pixel)
        let mrnd = hash12(c + vec2<f32>(0.37, 0.0));
        phaseAcc += (mrnd * 0.2 + e * 0.12) * (g + sf);
        flashAcc += spikeFlash * g;
        particleGlow += g;
        softField += sf;
        firing = max(firing, g * spikeFlash);
    }

    // Colour palette: the nearby motes' own phases, glow-weighted, falling
    // back to the field's mean phase away from motes (a per-cell fallback
    // tiled the mouse halo and trail tint into cell-shaped blocks).
    let wSum = particleGlow + softField;
    let motePhase = mix(0.1 + bass * 0.06, phaseAcc / max(wSum, 1e-4), clamp(wSum * 4.0, 0.0, 1.0));
    let phase = hueShift + time * 0.04 + bass * 0.1 + motePhase;
    let dustColor = palette(
        phase,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    let accentColor = palette(
        phase + 0.3,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 0.7, 0.4),
        vec3<f32>(0.15, 0.45, 0.75)
    );

    // ── Idea 2: axon filaments with conducted spike pulses ───────────
    // Each 3x3 mote wires to its +x / +y neighbour (hash-gated). A spike
    // (own or relayed) leaves the source and travels at a finite velocity.
    // ── Idea 4: saltatory conduction ─────────────────────────────────
    // The axons are myelinated: bright sheath internodes pinched at dark
    // nodes of Ranvier. The pulse hops node to node; each node flashes as
    // it regenerates the spike and fades while the next internode charges.
    var axon = 0.0;
    var axonPulse = 0.0;
    let axonWidth = rCell * 0.35;
    for (var k = 0; k < 9; k = k + 1) {
        let ox = k % 3 - 1;
        let oy = k / 3 - 1;
        let wi = (ox + 2) + (oy + 2) * 4;
        let src = cellId + vec2<f32>(f32(ox), f32(oy));
        for (var m = 0; m < 2; m = m + 1) {
            let dx = select(0, 1, m == 0);
            let dy = 1 - dx;
            if (ox + dx <= 1 && oy + dy <= 1) {
                let dst = src + vec2<f32>(f32(dx), f32(dy));
                let a = wCenter[wi];
                let b = wCenter[wi + dx + dy * 4];
                let sd = segDist(gridPos, a, b);
                // Skip far fibres before the hash and the glow work.
                if (sd.x < axonWidth * 5.0 && linkOn(src, dst, densityNorm)) {
                    let len = max(length(b - a), 1e-3);
                    let internodes = max(2.0, floor(len * 3.0 + 0.5));
                    let nodeDist = abs(fract(sd.y * internodes + 0.5) - 0.5);
                    let sheath = smoothstep(0.08, 0.22, nodeDist);
                    let fiber = glow(sd.x, axonWidth * (0.55 + 0.45 * sheath), 0.16 * (0.5 + mids)) * (0.35 + 0.65 * sheath);
                    let head = relay[k] * conduction / len;
                    let hop = floor(head * internodes);
                    let charge = head * internodes - hop;
                    let along = (sd.y - hop / internodes) * len;
                    let nodeFlash = glow(along, axonWidth * 2.2, 1.0) * exp(-charge * 2.5) * step(head, 1.0);
                    let pulse = glow(sd.x, axonWidth * 2.2, 1.0) * nodeFlash;
                    axon += fiber;
                    axonPulse += pulse;
                }
            }
        }
    }

    var col = vec3<f32>(0.02, 0.02, 0.04);
    let moteFlash = clamp(flashAcc / max(particleGlow, 1e-4), 0.0, 1.0);
    col += mix(dustColor, spikeColor, moteFlash * 0.7) * particleGlow;
    col += accentColor * softField;
    col += accentColor * mouseGlow;
    col += dustColor * mousePull;
    col += accentColor * axon;
    col += mix(accentColor, spikeColor, 0.6) * axonPulse * (0.9 + treble * 0.6);
    col += spikeColor * electrode * 0.5;

    // Subtle vignette
    let v = 1.0 - length(uv - 0.5) * 0.35;
    col *= clamp(v, 0.0, 1.0);

    // Hue Shift tints the accumulated trail toward the live palette.
    let trailTint = mix(vec3<f32>(1.0), dustColor + vec3<f32>(0.25), 0.3 * (0.25 + hueNorm));

    // Comet trails: exact load of last frame's display from dataTextureC,
    // decoded back to linear light (inverse ACES, un-tint). Flow Speed
    // lengthens/shortens the streak, Glow Radius sets the injection.
    let maxC = vec2<i32>(textureDimensions(dataTextureC)) - vec2<i32>(1);
    let prevDisplay = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxC), 0).rgb;
    let prevFrame = acesInverse(prevDisplay) / (DISPLAY_EXPOSURE * max(trailTint, vec3<f32>(0.2)));
    let trailDecay = mix(0.86, 0.93, speedNorm);
    let inject = mix(0.35, 0.7, glowNorm);
    // Injection is normalised by (1 - decay): HEAD's col*inject had a 5-10x
    // steady-state gain that only stayed dark because motes were sub-pixel.
    var trail = prevFrame * trailDecay + col * inject * (1.0 - trailDecay) * 4.0;
    // Clamp accumulated trail pre-tint at ~1.2 (luma-echo-warp lesson).
    trail = min(trail, vec3<f32>(1.2));

    // Single ACES pass on the display colour.
    let display = aces(trail * trailTint * DISPLAY_EXPOSURE);

    // Alpha = dust medium plus mote cores, axon fibres and accumulated trail.
    let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
    // HEAD floor was 0.02 (meanA ~0.1 -> pale wash over a page); the dark
    // dust medium is now mostly opaque.
    let alpha = clamp(0.85 + particleGlow * 0.3 + softField * 0.2 + (axon + axonPulse) * 0.3 + luma * 0.3, 0.0, 1.0);

    let finalColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, coord, finalColor);
    // Pass the input depth through; firing motes sit slightly proud.
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depthC + firing * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
