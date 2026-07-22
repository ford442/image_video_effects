# Swarm Brief: retro_phosphor_dream

**Role:** Interactivist
**Name:** Phosphor Dream
**Category:** generative
**Description:** Authentic CRT simulation with RGB phosphor triads, persistence afterglow, interlaced flicker, barrel distortion, and chromatic aberration
**Current lines:** 175
**Target lines:** 225–265 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This CRT emulator has a LATENT BUG and zero real interactivity - fix the bug, then make it respond:
- FIX THE BUG (priority 1): audioPulse is bound to u.zoom_config.w (MouseDown) and plasmaBuffer is declared but never read - rewire audioPulse to plasmaBuffer[0].x (bass) so persistence decay + glow actually pump with music, not clicks.
- Analog hum & jitter: treble (plasmaBuffer[0].z) drives subtle scanline phase jitter plus a slow vertical hum-bar roll for authentic analog noise.
- Mouse degauss: mouse X modulates curvature strength; on mouse-down trigger a temporary degauss wobble (time-decaying sinusoidal UV offset) using u.zoom_config.yz/w.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the phosphor persistence uses max(current, prev*decay) - it cannot blow out additively, but keep decay <= 0.95. Preserve the barrel distortion, RGB triad mask, and vignette math; upgrade, don't rewrite. Keep JSON steps/defaults as-is (saved-preset contract).

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
  "id": "retro_phosphor_dream",
  "name": "Phosphor Dream",
  "url": "shaders/retro_phosphor_dream.wgsl",
  "description": "Authentic CRT simulation with RGB phosphor triads, persistence afterglow, interlaced flicker, barrel distortion, and chromatic aberration",
  "tags": [
    "crt",
    "retro",
    "phosphor",
    "analog",
    "vintage"
  ],
  "features": [
    "temporal-persistence",
    "audio-reactive",
    "phosphor-glow"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Curvature",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Phosphor Size",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Scanlines",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Flicker",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.6,
  "updatedParams": [
    {
      "index": 0,
      "name": "Curvature",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 1,
      "name": "Phosphor Size",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 2,
      "name": "Scanlines",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 3,
      "name": "Flicker",
      "default": 0.2,
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
//  retro_phosphor_dream.wgsl - Authentic CRT Phosphor Simulation
//  
//  Agent: Visualist + Algorithmist
//  Techniques:
//    - RGB phosphor triad subpixel simulation
//    - Persistence/decay from phosphor afterglow
//    - Interlaced scanline flicker
//    - Barrel distortion with chromatic aberration
//    - Vignette and screen curvature
//  
//  Target: 4.6★ rating
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

// Hash
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Phosphor triad pattern
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

// Scanline pattern
fn scanlines(uv: vec2<f32>, intensity: f32, time: f32) -> f32 {
    let scanline = sin(uv.y * 480.0 * PI + time * 0.1) * 0.5 + 0.5;
    return 1.0 - (scanline * intensity);
}

// Interlaced flicker
fn interlaceFlicker(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let field = floor(time * 30.0) % 2.0;
    let line = floor(uv.y * 240.0) % 2.0;
    let flicker = select(1.0, 0.85, line == field);
    return 1.0 - (1.0 - flicker) * intensity;
}

// Phosphor persistence (temporal afterglow)
fn phosphorGlow(current: vec3<f32>, prev: vec3<f32>, decay: f32) -> vec3<f32> {
    return max(current, prev * decay);
}

// Chromatic aberration for barrel edges
fn chromaticAberration(uv: vec2<f32>, strength: f32, tex: texture_2d<f32>, smp: sampler) -> vec3<f32> {
    let centered = uv - 0.5;
    let r = length(centered);
    let aberration = strength * r * r;
    
    let rUV = uv + normalize(centered) * aberration;
    let gUV = uv;
    let bUV = uv - normalize(centered) * aberration;
    
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
    
    // Parameters
    let curvature = u.zoom_params.x * 0.3;           // 0-0.3
    let phosphorSize = 0.001 + u.zoom_params.y * 0.003; // 0.001-0.004
    let scanlineIntensity = u.zoom_params.z * 0.5;   // 0-0.5
    let flickerIntensity = u.zoom_params.w * 0.3;    // 0-0.3
    
    // Audio reactivity affects glow
    let audioPulse = u.zoom_config.w;
    
    // Apply barrel distortion to UV
    let distortedUV = barrelDistort(uv, curvature);
    
    // Chromatic aberration at edges
    var color = chromaticAberration(distortedUV, curvature * 0.5, readTexture, u_sampler);
    
    // Sample with phosphor mask
    let triad = phosphorTriad(uv, phosphorSize);
    color *= 0.7 + triad * 0.6;
    
    // Scanlines
    color *= scanlines(uv, scanlineIntensity, time);
    
    // Interlaced flicker
    color *= interlaceFlicker(uv, time, flickerIntensity);
    
    // Temporal phosphor persistence
    let prevFrame = textureLoad(dataTextureC, coord, 0).rgb;
    color = phosphorGlow(color, prevFrame, 0.85 + audioPulse * 0.1);
    
    // Film grain
    color *= filmGrain(uv, time);
    
    // Vignette from screen edge
    let edgeDist = length(uv - 0.5) * 1.4;
    let vignette = 1.0 - edgeDist * edgeDist * 0.5;
    color *= vignette;
    
    // HDR boost for phosphor bloom
    color = color * (1.0 + audioPulse * 0.5);
    
    // Tone map
    color = color / (1.0 + color * 0.5);
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    
    // Store for persistence
    textureStore(dataTextureA, coord, vec4<f32>(color, 1.0));
}
```
