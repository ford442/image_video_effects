// ═══════════════════════════════════════════════════════════════════════════════
//  interactive_neural_swarm.wgsl - Neural Network Swarm Visualization (Batch 18)
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-10-19
//  Ideas: myelinated axons with saltatory node hops; synaptic bouton arrival flare;
//         dendritic spines breathing with activation
//  A packing: ACES display RGB + max activation in A.a (C unused)
//
//  Role: Interactivist
//  Techniques:
//    - Agent-based neural swarm (particles = neurons, hash-placed topology)
//    - Curl-noise drift field (divergence-free organic motion, per neuron)
//    - O(N^2) proximity connection weights with dynamic modulation
//    - Signal propagation: traveling pulses along axons + click wavefronts
//    - Spring-dampered mouse attractor (persistent state in extraBuffer)
//    - Honest audio: bass = global energy, per-neuron FFT bins = activation
//    - Honest depth from neuron proximity / signal strength (never constant)
//
//  State layout (extraBuffer safe zone [133..255] only):
//    [133..134] attractor position    [135..136] attractor velocity
//    [137]      attractor init flag
//
//  Audio map (plasmaBuffer, read-only):
//    [0].x           = bass -> global activation energy
//    [1 + (i%8)].x   = per-neuron FFT bin -> per-neuron activation
//
//  Engine uniform truth: config = [time, rippleCount, resW, resH]
//    zoom_config = [time, mouseX, mouseY, mouseDown] (w is a BUTTON, not audio)
//
//  Target: 4.8★ rating
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const MAX_NEURONS: i32 = 40;
const CONNECTION_RADIUS: f32 = 0.15;
const TAU: f32 = 6.28318530718;
const MYELIN_NODES: f32 = 6.0;     // [idea 1] nodes of Ranvier per axon
const SPINE_COUNT: i32 = 5;        // [idea 3] dendritic spines per soma

// extraBuffer safe zone [133..255]: spring-dampered mouse attractor state
const ATTRACT_X: i32 = 133;
const ATTRACT_Y: i32 = 134;
const ATTRACT_VX: i32 = 135;
const ATTRACT_VY: i32 = 136;
const ATTRACT_INIT: i32 = 137;

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn smoothFalloff(d: f32, radius: f32) -> f32 {
    let x = d / radius;
    return pow(max(1.0 - x * x, 0.0), 2.0);
}

// Divergence-free curl of the hash field: organic flow without sinks/sources
fn curlNoise2(p: vec2<f32>) -> vec2<f32> {
    let e = 0.01;
    let n1 = hash2(p + vec2<f32>(e, 0.0)) - hash2(p - vec2<f32>(e, 0.0));
    let n2 = hash2(p + vec2<f32>(0.0, e)) - hash2(p - vec2<f32>(0.0, e));
    return vec2<f32>(n2, -n1) / (2.0 * e);
}

// Generate neuron positions — hash placement preserved VERBATIM (topology
// emerges from these exact constants; do not retune).
fn getNeuronPos(i: i32, time: f32, mousePos: vec2<f32>) -> vec2<f32> {
    let fi = f32(i);
    let hash1 = hash2(vec2<f32>(fi * 1.618, fi * 2.718));
    let hash2v = hash2(vec2<f32>(fi * 3.142, fi * 1.414));

    let baseX = hash1 * 0.8 + 0.1;
    let baseY = hash2v * 0.8 + 0.1;

    // Curl-noise drift replaces the old sin/cos wobble: each neuron rides a
    // divergence-free flow sampled at ITS OWN base position (not per-pixel).
    let flowP = vec2<f32>(baseX, baseY) * 3.0 + vec2<f32>(time * 0.07, -time * 0.05);
    let drift = curlNoise2(flowP) * 0.03;

    // Mouse attraction (neurons cluster near the spring-dampered attractor)
    let toMouse = mousePos - vec2<f32>(baseX, baseY);
    let attraction = toMouse * 0.2 * smoothstep(0.5, 0.0, length(toMouse));

    return vec2<f32>(baseX, baseY) + drift + attraction;
}

