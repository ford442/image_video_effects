# Swarm Brief: bio_lenia_continuous

**Role:** Algorithmist
**Name:** Lenia Continuous
**Category:** generative
**Description:** Continuous cellular automata (Lenia) with smooth growth functions, multiple kernel radii, and biological emergence patterns
**Current lines:** 192
**Target lines:** 242–282 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This continuous Lenia sim has good feedback discipline but confused uniform semantics - clean the gates, then give it seasons and a second species:
- FIX THE SPAWN GATE (priority 1): `mouseClickCount = u.config.y` is the engine's ripple count - it stays > 0 forever after the first click, so the mouse spawns life continuously without being held. Gate mouse seeding on `u.zoom_config.w > 0.5` (mouse-DOWN) instead. Also fix `audioPulse = u.zoom_config.w` (mouse-down mislabeled as audio): route real audio from `plasmaBuffer[0].y` (mids) to a slow growthCenter wobble (audio 'seasons' - classic Lenia modulation).
- Second species: store a competing species in the free dataTextureA.g channel with its own bell() kernel parameters and a cross-feeding term (species A inhibits B where dense), so red/green colonies visibly compete. Keep species B's dynamics in the existing dataTextureC read-back path (A packs both channels).
- Click seed bombs: loop the ripples[] uniform (guard `min(u32(u.config.y), 50u)`) - each live ripple drops a circular species-B seed blob at the click point, decaying with ripple age.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the `bell()` growth/kernel functions, the clamp(newState, 0.0, 1.0), and the dataTextureA.r primary-species state layout VERBATIM - the feedback contract depends on them. dataTextureA is SIM STATE - never clamp/tonemap it. The O(r^2) kernel loop is expensive by design; do not restructure it.

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
  "id": "bio_lenia_continuous",
  "name": "Lenia Continuous",
  "url": "shaders/bio_lenia_continuous.wgsl",
  "description": "Continuous cellular automata (Lenia) with smooth growth functions, multiple kernel radii, and biological emergence patterns",
  "tags": [
    "lenia",
    "cellular-automata",
    "biological",
    "emergence",
    "simulation"
  ],
  "features": [
    "feedback-loop",
    "mouse-spawn",
    "audio-reactive",
    "continuous-ca"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Radius",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Growth Center",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Growth Width",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Time Step",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.7,
  "updatedParams": [
    {
      "index": 0,
      "name": "Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 1,
      "name": "Growth Center",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 2,
      "name": "Growth Width",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 3,
      "name": "Time Step",
      "default": 0.3,
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
//  bio_lenia_continuous.wgsl - Continuous Cellular Automata (Lenia)
//  
//  Agent: Algorithmist + Interactivist
//  Techniques:
//    - Lenia continuous CA (smoothLife-like)
//    - Multiple kernel radii
//    - Growth function with bell curve
//    - Mouse spawn / clear interaction
//    - Audio-reactive growth parameters
//  
//  Target: 4.7★ rating
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

// Bell curve function for Lenia growth
fn bell(x: f32, m: f32, s: f32) -> f32 {
    return exp(-pow((x - m) / s, 2.0) / 2.0);
}

// Smooth step
fn smoothStep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// Lenia kernel (smooth ring)
fn kernel(r: f32, radius: f32) -> f32 {
    if (r > radius) {
        return 0.0;
    }
    // Ring kernel: peaks at r = radius/2
    let peak = radius * 0.5;
    return bell(r, peak, radius * 0.15);
}

// Growth function for Lenia
fn growth(neighborhood: f32, growthCenter: f32, growthWidth: f32) -> f32 {
    return bell(neighborhood, growthCenter, growthWidth) * 2.0 - 1.0;
}

// Sample previous state
fn sampleState(uv: vec2<f32>, tex: texture_2d<f32>) -> f32 {
    return textureSampleLevel(tex, non_filtering_sampler, uv, 0.0).r;
}

// Pseudo-random
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Color mapping based on cell age/value
fn leniaColor(value: f32, time: f32) -> vec3<f32> {
    // Biological color palette
    let hue = 0.25 + value * 0.15 + sin(time * 0.1) * 0.05; // Green to yellow
    let sat = 0.6 + value * 0.4;
    let val = 0.3 + value * 0.7;
    
    // HSV to RGB
    let c = val * sat;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = val - c;
    
    var rgb: vec3<f32>;
    let h = hue * 6.0;
    if (h < 1.0) {
        rgb = vec3<f32>(c, x, 0.0);
    } else if (h < 2.0) {
        rgb = vec3<f32>(x, c, 0.0);
    } else if (h < 3.0) {
        rgb = vec3<f32>(0.0, c, x);
    } else if (h < 4.0) {
        rgb = vec3<f32>(0.0, x, c);
    } else if (h < 5.0) {
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
    let invRes = 1.0 / resolution;
    
    // Parameters
    let radius = 5.0 + u.zoom_params.x * 15.0;           // 5-20 pixel radius
    let growthCenter = 0.15 + u.zoom_params.y * 0.25;    // 0.15-0.4
    let growthWidth = 0.01 + u.zoom_params.z * 0.04;     // 0.01-0.05
    let dt = 0.1 + u.zoom_params.w * 0.2;                // 0.1-0.3 time step
    
    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let mouseClickCount = u.config.y;
    let audioPulse = u.zoom_config.w;
    
    // Sample current state from dataTextureC (feedback)
    let currentState = sampleState(uv, dataTextureC);
    
    // Calculate neighborhood integral
    var neighborhood = 0.0;
    var kernelSum = 0.0;
    let r = i32(radius);
    
    for (var dy: i32 = -r; dy <= r; dy = dy + 1) {
        for (var dx: i32 = -r; dx <= r; dx = dx + 1) {
            let d = sqrt(f32(dx * dx + dy * dy));
            if (d > radius) {
                continue;
            }
            
            let sampleUV = uv + vec2<f32>(f32(dx), f32(dy)) * invRes;
            let k = kernel(d, radius);
            neighborhood += sampleState(sampleUV, dataTextureC) * k;
            kernelSum += k;
        }
    }
    
    // Normalize
    if (kernelSum > 0.0) {
        neighborhood /= kernelSum;
    }
    
    // Apply growth function
    let g = growth(neighborhood, growthCenter, growthWidth);
    
    // Update state
    var newState = currentState + dt * g;
    newState = clamp(newState, 0.0, 1.0);
    
    // Mouse spawn: if mouse is nearby and clicked, add life
    let toMouse = length(uv - mousePos);
    if (toMouse < 0.05 && mouseClickCount > 0.0) {
        newState = 1.0;
    }
    
    // Random seeding if very dead
    if (newState < 0.01 && rand(uv + time) < 0.001 * (1.0 + audioPulse)) {
        newState = rand(uv + time * 2.0);
    }
    
    // Audio modulates growth center
    newState = clamp(newState + audioPulse * 0.1, 0.0, 1.0);
    
    // Color mapping
    var color = leniaColor(newState, time);
    
    // Add glow around living cells
    let glow = smoothStep(0.2, 0.8, newState) * 0.5;
    color += vec3<f32>(0.4, 0.8, 0.3) * glow;
    
    // Tone map
    color = color / (1.0 + color);
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(newState, 0.0, 0.0, 1.0));
    
    // Store state for next frame
    textureStore(dataTextureA, coord, vec4<f32>(newState, 0.0, 0.0, 1.0));
}
```
