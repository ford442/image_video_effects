# Swarm Brief: interactive_neural_swarm

**Role:** Interactivist
**Name:** Neural Swarm
**Category:** generative
**Description:** Agent-based neural network visualization with signal propagation, connection weights, and emergent activation patterns
**Current lines:** 221
**Target lines:** 271–311 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This neural swarm claims 'audio-reactive' but reads the mouse button as audio, and its depth write clobbers the chain - wake it up:
- FIX THE FAKE AUDIO (priority 1): `audioPulse = u.zoom_config.w` is mouse-DOWN, not audio - plasmaBuffer is never read. Rewire: bass (`plasmaBuffer[0].x`) drives global activation energy, and each neuron i reads its own FFT bin (`plasmaBuffer[1 + (i % 8)].x`) for per-neuron activation. ALSO make 'Network Density' honest: it currently only scales brightness - let it also gate the active neuron count (e.g. 20-40 neurons).
- Honest depth: the shader writes constant 0.0 depth, clobbering the chain - write depth derived from neuron proximity/signal strength instead.
- Click signal waves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) emitting expanding activation wavefronts from each click that propagate through the connection web; spring-damper the mouse attractor (extraBuffer[133..135]); replace the sin/cos neuron drift with a curl-noise drift field.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve `getNeuronPos` hash placement and the O(N^2) `connectionStrength` loop VERBATIM - network topology emerges from those exact hash constants. extraBuffer in [133..255] ONLY.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "interactive_neural_swarm",
  "name": "Neural Swarm",
  "url": "shaders/interactive_neural_swarm.wgsl",
  "description": "Agent-based neural network visualization with signal propagation, connection weights, and emergent activation patterns",
  "tags": [
    "neural",
    "network",
    "swarm",
    "interactive",
    "neon",
    "biological"
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "agent-based",
    "signal-propagation",
    "neon"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Connection Threshold",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Signal Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Glow Radius",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Network Density",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.8,
  "updatedParams": [
    {
      "index": 0,
      "name": "Connection Threshold",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 1,
      "name": "Signal Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 2,
      "name": "Glow Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 3,
      "name": "Network Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════════════════
//  interactive_neural_swarm.wgsl - Neural Network Swarm Visualization
//  
//  Agent: Interactivist + Visualist + Algorithmist
//  Techniques:
//    - Agent-based neural swarm (particles = neurons)
//    - Connection weights based on proximity
//    - Signal propagation through network
//    - Mouse = stimulus source, Audio = activation energy
//  
//  Target: 4.8★ rating
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const NUM_NEURONS: i32 = 40;
const CONNECTION_RADIUS: f32 = 0.15;

// Hash function
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Smooth falloff
fn smoothFalloff(d: f32, radius: f32) -> f32 {
    let x = d / radius;
    return pow(max(1.0 - x * x, 0.0), 2.0);
}

// Generate neuron positions
fn getNeuronPos(i: i32, time: f32, mousePos: vec2<f32>) -> vec2<f32> {
    let fi = f32(i);
    let hash1 = hash2(vec2<f32>(fi * 1.618, fi * 2.718));
    let hash2 = hash2(vec2<f32>(fi * 3.142, fi * 1.414));
    
    // Base position with organic movement
    let baseX = hash1 * 0.8 + 0.1;
    let baseY = hash2 * 0.8 + 0.1;
    
    // Slow organic drift
    let drift = vec2<f32>(
        sin(time * 0.3 + fi * 0.5) * 0.05,
        cos(time * 0.4 + fi * 0.3) * 0.05
    );
    
    // Mouse attraction (neurons cluster near mouse)
    let toMouse = mousePos - vec2<f32>(baseX, baseY);
    let attraction = toMouse * 0.2 * smoothstep(0.5, 0.0, length(toMouse));
    
    return vec2<f32>(baseX, baseY) + drift + attraction;
}

// Calculate connection strength
fn connectionStrength(p1: vec2<f32>, p2: vec2<f32>, time: f32) -> f32 {
    let dist = length(p1 - p2);
    if (dist > CONNECTION_RADIUS || dist < 0.001) {
        return 0.0;
    }
    
    // Dynamic weight
    let baseStrength = 1.0 - dist / CONNECTION_RADIUS;
    let modulation = sin(time * 2.0 + dist * 20.0) * 0.3 + 0.7;
    
    return baseStrength * modulation;
}

// Signal propagation visualization
fn signalWave(uv: vec2<f32>, source: vec2<f32>, time: f32, speed: f32) -> f32 {
    let dist = length(uv - source);
    let wave = sin(dist * 30.0 - time * speed * 5.0);
    let envelope = smoothstep(0.4, 0.0, dist) * smoothstep(0.0, 0.05, dist);
    return wave * envelope;
}

// Glow effect
fn glow(uv: vec2<f32>, center: vec2<f32>, intensity: f32, radius: f32) -> f32 {
    let dist = length(uv - center);
    return intensity / (1.0 + dist * dist * 100.0 / (radius * radius));
}

// Neon color based on activation
fn activationColor(activation: f32, baseHue: f32) -> vec3<f32> {
    let hue = baseHue + activation * 0.2;
    let sat = 0.8 + activation * 0.2;
    let val = 0.5 + activation * 0.5;
    
    // HSV to RGB
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
    
    // Parameters
    let connectionThreshold = u.zoom_params.x;        // 0-1
    let signalSpeed = 0.5 + u.zoom_params.y * 2.0;    // 0.5-2.5
    let glowRadius = 0.02 + u.zoom_params.z * 0.03;   // 0.02-0.05
    let networkDensity = u.zoom_params.w;             // 0-1
    
    // Inputs
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Background
    var color = vec3<f32>(0.02, 0.02, 0.04);
    
    // Mouse signal wave
    let mouseSignal = signalWave(uv, mousePos, time, signalSpeed);
    color += vec3<f32>(0.3, 0.6, 1.0) * abs(mouseSignal) * (0.5 + audioPulse);
    
    // Process neurons
    for (var i: i32 = 0; i < NUM_NEURONS; i = i + 1) {
        let pos = getNeuronPos(i, time, mousePos);
        let neuronGlow = glow(uv, pos, 1.0, glowRadius);
        
        // Neuron activation from mouse proximity and audio
        let toMouse = length(pos - mousePos);
        let baseActivation = smoothstep(0.3, 0.0, toMouse);
        let activation = baseActivation + audioPulse * hash2(vec2<f32>(f32(i), time));
        
        // Add neuron glow
        let neuronColor = activationColor(activation, f32(i) / f32(NUM_NEURONS));
        color += neuronColor * neuronGlow * (0.5 + activation);
        
        // Draw connections to nearby neurons
        for (var j: i32 = i + 1; j < NUM_NEURONS; j = j + 1) {
            let pos2 = getNeuronPos(j, time, mousePos);
            let strength = connectionStrength(pos, pos2, time);
            
            if (strength > connectionThreshold * 0.5) {
                // Distance to line segment
                let pa = uv - pos;
                let ba = pos2 - pos;
                let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
                let dist = length(pa - ba * h);
                
                // Connection glow
                let connectionGlow = smoothstep(0.005, 0.0, dist) * strength;
                
                // Signal traveling along connection
                let alongLine = h;
                let signal = sin(alongLine * 10.0 - time * signalSpeed * 3.0 + f32(i));
                let signalGlow = smoothstep(0.1, 0.0, abs(signal - alongLine)) * strength;
                
                let connectionColor = mix(
                    vec3<f32>(0.3, 0.5, 0.8),
                    vec3<f32>(0.8, 0.3, 0.6),
                    activation
                );
                
                color += connectionColor * connectionGlow * 0.3;
                color += vec3<f32>(1.0, 0.9, 0.7) * signalGlow * 0.5 * (0.5 + audioPulse);
            }
        }
    }
    
    // Global network pulse
    let networkPulse = sin(time * 0.5) * 0.5 + 0.5;
    color *= 1.0 + networkPulse * networkDensity * 0.3;
    
    // Tone mapping
    color = color / (1.0 + color);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    color *= vignette;
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    
    // Store for feedback
    textureStore(dataTextureA, coord, vec4<f32>(color, 1.0));
}
```
