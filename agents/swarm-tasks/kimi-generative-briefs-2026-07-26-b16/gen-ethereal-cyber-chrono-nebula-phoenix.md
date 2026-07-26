# Swarm Brief: gen-ethereal-cyber-chrono-nebula-phoenix

**Role:** Visualist
**Name:** Ethereal Cyber-Chrono Nebula-Phoenix
**Category:** generative
**Description:** A majestic, hyper-organic cybernetic phoenix rising from a deep-space nebula, its wings woven from liquid auroral plasma and shattered quantum glass that burst into geometric temporal fractals upon acoustic climax.
**Current lines:** 144
**Target lines:** 194–234 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This SDF phoenix claims to be audio-reactive (it is tagged 'audio-reactive') but its audio is dead - resurrect it, then tame the HDR:
- FIX THE DEAD AUDIO (priority 1): the shader reads `audio` from `u.config.y`, which is the engine's RIPPLE COUNT (near-constant, not sound) - the 'audio-reactive' tag is a lie. Rewire: bass (`plasmaBuffer[0].x`) drives the attractor `a` constant wobble and wing plasma pulse; treble (`plasmaBuffer[0].z`) drives the chronoGlow shimmer.
- Tame the HDR: bgColor scaled by (1+audio*2) plus additive chronoGlow/mouseGlow has NO tonemap - once real audio lands this blows out. Add a hue-preserving clamp at ~2.0 followed by ACES (Narkowicz) before the writeTexture store.
- Spring-damper phoenix halo: ease the mouse glow center with a critically-damped spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the phoenix's attention glides; add a click ripple ring (guard `min(u32(u.config.y), 50u)`) that momentarily flares the wing plasma as it expands.
- Wire the 2 existing slider params via u.zoom_params.x/y using the EXISTING JSON controls (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-1. These param ids/defaults are the saved-preset contract: do not rename or re-default them, and do NOT invent params for z/w.
- Make each slider drive meaningful shader-specific constants in the WGSL.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the `sdPhoenix` SDF constants and the `attractorTrap` Clifford constants (-1.4, 1.6, 1.0, 0.7, 24 iters) VERBATIM - the silhouette is hand-tuned. The JSON uses a non-standard `controls[]` schema with ONLY 2 params (wingspan x, plasma_intensity y) - do NOT invent new params or restructure the JSON; updatedParams mirrors just those 2 (handled outside the WGSL). zoom_params.z/w stay unused.

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
  "id": "gen-ethereal-cyber-chrono-nebula-phoenix",
  "name": "Ethereal Cyber-Chrono Nebula-Phoenix",
  "description": "A majestic, hyper-organic cybernetic phoenix rising from a deep-space nebula, its wings woven from liquid auroral plasma and shattered quantum glass that burst into geometric temporal fractals upon acoustic climax.",
  "url": "shaders/gen-ethereal-cyber-chrono-nebula-phoenix.wgsl",
  "category": "generative",
  "tags": [
    "organic",
    "quantum",
    "cosmic",
    "biomechanical",
    "phoenix",
    "audio-reactive"
  ],
  "controls": [
    {
      "id": "wingspan",
      "name": "Wingspan",
      "type": "range",
      "min": 0.05,
      "max": 0.5,
      "step": 0.01,
      "default": 0.1,
      "uniformMapping": {
        "struct": "zoom_params",
        "field": "x"
      }
    },
    {
      "id": "plasma_intensity",
      "name": "Plasma Intensity",
      "type": "range",
      "min": 0.1,
      "max": 1.0,
      "step": 0.05,
      "default": 0.2,
      "uniformMapping": {
        "struct": "zoom_params",
        "field": "y"
      }
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Wingspan",
      "default": 0.1,
      "min": 0.05,
      "max": 0.5,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Plasma Intensity",
      "default": 0.2,
      "min": 0.1,
      "max": 1.0,
      "step": 0.05
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ----------------------------------------------------------------
// Ethereal Cyber-Chrono Nebula-Phoenix (upgraded)
// Category: generative
// ----------------------------------------------------------------
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};
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
const PI: f32 = 3.14159265359;
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + 0.25 * q;
}
// Clifford-like strange attractor used as a chrono-orbit trap
fn attractorTrap(p: vec2<f32>, t: f32, audio: f32) -> f32 {
    var z = p * 2.0;
    var trap = 100.0;
    let a = -1.4 + audio * 0.3;
    let b = 1.6 + sin(t * 0.2) * 0.1;
    let c = 1.0;
    let d = 0.7;
    let orbitTarget = vec2<f32>(0.4 * sin(t), 0.3 * cos(t));
    for (var i = 0; i < 24; i = i + 1) {
        let nx = sin(a * z.y) + c * cos(a * z.x);
        let ny = sin(b * z.x) + d * cos(b * z.y);
        z = vec2<f32>(nx, ny);
        trap = min(trap, length(z - orbitTarget));
    }
    return trap;
}

// SDF silhouette: cybernetic phoenix body, wings and tail
fn sdPhoenix(p: vec2<f32>, wingspan: f32) -> f32 {
    let body = length(vec2<f32>(p.x * 4.0, max(0.0, abs(p.y) - 0.22))) - 0.06;
    let wingY = p.y - 0.12;
    let wingX = abs(p.x) - 0.06;
    let wingUV = rot(0.25 + wingspan * 2.0) * vec2<f32>(wingX, wingY);
    let wing = length(vec2<f32>(wingUV.x * 0.35 / wingspan, wingUV.y * 2.5)) - 0.12;
    let tailUV = vec2<f32>(p.x * 2.0, p.y + 0.35);
    let tail = length(vec2<f32>(tailUV.x, max(0.0, -tailUV.y))) - 0.1 + 0.08 * sin(p.y * 20.0);
    return min(min(body, wing), tail);
}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let res = vec2<f32>(dims);
    let uv01 = vec2<f32>(id.xy) / res;
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / min(res.x, res.y);

    let time = u.config.x;
    let audio = u.config.y;
    let mouse = u.zoom_config.yz;
    let wingspan = clamp(u.zoom_params.x, 0.05, 0.5);
    let plasma = u.zoom_params.y;

    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
    let inDepthUV = clamp(uv01, vec2<f32>(0.0), vec2<f32>(1.0));
    let inDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, inDepthUV, 0.0).r;

    // Domain-warped FBM nebula background
    let warp = domainWarp(uv * 2.0 + vec2<f32>(time * 0.02), time * 0.05);
    var nebula = fbm(warp * 3.0, 5);
    nebula += 0.5 * fbm(warp * 6.0 + audio, 4);
    let bgColor = vec3<f32>(0.08, 0.05, 0.15) * nebula * (1.0 + audio * 2.0);

    // Strange-attractor chrono fractal as an orbit trap
    let trap = attractorTrap(uv * 1.5, time, audio);
    let chronoGlow = exp(-trap * 6.0) * (0.5 + 0.5 * audio);

    // Phoenix SDF and orbit-trap coloring
    var p = uv;
    p = rot(mouse.x * 2.0 + time * 0.1) * p;
    let d = sdPhoenix(p, wingspan);
    let edge = abs(d);
    let density = smoothstep(0.12, 0.0, d);
    let shell = exp(-edge * 12.0);

    // Cosmic palette driven by orbit traps and audio
    let pal = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(0.0, 0.33, 0.67) * PI * 2.0 + time * 0.5 - trap * 2.0);
    var phoenixColor = pal * (density + shell * 0.6);
    phoenixColor += vec3<f32>(1.0, 0.4, 0.1) * chronoGlow * plasma;

    // Branchless mouse-interaction halo
    let mouseDist = length(uv01 - mouse);
    let mouseGlow = exp(-mouseDist * 20.0) * (0.3 + audio);
    phoenixColor += vec3<f32>(0.4, 0.8, 1.0) * mouseGlow;

    // Composite over video background
    var color = mix(video.rgb, phoenixColor, clamp(density + shell * 0.5, 0.0, 1.0));
    color = mix(color, bgColor, 0.35 * (1.0 - density));

    // Meaningful alpha: emission + occlusion, not forced to 1.0
    let alpha = clamp(density + shell * 0.4 + chronoGlow * 0.2, 0.0, 1.0);

    // Depth: phoenix in front, input depth preserved where transparent
    let depth = mix(inDepth, 0.2 + density * 0.6, clamp(density + shell * 0.5, 0.0, 1.0));

    textureStore(writeTexture, id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(trap, d, nebula, alpha));
}
```
