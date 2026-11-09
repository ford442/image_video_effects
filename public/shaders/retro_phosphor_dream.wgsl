// ═══════════════════════════════════════════════════════════════════════════════
//  retro_phosphor_dream.wgsl - Authentic CRT Phosphor Simulation
//
//  Agent: Visualist + Algorithmist + Interactivist
//  Techniques:
//    - RGB phosphor triad subpixel simulation
//    - Persistence/decay from phosphor afterglow (bass-driven)
//    - Interlaced scanline flicker
//    - Barrel distortion with chromatic aberration
//    - Vignette and screen curvature
//    - Analog hum-bar roll & treble-driven scanline jitter
//    - Mouse curvature modulation + degauss wobble on click
//
//  Upgraded: 2026-11-09 (opus/batch-23)
//  Ideas: P22 split-decay trails; beam halation bleed; phosphor burn-in ghost
//  Rescue: degauss trigger lived in extraBuffer[133] (never persists) -> click
//          was dead; trigger time now kept in dataTextureA texel (0,0).a.
//          Mouse read zoom_config.xy as px (x is time) -> now .yz uv.
//
//  Audio contract (plasmaBuffer[0]): x=bass, y=mid, z=treble, w=level
//  Mouse contract (zoom_config): yz=mouse uv, w=down flag
//
//  Target: 4.6★ rating
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

// Persistent state: texel (0,0) of dataTextureA/.a holds the last degauss
// trigger time (read back next frame through dataTextureC).
// Never re-trigger a degauss more often than this (seconds).
const DEGAUSS_RETRIGGER_GAP: f32 = 0.35;

// Hash
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Phosphor triad pattern (vertical RGB stripes)
fn phosphorTriad(uv: vec2<f32>, triadSize: f32) -> vec3<f32> {
    let x = uv.x / triadSize;
    let triadX = fract(x);

    // RGB vertical stripes
    if (triadX < 0.33) {
        return vec3<f32>(1.0, 0.0, 0.0);
    } else if (triadX < 0.66) {
        return vec3<f32>(0.0, 1.0, 0.0);
    } else {
        return vec3<f32>(0.0, 0.0, 1.0);
    }
}

// Soft phosphor aperture: adds a gentle per-subpixel intensity roll-off
// so triads feel like glowing dots instead of razor-sharp stripes.
fn phosphorAperture(uv: vec2<f32>, triadSize: f32) -> f32 {
    let triadX = fract(uv.x / triadSize);
    let phase = fract(triadX * 3.0) - 0.5;               // -0.5..0.5 inside subpixel
    let aperture = cos(phase * PI);                       // 1 at center, 0 at edges
    return 0.75 + aperture * 0.25;
}

// Screen curvature (barrel distortion)
fn barrelDistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    let distortion = 1.0 + strength * r2;
    return centered * distortion + 0.5;
}

// Inverse barrel (for undistorting)
fn barrelUndistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    let distortion = 1.0 / (1.0 + strength * r2);
    return centered * distortion + 0.5;
}

// Degauss wobble: time-decaying sinusoidal UV offset triggered on mouse-down.
// Age in seconds since the trigger; decays fully after ~1.5s.
fn degaussOffset(uv: vec2<f32>, age: f32) -> vec2<f32> {
    let envelope = exp(-age * 3.5);
    let wobble = sin(age * 28.0) * envelope;
    // Wobble is strongest near the screen center, like a real degauss coil.
    let centerFalloff = 1.0 - smoothstep(0.0, 0.7, length(uv - 0.5));
    return vec2<f32>(wobble * 0.03, wobble * 0.017) * centerFalloff;
}

// Scanline pattern with treble-driven phase jitter (analog sync instability)
fn scanlines(uv: vec2<f32>, intensity: f32, time: f32, jitter: f32) -> f32 {
    let lineIndex = floor(uv.y * 240.0);
    let lineJitter = (hash(vec2<f32>(lineIndex, floor(time * 60.0))) - 0.5) * jitter;
    let phase = (uv.y + lineJitter) * 480.0 * PI + time * 0.1;
    let scanline = sin(phase) * 0.5 + 0.5;
    return 1.0 - (scanline * intensity);
}

