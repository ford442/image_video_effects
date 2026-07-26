# Swarm Brief: kimi_fractal_dreams

**Role:** Visualist
**Name:** Kimi Fractal Dreams
**Category:** generative
**Description:** Multi-layer fractal with orbit traps, burning ship variant, and smooth color cycling.
**Current lines:** 186
**Target lines:** 236–276 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This Burning-Ship Julia dreamscape has a latent NaN and mislabeled sliders - guard the math, then smooth the dream:
- FIX THE NaN RISK (priority 1): `cdiv(0.1, z + 0.01)` divides by a near-zero denominator when z ~= (-0.01, -0.01) (only reachable when complexity > 1.5), producing inf/NaN pixels. Add a small epsilon guard on the denominator magnitude (e.g. max(length2, 1e-4)) inside or around cdiv - do not change the formula's behavior elsewhere.
- Spring-damper Julia morph: smooth the mouse-driven Julia constant with a critically-damped spring (2-4 extraBuffer slots in [133..255]) so c glides instead of lerping at fixed 0.5; add click ripples (guard `min(u32(u.config.y), 50u)`) as temporary zoom-pulse impulses decaying with ripple age.
- Orbit-trap palette + treble filaments: key an IQ cosine palette on the orbit-trap distance, and extend treble reactivity to per-bin `plasmaBuffer[1..k]` filament glow so high-hat energy lights the fractal edges.
- Honest sliders (preset contract): JSON names are mislabeled vs. code (Intensity=zoom, Speed=iterations, Scale=colorCycles) and CANNOT be renamed. Keep JSON as-is; in WGSL give each slider an ADDITIONAL honest effect matching its label (e.g. 'Speed' also drives layer rotation rate) without changing the default look.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the Burning-Ship abs() + cmul iteration core and the smooth-escape `smoothIter = i - log2(log2(r)) + 4.0` formula VERBATIM; the 3-layer rotation by 1.047 rad with 0.8 scale is the visual signature. extraBuffer persistent state in [133..255] ONLY.

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

## JSON Parameters / Controls

```json
{
  "id": "kimi-fractal-dreams",
  "name": "Kimi Fractal Dreams",
  "url": "shaders/kimi_fractal_dreams.wgsl",
  "description": "Multi-layer fractal with orbit traps, burning ship variant, and smooth color cycling.",
  "features": [
    "mouse-driven",
    "generative",
    "fractal",
    "julia-set",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "procedural",
    "generative"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Detail",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Detail",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Kimi Fractal Dreams
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-06-06
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Kimi Fractal Dreams - Multi-layer fractal with orbit traps

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Complex number operations
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let denom = b.x * b.x + b.y * b.y;
    return vec2<f32>((a.x * b.x + a.y * b.y) / denom, (a.y * b.x - a.x * b.y) / denom);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.1;

    // Audio reactivity: bass pulses the zoom, mids cycle color, treble glows orbit traps
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse interaction
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Aspect correct coordinates
    let aspect = resolution.x / resolution.y;
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;
    
    // Mouse controls Julia set constant
    var mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= aspect;
    let c = mix(vec2<f32>(-0.8, 0.156), mousePos, 0.5);
    
    // Parameters
    let zoom = (u.zoom_params.x * 3.0 + 0.5) * (1.0 + bass * 0.2);
    let iterations = i32(u.zoom_params.y * 100.0) + 50;
    let colorCycles = (u.zoom_params.z * 5.0 + 1.0) * (1.0 + mids * 0.5);
    let complexity = u.zoom_params.w * 2.0 + 0.5;
    
    // Zoom towards mouse
    p = (p - mousePos) / zoom + mousePos;
    
    // Multiple fractal layers
    var col = vec3<f32>(0.0);
    var totalWeight = 0.0;
    
    let layers = 3;
    for (var layer = 0; layer < layers; layer++) {
        let fi = f32(layer);
        let layerC = c + vec2<f32>(cos(time + fi), sin(time + fi)) * 0.1;
        var z = p;
        
        var orbitTrap = 1000.0;
        var minRadius = 1000.0;
        
        let layerIter = iterations + layer * 20;
        
        for (var i = 0; i < layerIter; i++) {
            // Burning Ship variant with Julia
            z = vec2<f32>(abs(z.x), abs(z.y));
            z = cmul(z, z) + layerC;
            
            // Additional complexity
            if (complexity > 1.5) {
                z = z + cdiv(vec2<f32>(0.1, 0.0), z + vec2<f32>(0.01));
            }
            
            // Orbit traps
            let r = length(z);
            orbitTrap = min(orbitTrap, abs(r - 0.5));
            minRadius = min(minRadius, r);
            
            if (r > 4.0) {
                // Smooth coloring
                let smoothIter = f32(i) - log2(log2(r)) + 4.0;
                
                // Color based on escape time and orbit trap
                let hue = fract(smoothIter * 0.01 * colorCycles + fi * 0.33);
                let sat = 0.8;
                let light = 0.5 + orbitTrap * 2.0;
                
                // HSL to RGB
                let c1 = (1.0 - abs(2.0 * light - 1.0)) * sat;
                var x = c1 * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
                let m = light - c1 * 0.5;
                
                var layerCol: vec3<f32>;
                if (hue < 1.0 / 6.0) { layerCol = vec3<f32>(c1, x, 0.0); }
                else if (hue < 2.0 / 6.0) { layerCol = vec3<f32>(x, c1, 0.0); }
                else if (hue < 3.0 / 6.0) { layerCol = vec3<f32>(0.0, c1, x); }
                else if (hue < 4.0 / 6.0) { layerCol = vec3<f32>(0.0, x, c1); }
                else if (hue < 5.0 / 6.0) { layerCol = vec3<f32>(x, 0.0, c1); }
                else { layerCol = vec3<f32>(c1, 0.0, x); }
                layerCol += vec3<f32>(m);
                
                // Glow from orbit trap (treble intensifies the filament glow)
                layerCol += vec3<f32>(1.0, 0.8, 0.6) * orbitTrap * 2.0 * (1.0 + treble * 1.5);
                
                let weight = 1.0 / (1.0 + fi);
                col += layerCol * weight;
                totalWeight += weight;
                break;
            }
        }
        
        // Rotation for next layer
        let rot = vec2<f32>(
            p.x * cos(1.047) - p.y * sin(1.047),
            p.x * sin(1.047) + p.y * cos(1.047)
        );
        p = rot * 0.8;
    }
    
    if (totalWeight > 0.0) {
        col /= totalWeight;
    } else {
        col = vec3<f32>(0.02, 0.0, 0.05);
    }
    
    // Mouse glow
    let dist = length(uv - mouse);
    col += vec3<f32>(1.0, 0.9, 0.7) * smoothstep(0.3, 0.0, dist) * mouseDown * 0.5;
    
    // Post-processing
    col = pow(col, vec3<f32>(0.9));
    col *= 1.2;

    // Alpha: fractal escape coverage + glow luminance, never flat 1.0
    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(smoothstep(0.0, 1.0, totalWeight) * 0.5 + lum * 0.6, 0.0, 1.0);
    let out = vec4<f32>(acesToneMap(col * 1.1), alpha);

    // Depth: brighter escaped filaments read as nearer
    let depth = clamp(lum, 0.0, 1.0);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
```