// Connection weight — O(N^2) pairing preserved VERBATIM from the original.
fn connectionStrength(p1: vec2<f32>, p2: vec2<f32>, time: f32) -> f32 {
    let dist = length(p1 - p2);
    if (dist > CONNECTION_RADIUS || dist < 0.001) {
        return 0.0;
    }
    let baseStrength = 1.0 - dist / CONNECTION_RADIUS;
    let modulation = sin(time * 2.0 + dist * 20.0) * 0.3 + 0.7;
    return baseStrength * modulation;
}

// Expanding stimulus ring from the attractor (speed is slider-driven)
fn signalWave(uv: vec2<f32>, source: vec2<f32>, time: f32, speed: f32) -> f32 {
    let dist = length(uv - source);
    let wave = sin(dist * 30.0 - time * speed * 5.0);
    let envelope = smoothstep(0.4, 0.0, dist) * smoothstep(0.0, 0.05, dist);
    return wave * envelope;
}

// Distance to segment a->b, returns (distance, h along segment)
fn segDist(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return vec2<f32>(length(pa - ba * h), h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn glow(uv: vec2<f32>, center: vec2<f32>, intensity: f32, radius: f32) -> f32 {
    let dist = length(uv - center);
    return intensity / (1.0 + dist * dist * 100.0 / (radius * radius));
}

// Neon HSV ramp driven by activation level
fn activationColor(activation: f32, baseHue: f32) -> vec3<f32> {
    let hue = baseHue + activation * 0.2;
    let sat = 0.8 + activation * 0.2;
    let val = 0.5 + activation * 0.5;
    let c = val * sat;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = val - c;
    var rgb: vec3<f32>;
    if (hue < 1.0 / 6.0) {
        rgb = vec3<f32>(c, x, 0.0);
    } else if (hue < 2.0 / 6.0) {
        rgb = vec3<f32>(x, c, 0.0);
    } else if (hue < 3.0 / 6.0) {
        rgb = vec3<f32>(0.0, c, x);
    } else if (hue < 4.0 / 6.0) {
        rgb = vec3<f32>(0.0, x, c);
    } else if (hue < 5.0 / 6.0) {
        rgb = vec3<f32>(x, 0.0, c);
    } else {
        rgb = vec3<f32>(c, 0.0, x);
    }
    return rgb + m;
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

    // ── Sliders (saved-preset contract: zoom_params.x/y/z/w) ──────────────
    let connectionThreshold = u.zoom_params.x;        // param1: visibility gate
    let signalSpeed = 0.5 + u.zoom_params.y * 2.0;    // param2: 0.5..2.5 pulse rate
    let glowRadius = 0.02 + u.zoom_params.z * 0.03;   // param3: 0.02..0.05 soma size
    let networkDensity = u.zoom_params.w;             // param4: gates neuron count

    // ── Honest audio (plasmaBuffer FFT, not the mouse button) ─────────────
    let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
    let clickPulse = u.zoom_config.w;                 // mouse-DOWN: stimulus only
    let rawMouse = u.zoom_config.yz;

    // ── Spring-dampered mouse attractor (extraBuffer safe zone) ───────────
    // Thread (0,0) integrates a critically-damped spring toward the raw mouse
    // so the stimulus source glides instead of teleporting between clicks.
    if (global_id.x == 0u && global_id.y == 0u) {
        var pos = vec2<f32>(extraBuffer[ATTRACT_X], extraBuffer[ATTRACT_Y]);
        var vel = vec2<f32>(extraBuffer[ATTRACT_VX], extraBuffer[ATTRACT_VY]);
        if (extraBuffer[ATTRACT_INIT] < 0.5) {
            pos = rawMouse;
            vel = vec2<f32>(0.0);
        }
        let omega = 8.0;
        let dt = 0.016;
        let accel = omega * omega * (rawMouse - pos) - 2.0 * omega * vel;
        vel += accel * dt;
        pos += vel * dt;
        extraBuffer[ATTRACT_X] = pos.x;
        extraBuffer[ATTRACT_Y] = pos.y;
        extraBuffer[ATTRACT_VX] = vel.x;
        extraBuffer[ATTRACT_VY] = vel.y;
        extraBuffer[ATTRACT_INIT] = 1.0;
    }
    let mousePos = vec2<f32>(extraBuffer[ATTRACT_X], extraBuffer[ATTRACT_Y]);

    // Network Density is honest now: it gates the ACTIVE neuron count (20..40),
    // not just downstream brightness.
    let activeNeurons = i32(mix(20.0, f32(MAX_NEURONS), networkDensity));

    var color = vec3<f32>(0.02, 0.02, 0.04);

    // Ambient neural mist: faint hash dither so the void never reads flat
    let mist = hash2(floor(uv * 24.0) + vec2<f32>(floor(time * 0.5)));
    color += vec3<f32>(0.010, 0.014, 0.030) * mist * (0.6 + bass * 0.4);

    // ── Click signal wavefronts (ripples carry (x, y, startTime, _)) ──────
    // Each click emits an expanding activation ring that propagates through
    // the connection web: it lights pixels AND boosts neuron/web activity.
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleWave = 0.0;
    for (var ri: u32 = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age > 0.0 && age < 4.0) {
            let dist = length(uv - rp.xy);
            let front = age * 0.65;
            rippleWave += exp(-pow((dist - front) * 18.0, 2.0)) * exp(-age * 1.6);
        }
    }

    // Attractor stimulus ring: louder with bass, sharper while the button is held
    let mouseSignal = signalWave(uv, mousePos, time, signalSpeed);
    color += vec3<f32>(0.3, 0.6, 1.0) * abs(mouseSignal) * (0.4 + bass * 0.6 + clickPulse * 0.5);
    color += vec3<f32>(0.5, 0.9, 1.0) * rippleWave * 0.8;

    // proximityField accumulates neuron proximity + signal strength per pixel;
    // it is the honest input for the depth write below.
    var proximityField = 0.0;
    var maxActivation = 0.0;

    for (var i: i32 = 0; i < activeNeurons; i = i + 1) {
        let pos = getNeuronPos(i, time, mousePos);
        let neuronGlow = glow(uv, pos, 1.0, glowRadius);

        // Per-neuron activation: attractor proximity + bass energy + own FFT bin
        let bin = plasmaBuffer[1u + u32(i) % 8u].x;
        let toMouse = length(pos - mousePos);
        let baseActivation = smoothstep(0.3, 0.0, toMouse);
        let activation = baseActivation + bass * 0.5 + bin * 0.4 + rippleWave * 0.3;
        maxActivation = max(maxActivation, activation);

        // Soma glow + activation halo ring (radius breathes with activation)
        let neuronColor = activationColor(activation, f32(i) / f32(MAX_NEURONS));
        let somaDist = length(uv - pos);
        let halo = smoothFalloff(somaDist, glowRadius * 4.0 * (1.0 + activation)) * 0.15 * activation;
        color += neuronColor * neuronGlow * (0.5 + activation);
        color += neuronColor * halo;
        proximityField += neuronGlow * (0.5 + activation) + halo;

        // [idea 3] Dendritic spines: short tapered spokes at hashed angles that
        // reach further as the neuron activates (dendrites "listening").
        let spineLen = glowRadius * (2.2 + activation * 1.6);
        let spineSeed = hash2(vec2<f32>(f32(i) * 7.31, 2.9)) * TAU;
        for (var k: i32 = 0; k < SPINE_COUNT; k = k + 1) {
            let a = spineSeed + f32(k) * TAU / f32(SPINE_COUNT) + sin(time * 0.7 + f32(k) * 1.9 + f32(i)) * 0.25;
            let tip = pos + vec2<f32>(cos(a), sin(a)) * spineLen;
            let sd = segDist(uv, pos, tip);
            let width = mix(0.0026, 0.0006, sd.y);
            let spine = smoothstep(width, 0.0, sd.x) * smoothstep(0.25, 0.45, sd.y);
            color += neuronColor * spine * (0.25 + activation * 0.35);
            proximityField += spine * 0.2;
        }

        // Draw connections to nearby neurons (O(N^2) pairing preserved)
        for (var j: i32 = i + 1; j < activeNeurons; j = j + 1) {
            let pos2 = getNeuronPos(j, time, mousePos);
            let strength = connectionStrength(pos, pos2, time);

            if (strength > connectionThreshold * 0.5) {
                // Distance to the axon segment
                let pa = uv - pos;
                let ba = pos2 - pos;
                let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
                let dist = length(pa - ba * h);

                let connectionGlow = smoothstep(0.005, 0.0, dist) * strength;

                // Action potential traveling along the axon; click wavefronts
                // passing through the web amplify it (signal propagation).
                let alongLine = h;
                let signal = sin(alongLine * 10.0 - time * signalSpeed * 3.0 + f32(i));
                let webBoost = 1.0 + rippleWave * 1.5;
                let signalGlow = smoothstep(0.1, 0.0, abs(signal - alongLine)) * strength * webBoost;

                let connectionColor = mix(
                    vec3<f32>(0.3, 0.5, 0.8),
                    vec3<f32>(0.8, 0.3, 0.6),
                    activation
                );

                color += connectionColor * connectionGlow * 0.3;
                color += vec3<f32>(1.0, 0.9, 0.7) * signalGlow * 0.5 * (0.5 + bass);
                proximityField += (connectionGlow + signalGlow) * 0.5;

                // [idea 1] Myelin sheath: beads at the nodes of Ranvier. The
                // spike hops node to node (saltatory conduction) rather than
                // gliding: hopPhase advances continuously, the lit node steps.
                let nodeIdx = round(h * MYELIN_NODES);
                let nodePos = pos + ba * (nodeIdx / MYELIN_NODES);
                let nodeD = length(uv - nodePos);
                let nodeBead = smoothstep(0.0045, 0.0, nodeD) * strength;
                let hopPhase = fract(time * signalSpeed * 0.45 + hash2(vec2<f32>(f32(i), f32(j))));
                let hopIdx = floor(hopPhase * (MYELIN_NODES + 1.0));
                let hopLit = select(0.0, 1.0, nodeIdx == hopIdx) * webBoost;
                color += connectionColor * nodeBead * 0.35;
                color += vec3<f32>(1.0, 0.95, 0.8) * smoothstep(0.009, 0.0, nodeD) * hopLit * strength * (0.6 + bass * 0.5);

                // [idea 2] Synaptic bouton: terminal knob just short of the
                // receiving soma that flares as the spike reaches the last node.
                let boutonPos = pos + ba * 0.9;
                let boutonD = length(uv - boutonPos);
                let arrival = select(0.0, 1.0, hopIdx >= MYELIN_NODES) * (1.0 - fract(hopPhase * (MYELIN_NODES + 1.0)));
                let bouton = smoothstep(0.006, 0.0, boutonD) * strength;
                let flare = glow(uv, boutonPos, arrival * strength, glowRadius * 0.6);
                color += mix(connectionColor, vec3<f32>(1.0, 0.85, 0.95), 0.5) * (bouton * 0.4 + flare * 0.9);
                proximityField += nodeBead * 0.3 + hopLit * nodeBead + flare * 0.5;
            }
        }
    }

    // Global network pulse (breathing), scaled by density so sparse nets rest
    let networkPulse = sin(time * 0.5) * 0.5 + 0.5;
    color *= 1.0 + networkPulse * networkDensity * 0.3;

    // Tone mapping (ACES on display) + vignette
    color = acesToneMap(color * 0.9);
    color *= 1.0 - length(uv - 0.5) * 0.3;

    // ── Honest depth: derived from neuron proximity / signal strength ─────
    // Active somas, axons and wavefronts push TOWARD the camera (lower depth)
    // instead of the old constant 0.0 write that clobbered the layer chain.
    let inDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let signalField = clamp(proximityField * 0.6 + maxActivation * 0.4 + rippleWave * 0.3, 0.0, 1.0);
    let depth = mix(inDepth, 0.15 + (1.0 - signalField) * 0.55, clamp(signalField * 2.0, 0.0, 1.0));

    // Semantic alpha: network coverage (somas, axons, spines, wavefronts)
    let alpha = clamp(0.15 + signalField * 0.85, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // dataTextureA: color + activation/field stats for downstream layers
    textureStore(dataTextureA, coord, vec4<f32>(color, maxActivation));
}