// Slow vertical hum-bar roll (60Hz mains bleed), pumped by treble energy
fn humBar(uv: vec2<f32>, time: f32, treble: f32) -> f32 {
    let rollSpeed = 0.06 + treble * 0.10;
    let bar = sin((uv.y + time * rollSpeed) * 2.0 * PI);
    let depth = 0.04 + treble * 0.10;
    return 1.0 - bar * bar * depth;
}

// Interlaced flicker
fn interlaceFlicker(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let field = floor(time * 30.0) % 2.0;
    let line = floor(uv.y * 240.0) % 2.0;
    let flicker = select(1.0, 0.85, line == field);
    return 1.0 - (1.0 - flicker) * intensity;
}

// Phosphor persistence (temporal afterglow). Decay must stay <= 0.95.
fn phosphorGlow(current: vec3<f32>, prev: vec3<f32>, decay: f32) -> vec3<f32> {
    return max(current, prev * decay);
}

// Chromatic aberration for barrel edges
fn chromaticAberration(uv: vec2<f32>, strength: f32, tex: texture_2d<f32>, smp: sampler) -> vec3<f32> {
    let centered = uv - 0.5;
    let r = length(centered);
    let aberration = strength * r * r;

    let dir = normalize(centered + vec2<f32>(1e-5, 0.0));
    let rUV = uv + dir * aberration;
    let gUV = uv;
    let bUV = uv - dir * aberration;

    return vec3<f32>(
        textureSampleLevel(tex, smp, rUV, 0.0).r,
        textureSampleLevel(tex, smp, gUV, 0.0).g,
        textureSampleLevel(tex, smp, bUV, 0.0).b
    );
}

