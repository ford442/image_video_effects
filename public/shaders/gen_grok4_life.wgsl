// ═══════════════════════════════════════════════════════════════════════════════
//  SmoothLife Predator-Prey — Two-Species Audio-Reactive Cellular Automaton
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, procedural, animated
//  Complexity: Very High
//  Scientific: Rafler 2011 SmoothLife for two interacting species:
//              - Species A (prey, green): standard SmoothLife birth/survival,
//                locally suppressed by species B density (predation pressure)
//              - Species B (predator, red): grows proportional to A density
//                (Lotka-Volterra α·A·B term), decays to zero without prey
//              - Predator-prey Lotka-Volterra oscillations at population scale
//              - Audio bass drives prey birth-rate, treble drives predator decay,
//                mids modulate coupling strength
//  Upgrades (2026-07-22, Algorithmist pass):
//              - FIXED toroidal wrap bug: hardcoded `& 2047` bitmask replaced by
//                resolution-aware modulo wrap (correct at ANY canvas size)
//              - Spectral ecosystem zonation: per-bin FFT energy spatially varies
//                the Lotka-Volterra coupling (bass zone / mid zone / treble zone)
//              - Age-based prey ramp: young colonies cyan-white → old deep green
//              - Extinction bloom pulse when smoothed global population crashes
//  Upgraded: Phase B+
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,  // x=TimeStep, y=Sharpness, z=ColorSpeed, w=InitDensity
    ripples:     array<vec4<f32>, 50>,
}

fn smooth_interval(x: f32, a: f32, b: f32, sharp: f32) -> f32 {
    return smoothstep(a - sharp, a + sharp, x) * (1.0 - smoothstep(b - sharp, b + sharp, x));
}

// Resolution-aware toroidal wrap: correct at ANY canvas size.
// (Replaces the old `& 2047` bitmask that silently assumed a 2048x2048 canvas.)
fn wrap_px(p: vec2<i32>, size: vec2<i32>) -> vec2<i32> {
    return ((p % size) + size) % size;
}

// Annular neighbourhood convolution for species channel (2-pass).
// 9x9 kernel with inner disc (r<3) and outer annulus (3<=r<9) weighting —
// expensive but intentional: this IS the SmoothLife integral approximation.
fn sampleNeighbourhood(px: vec2<i32>, res: vec2<f32>, channel: i32) -> vec4<f32> {
    let inner_radius = 3.0;
    let outer_radius = 9.0;
    let size = vec2<i32>(i32(res.x), i32(res.y));
    var inner_sum = 0.0; var inner_w = 0.0;
    var outer_sum = 0.0; var outer_w = 0.0;
    for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
            let npx = wrap_px(px + vec2<i32>(dx, dy), size);
            let s = textureLoad(dataTextureC, npx, 0);
            let val = select(s.r, s.g, channel == 1);
            let dist = sqrt(f32(dx*dx + dy*dy));
            if (dist < inner_radius) {
                let w = 1.0 - smoothstep(0.0, inner_radius, dist);
                inner_sum += val * w; inner_w += w;
            }
            if (dist < outer_radius && dist >= inner_radius * 0.5) {
                let mid = (inner_radius + outer_radius) * 0.5;
                let w = max(0.0, (1.0 - abs(dist - mid) / (outer_radius - inner_radius)));
                let ww = w * w;
                outer_sum += val * ww; outer_w += ww;
            }
        }
    }
    let n = select(inner_sum / inner_w, 0.0, inner_w < 0.001);
    let m = select(outer_sum / outer_w, 0.0, outer_w < 0.001);
    return vec4<f32>(n, m, 0.0, 0.0);
}

