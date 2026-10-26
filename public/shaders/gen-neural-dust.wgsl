// ═══════════════════════════════════════════════════════════════════
//  Neural Dust
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: leaky integrate-and-fire motes with a sharp action-potential flash and refractory bioluminescent afterglow, click ripples acting as stimulus electrodes that force-fire the motes they cross; axon filaments wiring neighbouring motes that conduct a travelling spike pulse with conduction delay
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Dust Density, y=Flow Speed, z=Glow Radius, w=Hue Shift
  ripples: array<vec4<f32>, 50>,
};

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

// Mote centre in grid space (same offset/drift law as the glow layer).
fn moteCenter(cellId: vec2<f32>, time: f32, flowSpeed: f32) -> vec2<f32> {
    let rnd = hash12(cellId + vec2<f32>(time * 0.05, 0.0));
    let offset = (hash12(cellId + vec2<f32>(1.0, 2.0)) - 0.5) * 0.6;
    let drift = vec2<f32>(
        sin(time * flowSpeed * 2.0 + rnd * 6.28318),
        cos(time * flowSpeed * 1.5 + rnd * 6.28318)
    ) * 0.25;
    return cellId + vec2<f32>(0.5) + vec2<f32>(offset) - drift;
}

// Leaky integrate-and-fire: the membrane charges at a per-mote rate (its
// own FFT band and bass raise the input current); on crossing threshold it
// fires and resets. Returns seconds since the last spike.
fn sinceSpike(cellId: vec2<f32>, time: f32, drive: f32) -> f32 {
    let rate = mix(0.22, 0.85, hash12(cellId + vec2<f32>(3.3, 7.1))) * drive;
    let phase = fract(time * rate + hash12(cellId + vec2<f32>(11.0, 5.0)));
    return phase / max(rate, 1e-3);
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

    // Particle grid layer
    let gridScale = mix(8.0, 24.0, dustDensity);
    let gridPos = warped * gridScale;
    let cellId = floor(gridPos);
    let cellFract = fract(gridPos) - 0.5;

    // Random offset per cell
    let rnd = hash12(cellId + vec2<f32>(time * 0.05, 0.0));
    let offset = (hash12(cellId + vec2<f32>(1.0, 2.0)) - 0.5) * 0.6;
    let drift = vec2<f32>(
        sin(time * flowSpeed * 2.0 + rnd * 6.28318),
        cos(time * flowSpeed * 1.5 + rnd * 6.28318)
    ) * 0.25;
    let particlePos = cellFract - offset + drift;

    // Per-cell band: this cell's own bass/mids/treble lane drives it
    let cellEnergy = cellBandEnergy(cellId);

    // Distance from particle center with per-band audio jitter
    let jitter = 1.0 + (bass + treble) * 0.2 + cellEnergy * 0.55;
    let d = length(particlePos) / jitter;

    // Mouse gravity attracts nearby particles (screen space, unparallaxed)
    let toMouse = mouse - p;
    let mouseDist = length(toMouse);
    let mousePull = exp(-mouseDist * 3.0) * mouseDown * 0.15;
    let mouseGlow = glow(mouseDist, 0.4 + mids * 0.3, 0.6 * mouseDown);

    // ── Idea 1: integrate-and-fire spikes + refractory afterglow ─────
    // Holding the mouse depolarises nearby motes (extra input current).
    let drive = 1.0 + cellEnergy * 0.8 + bass * 0.5 + exp(-mouseDist * 4.0) * mouseDown * 1.5;
    var since = sinceSpike(cellId, time, drive);

    // Click ripples are stimulus electrodes: the expanding front force-fires
    // every mote it crosses (the most recent crossing wins).
    var electrode = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let rpos = (rp.xy - 0.5) * vec2<f32>(aspect, 1.0);
            let rdist = length(p - rpos);
            let front = age * 0.45;
            // time since the front passed this point
            let crossed = age - rdist / 0.45;
            if (crossed >= 0.0) {
                since = min(since, crossed);
            }
            electrode += exp(-pow((rdist - front) * 40.0, 2.0)) * exp(-age * 1.2);
        }
    }
    let spikeFlash = exp(-since * 16.0);
    // Luciferin-like afterglow fades through the refractory window.
    let afterglow = exp(-since * 2.2) * 0.45;
    let excite = spikeFlash + afterglow;

    // Layered glow field (per-band energy boosts the cell's glow)
    let density = mix(0.3, 1.2, dustDensity);
    let bandBoost = (0.7 + cellEnergy * 0.9) * (0.55 + excite * 0.9);
    let spikeRadius = glowRadius * (1.0 + spikeFlash * 0.8);
    let particleGlow = glow(d, spikeRadius, density * bandBoost);
    let softField = glow(d, glowRadius * 4.0, density * 0.25 * bandBoost);

    // ── Idea 2: axon filaments with conducted spike pulses ───────────
    // Each mote wires to its +x / +y neighbour (hash-gated). A spike leaves
    // the source mote and travels the axon at a finite conduction velocity.
    var axon = 0.0;
    var axonPulse = 0.0;
    let conduction = 2.5 * (1.0 + treble * 0.6);
    let axonWidth = glowRadius * 0.35;
    for (var k = 0; k < 4; k = k + 1) {
        var src = cellId;
        var dst = cellId + vec2<f32>(1.0, 0.0);
        if (k == 1) { dst = cellId + vec2<f32>(0.0, 1.0); }
        if (k == 2) { src = cellId - vec2<f32>(1.0, 0.0); dst = cellId; }
        if (k == 3) { src = cellId - vec2<f32>(0.0, 1.0); dst = cellId; }
        let linkSeed = hash12(src * 2.1 + dst * 0.7 + vec2<f32>(13.0, 29.0));
        if (linkSeed < mix(0.35, 0.7, densityNorm)) {
            let a = moteCenter(src, time, flowSpeed);
            let b = moteCenter(dst, time, flowSpeed);
            let sd = segDist(gridPos, a, b);
            let srcDrive = 1.0 + cellBandEnergy(src) * 0.8 + bass * 0.5;
            let s = sinceSpike(src, time, srcDrive);
            let head = s * conduction / max(length(b - a), 1e-3);
            let fiber = glow(sd.x, axonWidth, 0.12 * (0.5 + mids));
            let pulse = glow(sd.x, axonWidth * 1.8, 1.0) * exp(-pow((sd.y - head) * 9.0, 2.0)) * step(head, 1.1);
            axon += fiber;
            axonPulse += pulse;
        }
    }

    // Color palette (per-band energy nudges the phase per cell)
    let phase = hueShift + time * 0.04 + rnd * 0.2 + bass * 0.1 + cellEnergy * 0.12;
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
    // Action potential flashes hot cyan-white before relaxing to the palette.
    let spikeColor = vec3<f32>(0.7, 0.95, 1.0);

    var col = vec3<f32>(0.02, 0.02, 0.04);
    col += mix(dustColor, spikeColor, spikeFlash * 0.7) * particleGlow;
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
    var trail = prevFrame * trailDecay + col * inject;
    // Clamp accumulated trail pre-tint at ~1.2 (luma-echo-warp lesson).
    trail = min(trail, vec3<f32>(1.2));

    // Single ACES pass on the display colour.
    let display = aces(trail * trailTint * DISPLAY_EXPOSURE);

    // Alpha = dust density: mote cores, axon fibres and accumulated trail.
    let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(particleGlow * 0.6 + softField * 0.5 + (axon + axonPulse) * 0.5 + luma * 0.6, 0.02, 1.0);

    let finalColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, coord, finalColor);
    // Pass the input depth through; firing motes sit slightly proud.
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depthC + particleGlow * spikeFlash * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