// Noise/grain
fn filmGrain(uv: vec2<f32>, time: f32) -> f32 {
    return hash(uv + time * 0.1) * 0.1 + 0.95;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);

    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // ── Audio analysis (FIX: was bound to u.zoom_config.w = MouseDown) ──
    // plasmaBuffer[0]: x=bass, y=mid, z=treble, w=overall level
    let spectrum = plasmaBuffer[0];
    let audioPulse = clamp(spectrum.x, 0.0, 1.0);        // bass pumps persistence + glow
    let trebleEnergy = clamp(spectrum.z, 0.0, 1.0);      // treble drives analog noise

    // ── Mouse state ──
    let mouseUV = clamp(u.zoom_config.yz, // fix: was zoom_config.xy/px (time/res -> curvature crept with time)
                    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 1.0));
    let mouseDown = step(0.5, u.zoom_config.w);

    // Degauss trigger bookkeeping: every thread derives the same value from
    // the state texel, thread (0,0) persists it into dataTextureA.a.
    var lastTrigger = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).a;
    if (lastTrigger > time + 0.5 || lastTrigger <= 1.0) { lastTrigger = -100.0; } // fresh / reset / sentinel
    if (mouseDown > 0.5 && time - lastTrigger > DEGAUSS_RETRIGGER_GAP) {
        lastTrigger = time;
    }
    let degaussAge = max(time - lastTrigger, 0.0);

    // ── Slider parameters (saved-preset contract: zoom_params.x/y/z/w) ──
    // param1 "Curvature"    -> barrel distortion strength
    // param2 "Phosphor Size"-> triad subpixel size
    // param3 "Scanlines"    -> scanline intensity
    // param4 "Flicker"      -> interlaced flicker intensity
    var curvature = u.zoom_params.x * 0.3;               // 0-0.3
    let phosphorSize = 0.001 + u.zoom_params.y * 0.003;  // 0.001-0.004
    let scanlineIntensity = u.zoom_params.z * 0.5;       // 0-0.5
    let flickerIntensity = u.zoom_params.w * 0.3;        // 0-0.3

    // Mouse X modulates curvature strength (grab the tube and bend it)
    curvature *= 0.6 + mouseUV.x * 0.8;

    // ── UV pipeline: degauss wobble -> barrel distortion ──
    var workUV = uv + degaussOffset(uv, degaussAge);
    let distortedUV = barrelDistort(workUV, curvature);

    // Chromatic aberration at edges
    var color = chromaticAberration(distortedUV, curvature * 0.5, readTexture, u_sampler);

    // Sample with phosphor mask + soft aperture
    let triad = phosphorTriad(uv, phosphorSize);
    color *= (0.7 + triad * 0.6) * phosphorAperture(uv, phosphorSize);

    // Scanlines with treble-driven phase jitter
    let jitterAmount = trebleEnergy * 0.004;
    color *= scanlines(uv, scanlineIntensity, time, jitterAmount);

    // Slow hum-bar roll
    color *= humBar(uv, time, trebleEnergy);

    // Interlaced flicker
    color *= interlaceFlicker(uv, time, flickerIntensity);

    // Temporal phosphor persistence — bass pumps the afterglow decay.
    // Idea 1 — P22 split decay: each phosphor fades at its own rate
    // (blue fastest, green longest), so moving light leaves green-amber trails.
    // Every channel stays <= 0.95.
    let prevFrame = textureLoad(dataTextureC, coord, 0).rgb;
    let decay = vec3<f32>(0.86, 0.93, 0.74) + audioPulse * vec3<f32>(0.06, 0.02, 0.1);
    color = max(color, prevFrame * min(decay, vec3<f32>(0.95)));

    // Idea 2 — Beam halation: bright beam energy from neighbouring columns
    // of the previous frame bleeds sideways through the faceplate glass.
    var halo = vec3<f32>(0.0);
    let maxC = vec2<i32>(resolution) - vec2<i32>(1);
    for (var k: i32 = 1; k <= 4; k = k + 1) {
        let w = exp(-f32(k) * 0.6);
        let l = textureLoad(dataTextureC, clamp(coord - vec2<i32>(k * 2, 0), vec2<i32>(0), maxC), 0).rgb;
        let r = textureLoad(dataTextureC, clamp(coord + vec2<i32>(k * 2, 0), vec2<i32>(0), maxC), 0).rgb;
        halo += (max(l - vec3<f32>(0.45), vec3<f32>(0.0)) + max(r - vec3<f32>(0.45), vec3<f32>(0.0))) * w;
    }
    color += halo * (0.35 + audioPulse * 0.3);

    // Idea 3 — Phosphor burn-in: every texel's alpha integrates its own
    // long-run luminance (~20 s), and that worn phosphor shows as a faint
    // brown-amber ghost of whatever sat on screen — a degauss can't clear it.
    let prevBurn = select(textureLoad(dataTextureC, coord, 0).a, 0.0, coord.x == 0 && coord.y == 0);
    let burnPrev = select(prevBurn, 0.0, prevBurn > 1.0 || time < 0.1);
    let burn = mix(burnPrev, dot(color, vec3<f32>(0.3, 0.55, 0.15)), 0.0015 + audioPulse * 0.002);
    color = color * (1.0 - burn * 0.18) + vec3<f32>(0.55, 0.38, 0.18) * burn * 0.22;

    // Film grain
    color *= filmGrain(uv, time);

    // Vignette from screen edge
    let edgeDist = length(uv - 0.5) * 1.4;
    let vignette = 1.0 - edgeDist * edgeDist * 0.5;
    color *= vignette;

    // HDR boost for phosphor bloom — bass-driven
    color = color * (1.0 + audioPulse * 0.5);

    // Degauss flash: brief chromatic shimmer while the wobble is active
    let degaussGlow = exp(-degaussAge * 3.5) * 0.25;
    color += vec3<f32>(degaussGlow * 0.4, degaussGlow * 0.8, degaussGlow * 0.6);

    // Tone map
    color = color / (1.0 + color * 0.5);

    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));

    // Store for persistence
    let stateA = select(clamp(burn, 0.0, 1.0), lastTrigger, coord.x == 0 && coord.y == 0);
    textureStore(dataTextureA, coord, vec4<f32>(color, stateA));
}
