// ═══════════════════════════════════════════════════════════════════
//  Neural Nexus
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: neural-nexus
//  Upgraded: 2026-05-30 → swarm b18 (click bursts, spring cursor, FFT voices)
//  Upgraded: 2026-11-09
//  Ideas: axon fibres with travelling action potentials gated by each neuron's own firing; spike-rate afterglow from exact C
//  A packing: raw sim state (totalActivity, sparks incl. afterglow, mousePulse, alpha) — C.g read back as sparks
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// ── Persistent shader state in extraBuffer[133..255] ONLY ──────────
// [0..4] reserved, [5..132] = engine FFT bins (never touched here).
//   [133] = sprung cursor x      [134] = sprung cursor y
//   [135] = cursor velocity x    [136] = cursor velocity y
const STATE_POS_X: u32 = 133u;
const STATE_POS_Y: u32 = 134u;
const STATE_VEL_X: u32 = 135u;
const STATE_VEL_Y: u32 = 136u;
const SPRING_OMEGA: f32 = 12.0;   // critically damped: c = 2 * omega
const FIXED_DT: f32 = 0.0166667;  // 60 Hz fixed step keeps it stable

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn neuronAt(i: u32) -> vec2<f32> {
    let seed = f32(i) * 17.23;
    return vec2<f32>(hash(vec2<f32>(seed, 0.13)), hash(vec2<f32>(seed, 9.71)));
}

// Distance from p to the segment a→b, and the 0..1 parameter along it.
fn segmentDist(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let ab = b - a;
    let s = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
    return vec2<f32>(length(p - a - ab * s), s);
}