// Spectral ecosystem zonation: split the screen into three vertical biomes.
// Left third follows the bass FFT bins, middle the mid bins, right the treble
// bins; each zone's per-bin energy scales its local Lotka-Volterra coupling,
// so distinct ecological regimes visibly emerge across the canvas.
fn zoneEnergy(uv_x: f32) -> f32 {
    let binLow  = plasmaBuffer[2].x + plasmaBuffer[3].x + plasmaBuffer[4].x;
    let binMid  = plasmaBuffer[9].x + plasmaBuffer[10].x + plasmaBuffer[11].x;
    let binHigh = plasmaBuffer[16].x + plasmaBuffer[17].x + plasmaBuffer[18].x;
    let wLeft   = 1.0 - smoothstep(0.28, 0.38, uv_x);
    let wRight  = smoothstep(0.62, 0.72, uv_x);
    let wMid    = 1.0 - wLeft - wRight;
    let e = (wLeft * binLow + wMid * binMid + wRight * binHigh) / 3.0;
    return clamp(e, 0.0, 1.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let px     = vec2<i32>(global_id.xy);
    let mouse  = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mDown  = u.zoom_config.w > 0.0;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ─── Slider wiring (saved-preset contract: ids/defaults unchanged) ───
    // Time Step    → simulation integration step dt
    // Sharpness    → steepness of the SmoothLife birth/survival transitions
    // Colour Speed → hue-cycle rate + age advance rate (generational tempo)
    // Init Density → spontaneous reseed probability and seed-blob radius
    let dt        = clamp(u.zoom_params.x, 0.01, 0.5);
    let sharpness = max(0.01, u.zoom_params.y * 2.0);
    let colSpeed  = u.zoom_params.z;
    let initDens  = u.zoom_params.w;

    // ─── Read current state ───
    let stateData = textureLoad(dataTextureC, px, 0);
    let stateA    = stateData.r;   // prey
    let stateB    = stateData.g;   // predator
    let age       = stateData.b;
    let activity  = stateData.a;

    // ─── Neighbourhoods for both species ───
    let nbA = sampleNeighbourhood(px, resolution, 0);
    let nbB = sampleNeighbourhood(px, resolution, 1);
    let nA  = nbA.x; let mA = nbA.y;   // inner/outer averages for A
    let nB  = nbB.x;                    // inner average for B (predator density)

    // ─── Zoned coupling: local FFT biome modulates interaction strength ───
    let zoneE    = zoneEnergy(uv.x);
    let coupling = mix(0.0, 0.6, mids) * mix(0.6, 1.5, clamp(zoneE, 0.0, 1.0));

    // ─── SmoothLife update for Species A (prey) ───
    // Standard SmoothLife with audio bass modulating birth range
    let bassBoost = bass * 0.04;
    let b1 = 0.257 - bassBoost; let b2 = 0.336 + bassBoost;
    let d1 = 0.365;              let d2 = 0.549;
    let sharp = sharpness * 0.05;
    let birthA    = smooth_interval(nA, b1, b2, sharp);
    let surviveA  = smooth_interval(nA, d1, d2, sharp);
    var transA    = birthA * (1.0 - stateA) + surviveA * stateA;
    transA       += mA * 0.05 * (0.5 - stateA);
    // Predation pressure: predator suppresses prey locally (zone-scaled)
    transA       -= nB * stateA * coupling;

    // ─── SmoothLife update for Species B (predator) ───
    // Predator grows proportional to prey density (Lotka-Volterra)
    let predGrowth   = nA * stateB * coupling;             // α·A·B growth
    let trebleDecay  = 0.05 * (1.0 + treble * 0.5);       // intrinsic decay
    var transB       = predGrowth - stateB * trebleDecay;
    // Also needs prey neighbourhood to establish
    let birthB = smooth_interval(nA, 0.3, 0.7, sharp * 2.0) * (1.0 - stateB) * coupling * 0.5;
    transB += birthB;

    // ─── Discrete time update ───
    var newA = clamp(stateA + dt * (transA - stateA), 0.0, 1.0);
    var newB = clamp(stateB + dt * transB, 0.0, 1.0);

    // ─── Mouse interaction ───
    let mdist = distance(uv, mouse);
    if (mDown && mdist < 0.03) {
        let blob = 1.0 - smoothstep(0.0, 0.03, mdist);
        newA = max(newA, blob);
    }

    // ─── Random seeding (Init Density drives rate + blob radius) ───
    let noise = fract(sin(dot(uv + time * 0.001, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let thresh = 1.0 - max(0.001, initDens * 0.01);
    if (noise > thresh) {
        let seedPos = vec2<f32>(fract(noise * 1.618), fract(noise * 2.718));
        let sdist = distance(uv, seedPos);
        let srad  = 0.03 + initDens * 0.04;
        if (sdist < srad) { newA = max(newA, 1.0 - smoothstep(0.0, srad, sdist)); }
    }

    // ─── Age & activity (Colour Speed also sets generational tempo) ───
    var newAge  = fract(age + (0.01 + colSpeed * 0.03) * (newA - 0.1));
    let newAct  = mix(activity, abs(newA - stateA) + abs(newB - stateB), 0.1);

    // ─── Extinction-event detection (single-thread population monitor) ───
    // extraBuffer[133] = smoothed global population, [134] = bloom pulse.
    // Thread (0,0) coarsely samples a 4x4 grid and updates the EMA; a sharp
    // drop triggers a global bloom pulse that decays over ~40 frames.
    let prevPop   = extraBuffer[133];
    let bloomPulse = extraBuffer[134];
    if (global_id.x == 0u && global_id.y == 0u) {
        var popSum = 0.0;
        for (var gy = 0; gy < 4; gy++) {
            for (var gx = 0; gx < 4; gx++) {
                let sp = vec2<i32>(
                    (gx * i32(resolution.x) / 4 + i32(resolution.x) / 8) % i32(resolution.x),
                    (gy * i32(resolution.y) / 4 + i32(resolution.y) / 8) % i32(resolution.y)
                );
                popSum += textureLoad(dataTextureC, sp, 0).r;
            }
        }
        let popNow = popSum / 16.0;
        let popSmooth = mix(prevPop, popNow, 0.05);
        var pulse = bloomPulse * 0.975;
        if (prevPop - popNow > 0.08 && prevPop > 0.15) {
            pulse = 1.0;   // extinction event detected
        }
        extraBuffer[133] = popSmooth;
        extraBuffer[134] = pulse;
    }

    // ─── Colouring ───
    // Age-based prey ramp: young colonies cyan-white, ancient ones deep green,
    // so colony generations read visually. Predator: red-orange; mixed: yellow.
    let cycle     = newAge * 6.28318 + time * colSpeed;
    let youngCol  = vec3<f32>(0.55, 0.95, 1.0);            // cyan-white youth
    let oldCol    = vec3<f32>(0.05, 0.45, 0.12);           // deep green elders
    let ageFactor = smoothstep(0.05, 0.6, newAge);
    var preyCol   = mix(youngCol, oldCol, ageFactor);
    preyCol      += vec3<f32>(0.08 * sin(cycle), 0.12 * sin(cycle + 1.0), 0.06 * sin(cycle + 2.0));
    let predCol   = vec3<f32>(0.9 + 0.1 * sin(cycle * 2.0), 0.1 + 0.2 * sin(cycle * 2.0 + 1.0), 0.05);
    let deadCol   = vec3<f32>(0.04, 0.06, 0.12);
    let actColor  = vec3<f32>(1.0, 0.9, 0.3) * smoothstep(0.01, 0.1, newAct) * 0.5;

    var color = deadCol;
    color = mix(color, preyCol, smoothstep(0.0, 0.3, newA));
    // Predator overlay tints alive regions red
    color = mix(color, predCol, smoothstep(0.0, 0.3, newB) * newA);
    // Combined peak → yellow-white
    let coExist = newA * newB;
    color = mix(color, vec3<f32>(1.0, 1.0, 0.7), smoothstep(0.4, 0.9, coExist));
    color += actColor;
    // Extinction bloom: brief global warm flash when population crashes
    color += vec3<f32>(0.9, 0.75, 0.5) * bloomPulse * 0.35;
    // Vignette
    let cdist = length(uv - 0.5) * 1.4;
    color *= 1.0 - cdist * cdist * 0.3;

    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let finalColor = mix(inputColor.rgb, color, 0.9);

    textureStore(writeTexture, vec2<u32>(px), vec4<f32>(finalColor, 1.0));
    // SIM STATE (prey, predator, age, activity) — never clamp/tonemap this write
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newA, newB, newAge, newAct));
    textureStore(writeDepthTexture, vec2<u32>(px), vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
