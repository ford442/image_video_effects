// ═══════════════════════════════════════════════════════════════════
//  Neon Neural Network
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-14
//  Ideas: leaky integrate-and-fire neurons (closed-form interspike interval τ·ln(I/(I−θ)) + absolute refractory period) driving spike flashes and membrane-potential glow; saltatory conduction along myelinated axons (action potential hops node-of-Ranvier to node-of-Ranvier, launched at the presynaptic spike)
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Intensity, .y = Signal Speed, .z = Network Scale, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

// ═══ LIF neuron constants ═══
const LIF_TAU: f32 = 0.22;      // membrane time constant (s)
const LIF_THETA: f32 = 1.0;     // firing threshold
const LIF_REFRACT: f32 = 0.12;  // absolute refractory period (s)
const INTERNODE: f32 = 0.045;   // myelin internode length (network units)

// ═══ CHUNK: acesToneMap (canonical ACES) ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hash functions for procedural generation
fn hash2(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let q = p3 + dot(p3, p3.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Neon palette
fn neonColor(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}

fn neonColor2(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.1, 0.2);
    return a + b * cos(TAU * (c * t + d));
}

// Smooth minimum for soft blob blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ═══ ReLU Activation: R(x) = max(0, x) ═══
fn relu(x: f32) -> f32 {
    return max(0.0, x);
}

// ═══ Neural layer computation: output = R(W·input + b) ═══
fn neuralLayer(input: f32, weight: f32, bias: f32) -> f32 {
    return relu(weight * input + bias);
}

// ── IDEA 1: leaky integrate-and-fire neuron ──
// τ dV/dt = −V + I. With constant drive I > θ, V charges from reset (0) to θ in
// T = τ·ln(I / (I − θ)); after each spike the cell is clamped for T_ref.
// Returns (time since last spike, interspike period, V/θ, fires?).
fn lifNeuron(I: f32, seed: f32, time: f32) -> vec4<f32> {
    if (I <= LIF_THETA * 1.001) {
        // Subthreshold: membrane settles at V = I, never fires.
        return vec4<f32>(1e3, 1e3, clamp(I / LIF_THETA, 0.0, 1.0), 0.0);
    }
    let T = LIF_TAU * log(I / (I - LIF_THETA));
    let period = T + LIF_REFRACT;
    let since = fract(time / period + seed) * period;
    let charging = max(since - LIF_REFRACT, 0.0);
    let v = I * (1.0 - exp(-charging / LIF_TAU));
    return vec4<f32>(since, period, clamp(v / LIF_THETA, 0.0, 1.0), 1.0);
}

// Node structure - concentric ring layers
fn getNodePos(layer: i32, idx: i32, totalLayers: i32, time: f32) -> vec2<f32> {
    let fi = f32(idx);
    let fl = f32(layer);
    let nodesInLayer = 4 + layer * 2;
    let fx = hash1(fl * 37.0 + fi * 13.0 + 0.5);
    let fy = hash1(fl * 71.0 + fi * 29.0 + 1.3);
    
    let x = -0.75 + fl / f32(totalLayers - 1) * 1.5;
    let y = (fi / f32(nodesInLayer - 1) - 0.5) * 1.2;
    
    // Breathing animation
    let breathe = sin(time * 2.0 + fl * 1.5 + fi * 0.7) * 0.03;
    let drift = sin(time * 0.5 + fl + fi * 2.0) * 0.02;
    
    return vec2<f32>(x + drift + breathe, y + sin(time + fi) * 0.015);
}

// SDF for a line segment with glow
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Parametric position (0..1) of the closest point on a segment
fn segmentH(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let ba = b - a;
    return clamp(dot(p - a, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
}

// Signal pulse along an edge
fn signalPulse(edgeLen: f32, edgeIdx: f32, time: f32, speed: f32) -> f32 {
    let pulsePos = fract(time * speed * 0.3 + edgeIdx * 0.17);
    let pulseWidth = 0.08;
    let d = abs(pulsePos * edgeLen - 0.5 * edgeLen);
    return exp(-d * d / (pulseWidth * pulseWidth));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let minRes = max(min(res.x, res.y), 1.0);
    let uv = (vec2<f32>(pixel) - res * 0.5) / minRes;
    
    let time = u.config.x;
    // zoom_config.yz is mouse uv (0..1) → same centered space as uv
    let mousePos = (u.zoom_config.yz * res - res * 0.5) / minRes;
    let mouseDown = u.zoom_config.w > 0.5;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Bass drives input layer activation intensity
    let audioSpeed = speed * (0.85 + bass * 0.4);
    // Mids control synaptic connection strength
    let synapticStrength = 0.5 + mids * 0.8;
    
    let baseScale = 0.5 + scale * 1.5;
    let p = uv * baseScale;
    
    var col = vec3<f32>(0.02, 0.01, 0.03);
    
    // Mouse cursor node
    var cursorPos = mousePos * baseScale;
    let cursorPulse = sin(time * 4.0) * 0.5 + 0.5;
    let cursorRadius = 0.04 * (0.8 + cursorPulse * 0.3);

    // Axonal conduction velocity (network units / s), set by Signal Speed
    let condVel = 0.25 + audioSpeed * 1.6;
    
    // Background grid glow
    let gridDist = min(
        abs(fract(p.x * 6.0) - 0.5) * 2.0,
        abs(fract(p.y * 6.0) - 0.5) * 2.0
    );
    let gridLine = exp(-gridDist * gridDist * 300.0) * 0.06;
    col += vec3<f32>(0.05, 0.02, 0.08) * gridLine;

    // Click ripples = stimulating electrode: an expanding depolarisation front
    let rippleCount = min(u32(u.config.y), 50u);
    
    // Neural network layers as concentric rings
    let totalLayers = 6;
    
    var nodeField: f32 = 1e6;
    var edgeGlow: f32 = 0.0;
    var signalGlow: vec3<f32> = vec3<f32>(0.0);
    var nodeGlow: vec3<f32> = vec3<f32>(0.0);
    var backpropGlow: vec3<f32> = vec3<f32>(0.0);
    var spikeEnergy: f32 = 0.0;
    var ranvierGlow: f32 = 0.0;
    var stimRing: f32 = 0.0;
    
    var edgeIndex: f32 = 0.0;

    // Electrode rings (drawn once, in network space)
    for (var r = 0u; r < rippleCount; r = r + 1u) {
        let rp = u.ripples[r];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.0) {
            let rc = (rp.xy * res - res * 0.5) / minRes * baseScale;
            let front = length(p - rc) - age * 0.6;
            stimRing += exp(-front * front * 900.0) * exp(-age * 2.0);
        }
    }
    
    // Process all nodes and connections
    for (var layer = 0; layer < totalLayers; layer++) {
        let nodesInThisLayer = 4 + layer * 2;
        let nextLayerNodes = 4 + (layer + 1) * 2;
        
        for (var ni = 0; ni < nodesInThisLayer; ni++) {
            let nodePos = getNodePos(layer, ni, totalLayers, time);
            
            // Distance to this node
            let d = length(p - nodePos);
            nodeField = smin(nodeField, d, 0.08);
            
            // ═══ ReLU neuron firing threshold ═══
            // Neuron activation: R(dot(weights, input) + bias)
            let inputSignal = sin(time * 3.0 + f32(layer) * 1.2 + f32(ni) * 0.9) * 0.5 + 0.5;
            let weight = hash1(f32(layer) * 17.0 + f32(ni) * 31.0 + 0.5);
            let bias = hash1(f32(layer) * 53.0 + f32(ni) * 19.0 + 0.3) * 0.2 - 0.1;
            let activation = relu(weight * inputSignal * (1.0 + bass * 0.5) + bias);

            // Injected current: ReLU activation + cursor (held) + electrode fronts
            var stim = 0.0;
            if (mouseDown) {
                stim += 1.2 * exp(-length(cursorPos - nodePos) * 6.0);
            }
            for (var r = 0u; r < rippleCount; r = r + 1u) {
                let rp = u.ripples[r];
                let age = time - rp.z;
                if (age >= 0.0 && age < 2.0) {
                    let rc = (rp.xy * res - res * 0.5) / minRes * baseScale;
                    let front = length(nodePos - rc) - age * 0.6;
                    stim += 1.5 * exp(-front * front * 40.0) * exp(-age * 1.5);
                }
            }
            let nodeSeed = hash1(f32(layer) * 91.0 + f32(ni) * 7.0 + 2.1);
            // Tonic drive sets the interspike interval. It is kept time-invariant
            // (synaptic weight + Intensity) so the closed-form phase stays
            // coherent; fast inputs (ReLU activation, cursor, electrodes)
            // depolarise the membrane on top and can force extra spikes.
            let I = 0.75 + weight * (0.9 + intensity * 0.8) + bias;
            let lif = lifNeuron(I, nodeSeed, time);
            // Action potential: sharp spike, then refractory undershoot
            let spike = max(exp(-lif.x * 28.0) * lif.w, clamp(stim, 0.0, 1.0));
            let refractoryDim = select(1.0, 0.55, lif.w > 0.5 && lif.x < LIF_REFRACT);
            
            // Node glow scaled by ReLU activation
            let nodeSize = 0.018 + 0.005 * sin(time * 3.0 + f32(layer) * 1.2 + f32(ni) * 0.9);
            let nGlow = exp(-d * d / (nodeSize * nodeSize * 4.0));
            let nodeHue = f32(layer) / f32(totalLayers) + colorShift;
            let nodeCol = neonColor(nodeHue + time * 0.05);
            // Membrane potential charges the soma glow; spikes flash white-hot
            nodeGlow += nodeCol * nGlow * (0.6 + 0.4 * sin(time * 4.0 + f32(ni) * 1.7)) * (0.3 + activation * 1.1 + lif.z * 0.7) * refractoryDim;
            nodeGlow += mix(nodeCol, vec3<f32>(1.0), 0.6) * exp(-d * d / (nodeSize * nodeSize * 10.0)) * spike * (1.6 + treble * 0.5);
            spikeEnergy += nGlow * (spike + lif.z * 0.3);
            
            // Connections to next layer
            if (layer < totalLayers - 1) {
                for (var nj = 0; nj < nextLayerNodes; nj++) {
                    // Only connect some nodes for visual clarity
                    let connectionHash = hash1(f32(layer) * 100.0 + f32(ni) * 17.0 + f32(nj) * 31.0);
                    if (connectionHash > 0.55) {
                        let nextNodePos = getNodePos(layer + 1, nj, totalLayers, time);
                        let edgeDist = sdSegment(p, nodePos, nextNodePos);
                        let edgeWidth = 0.004 * (0.8 + 0.2 * sin(time * 2.0 + f32(layer) * 0.8));
                        
                        // Base edge glow modulated by synaptic strength (mids)
                        let eGlow = exp(-edgeDist * edgeDist / (edgeWidth * edgeWidth * 12.0));
                        let edgeHue = (f32(layer) / f32(totalLayers) + colorShift) * 0.7;
                        let edgeCol = neonColor2(edgeHue + time * 0.03);
                        edgeGlow += eGlow * 0.25 * intensity * synapticStrength;
                        
                        // Tonic signal pulses along edges
                        let edgeLen = length(nextNodePos - nodePos);
                        let pulse = signalPulse(edgeLen, edgeIndex, time, audioSpeed * 2.0 + 0.5);
                        let pulseGlow = exp(-edgeDist * edgeDist / (edgeWidth * edgeWidth * 6.0)) * pulse;
                        let sigHue = fract(edgeIndex * 0.15 + time * 0.08 + colorShift);
                        signalGlow += neonColor(sigHue) * pulseGlow * intensity * 0.6;

                        // ── IDEA 2: saltatory conduction ──
                        // The presynaptic spike launches an action potential down a
                        // myelinated axon. Under myelin it is invisible; it
                        // regenerates only at each node of Ranvier, so the glow
                        // hops node to node at the conduction velocity.
                        if (lif.w > 0.5 && eGlow > 1e-3) {
                            let h = segmentH(p, nodePos, nextNodePos);
                            let s = h * edgeLen;                          // arc length from soma
                            let sNode = floor(s / INTERNODE + 0.5) * INTERNODE; // nearest node to pixel
                            let atNode = exp(-pow((s - sNode) / (INTERNODE * 0.14), 2.0));
                            var flash = 0.0;
                            // Spike train: the current AP and the two before it
                            for (var k = 0; k < 3; k++) {
                                let front = (lif.x + f32(k) * lif.y) * condVel;      // continuous AP front
                                let hopNode = floor(front / INTERNODE) * INTERNODE; // last regenerated node
                                let hopAge = (front - hopNode) / INTERNODE;         // 0..1 within a hop
                                let isCurrent = exp(-pow((sNode - hopNode) / (INTERNODE * 0.5), 2.0));
                                let alive = step(sNode, edgeLen) * step(front, edgeLen + INTERNODE);
                                flash += atNode * isCurrent * exp(-hopAge * 3.0) * alive;
                            }
                            // Myelin sheath: faint beads between nodes
                            let sheath = (1.0 - atNode) * 0.08 * intensity;
                            let axon = exp(-edgeDist * edgeDist / (edgeWidth * edgeWidth * 5.0));
                            signalGlow += neonColor(sigHue) * axon * (flash * intensity * 3.2 + sheath) * synapticStrength;
                            ranvierGlow += axon * flash;
                        }
                        
                        // ═══ Treble-driven backpropagation "error glow" ═══
                        let errorSignal = hash1(edgeIndex * 73.0 + time * 0.1) * treble * 1.2;
                        let errorGlow = exp(-edgeDist * edgeDist / (edgeWidth * edgeWidth * 3.0)) * errorSignal;
                        backpropGlow += vec3<f32>(1.0, 0.2, 0.1) * errorGlow * 0.4;
                        
                        edgeIndex += 1.0;
                    }
                }
            }
            
            // Check proximity to mouse cursor
            if (mouseDown) {
                let toCursor = length(cursorPos - nodePos);
                if (toCursor < 0.35) {
                    let connDist = sdSegment(p, nodePos, cursorPos);
                    let connWidth = 0.006;
                    let connGlow = exp(-connDist * connDist / (connWidth * connWidth * 8.0));
                    let connHue = fract(f32(ni) * 0.1 + time * 0.1 + colorShift);
                    signalGlow += neonColor(connHue) * connGlow * 1.5 * (1.0 - toCursor / 0.35);
                }
            }
        }
    }
    
    // Apply edge glow color
    col += vec3<f32>(0.15, 0.25, 0.4) * edgeGlow;
    
    // Apply signal glow
    col += signalGlow;
    
    // Apply backpropagation error glow (treble-driven)
    col += backpropGlow;
    
    // Apply node glow
    col += nodeGlow;

    // Electrode stimulation fronts
    col += neonColor(colorShift + 0.5) * stimRing * (0.6 + bass * 0.4);
    
    // Central bright core on nodes
    let coreGlow = exp(-nodeField * nodeField * 500.0) * 0.8;
    col += vec3<f32>(0.9, 0.95, 1.0) * coreGlow * intensity;
    
    // Cursor node
    let cursorDist = length(p - cursorPos);
    let cursorGlow = exp(-cursorDist * cursorDist / (cursorRadius * cursorRadius * 4.0));
    let cursorCol = neonColor(0.0 + colorShift + time * 0.05);
    col += cursorCol * cursorGlow * (1.0 + select(0.0, 0.8, mouseDown));
    
    // Vignette
    let vignette = 1.0 - dot(uv, uv) * 0.4;
    col *= vignette;
    
    // ═══ Chromatic Aberration ═══
    let caStr = 0.003 * (1.0 + bass);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);
    col = max(col, vec3<f32>(0.0));
    
    // ═══ Temporal Feedback (exact load of last frame's display RGBA) ═══
    let maxC = vec2<i32>(i32(dims.x) - 1, i32(dims.y) - 1);
    let prev = textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), maxC), 0);
    col = mix(prev.rgb * 0.96, col, 0.25);
    
    // ═══ ACES Tone Map + Semantic Alpha ═══
    let display = acesToneMap(col * (1.1 + bass * 0.1));
    // Alpha = neural activity coverage: axons, spiking somata, AP hops, stimulus fronts
    let alpha = clamp(edgeGlow * 0.8 + spikeEnergy * 0.6 + ranvierGlow * 0.5 + coreGlow * 0.4
                      + stimRing * 0.3 + cursorGlow * 0.3 + prev.a * 0.15, 0.04, 0.95);
    // Depth: deeper layers recede; somata and firing nodes pop forward
    let depth = clamp((1.0 - (p.x / baseScale + 0.75) / 1.5) * 0.35 + coreGlow * 0.4 + clamp(spikeEnergy, 0.0, 1.0) * 0.25, 0.0, 1.0);
    let finalColor = vec4<f32>(display, alpha);
    
    textureStore(writeTexture, pixel, finalColor);
    textureStore(dataTextureA, pixel, finalColor);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