// Critically-damped spring step (semi-implicit Euler, fixed dt).
// Returns vec4(newPos.xy, newVel.xy) eased toward targetPos.
fn springStep(pos: vec2<f32>, vel: vec2<f32>, targetPos: vec2<f32>) -> vec4<f32> {
    let accel = (targetPos - pos) * (SPRING_OMEGA * SPRING_OMEGA) - vel * (2.0 * SPRING_OMEGA);
    let newVel = vel + accel * FIXED_DT;
    let newPos = pos + newVel * FIXED_DT;
    return vec4<f32>(newPos, newVel);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let density = clamp(u.zoom_params.x, 0.5, 4.0);
    let signalSpeed = clamp(u.zoom_params.y, 0.0, 4.0);
    let decayRate = clamp(u.zoom_params.z, 0.05, 2.5);
    let branches = clamp(u.zoom_params.w, 1.0, 8.0);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // ── Spring-dampered cursor: signals glide instead of snapping ──
    var springState = vec4<f32>(
        extraBuffer[STATE_POS_X], extraBuffer[STATE_POS_Y],
        extraBuffer[STATE_VEL_X], extraBuffer[STATE_VEL_Y]
    );
    // First frame after zero-init: snap to the raw cursor so we don't
    // sweep in from (0,0) corner on load.
    if (all(springState == vec4<f32>(0.0)) && dot(rawMouse, rawMouse) > 0.0001) {
        springState = vec4<f32>(rawMouse, 0.0, 0.0);
    }
    let nextSpring = springStep(springState.xy, springState.zw, rawMouse);
    // Single-thread writeback avoids a redundant write storm.
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[STATE_POS_X] = nextSpring.x;
        extraBuffer[STATE_POS_Y] = nextSpring.y;
        extraBuffer[STATE_VEL_X] = nextSpring.z;
        extraBuffer[STATE_VEL_Y] = nextSpring.w;
    }
    let mousePos = clamp(springState.xy, vec2<f32>(0.0), vec2<f32>(1.0));

    var activity = 0.0;
    var sparks = 0.0;
    var fibreGlow = 0.0;   // Idea 1: axon fibre light
    var spikeGlow = 0.0;   // Idea 1: action-potential packets on the fibres
    let nodeCount = 5u + u32(density * 2.0);

    for (var i: u32 = 0u; i < nodeCount; i = i + 1u) {
        let seed = f32(i) * 17.23;
        let neuronPos = vec2<f32>(
            hash(vec2<f32>(seed, 0.13)),
            hash(vec2<f32>(seed, 9.71))
        );
        // ── Per-neuron FFT voice: each neuron listens to its own bin ──
        let voiceBin = u32(hash(vec2<f32>(seed, 4.17)) * 8.0) % 8u + 1u;
        let voice = clamp(plasmaBuffer[voiceBin].x, 0.0, 1.0);
        let toNeuron = uv - neuronPos;
        let dist = max(length(toNeuron), 0.001);
        let connectionDist = distance(neuronPos, mousePos);
        let signalPhase = time * (3.0 + bass * 6.0) - connectionDist * (2.5 + signalSpeed * 2.0) * 6.0;
        let pulse = sin(signalPhase) * exp(-connectionDist * (1.5 + decayRate)) * (0.55 + 0.9 * voice);
        let angle = atan2(toNeuron.y, toNeuron.x);
        let dendrite = 0.5 + 0.5 * cos(angle * branches + time * (1.2 + treble * 3.0) + seed);
        let aura = pulse * dendrite / (dist * (2.5 + density) + 0.35);
        activity += aura;
        sparks += exp(-dist * (20.0 + treble * 15.0)) * (0.3 + 0.7 * abs(pulse));

        // ── Idea 1: axon fibres + travelling action potentials ──────────
        // A neuron has an axon as well as dendrites: wire neuron i to i+1 and
        // i+3 (wrapping). The fibre is lit by the SOURCE neuron's own firing
        // (the same pulse term as above, so cells near the pointer fire first
        // and the cascade leaves the cursor along the wires); a packet runs
        // source→end at a rate that rides Signal Speed. Packets are
        // faded in/out at the fibre ends so the wrap never pops.
        let fire = clamp(max(pulse, 0.0) * 1.6, 0.0, 1.0);
        for (var k: u32 = 0u; k < 2u; k = k + 1u) {
            let axonEnd = neuronAt((i + 1u + k * 2u) % nodeCount);
            let sd = segmentDist(uv, neuronPos, axonEnd);
            let fibre = exp(-sd.x * 260.0);
            let pp = fract(time * (0.22 + signalSpeed * 0.18) + hash(vec2<f32>(seed, 3.3 + f32(k))));
            let packetD = (sd.y - pp) * 9.0;
            let packet = exp(-packetD * packetD) * smoothstep(0.0, 0.12, pp) * smoothstep(1.0, 0.88, pp);
            fibreGlow += fibre * (0.06 + 0.5 * fire);
            spikeGlow += fibre * packet * (0.15 + 1.6 * fire);
        }
    }

    // ── Click synapse bursts: each live ripple fires a temporary neuron ──
    // A click injects an expanding, decaying (~2s) pulse wave into the field.
    var clickBurst = 0.0;
    var clickSparks = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r: u32 = 0u; r < rippleCount; r = r + 1u) {
        let ripple = u.ripples[r];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.0) {
            continue;
        }
        // Decay slider also shortens/lengthens the burst tail.
        let fade = exp(-age * (2.0 + decayRate));
        let toClick = uv - ripple.xy;
        let clickDist = max(length(toClick), 0.001);
        // Signal Speed slider drives how fast the shockwave expands.
        let waveFront = age * (0.35 + signalSpeed * 0.2);
        let ring = sin((clickDist - waveFront) * 40.0) * exp(-abs(clickDist - waveFront) * 12.0);
        let strength = 0.6 + 0.4 * clamp(ripple.w, 0.0, 1.0);
        clickBurst += ring * fade * strength / (clickDist * 4.0 + 0.6);
        clickSparks += exp(-clickDist * 24.0) * fade * strength * 0.8;
    }
    activity += clickBurst;
    sparks += clickSparks;

    // ── Idea 2: spike-rate afterglow ─────────────────────────────────
    // A firing neuron lingers instead of flickering with |pulse|: the spark
    // field keeps max(now, previous · keep) from the exact previous-frame A
    // (A.g IS sparks, so C.g read back is the same quantity — raw sim state,
    // never tone-mapped). `keep` rides the Decay slider (more decay = shorter
    // tail), so the slider keeps its role. max() keeps it bounded.
    let prevSparks = clamp(textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).g, 0.0, 6.0);
    let afterKeep = mix(0.985, 0.90, clamp(decayRate / 2.5, 0.0, 1.0));
    sparks = max(sparks, prevSparks * afterKeep);

    let mouseDist = distance(uv, mousePos);
    let mousePulse = sin(mouseDist * (16.0 + treble * 12.0) - time * (7.0 + bass * 4.0)) *
        exp(-mouseDist * (3.0 + density)) * (0.3 + bass * 0.7);

    let totalActivity = activity + mousePulse;
    let sampleUV = clamp(
        uv + vec2<f32>(totalActivity * 0.025, activity * 0.015 + mousePulse * 0.01),
        vec2<f32>(0.001, 0.001),
        vec2<f32>(0.999, 0.999)
    );
    let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let electricBlue = vec3<f32>(0.05, 0.45 + treble * 0.15, 1.0) * max(totalActivity, 0.0);
    let synapsePurple = vec3<f32>(0.9, 0.15, 1.0) * max(-totalActivity, 0.0) * 0.65;
    let warmSparks = vec3<f32>(1.0, 0.7 + mids * 0.2, 0.25) * sparks * (0.12 + bass * 0.08);
    // Cyan flash riding the click shockwave so bursts read as fresh firings.
    let clickGlow = vec3<f32>(0.35, 0.85, 1.0) * max(clickBurst, 0.0) * 0.45;
    // Idea 1 light: cool fibre, near-white action-potential packet.
    let axonLight = vec3<f32>(0.20, 0.55, 0.95) * fibreGlow * 0.5 + vec3<f32>(0.85, 0.95, 1.0) * spikeGlow * 0.9;
    let finalColor = baseColor.rgb + electricBlue + synapsePurple + warmSparks + clickGlow + axonLight;
    let alpha = clamp(baseColor.a * 0.38 + abs(totalActivity) * 0.28 + sparks * 0.2 + (fibreGlow * 0.5 + spikeGlow) * 0.12 + bass * 0.05, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + abs(totalActivity) * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(totalActivity, sparks, mousePulse, alpha));
}
