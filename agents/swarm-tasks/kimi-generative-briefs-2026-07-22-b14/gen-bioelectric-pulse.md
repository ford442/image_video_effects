# Swarm Brief: gen-bioelectric-pulse

**Role:** Interactivist
**Name:** Bioelectric Pulse
**Category:** generative
**Description:** Reaction-diffusion-like organic pulses through a noise-driven substrate. Audio energizes the pulse field, and mouse activation emits a secondary bioelectric wave.
**Current lines:** 180
**Target lines:** 230–270 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This shader has the same mouse-coordinate bug class we fixed in Batch 13 - fix it, then make the name honest with real feedback:
- FIX THE MOUSE BUG (priority 1): the shader reads mouse position from u.zoom_config.xy, but x is TIME - the mouse pulse is glued to a drifting wrong coordinate. Engine convention is u.zoom_config.yz = mouse position, .w = mouse-down (verified in src/renderer/UniformBuffer.ts). Fix all mouse reads.
- Honest reaction trails: add real dataTextureC temporal feedback (mix ~0.1, decay 0.9, clamp pre-tint at ~1.2) so pulses leave phosphor trails - the shader's reaction-diffusion name becomes earned.
- Kick mega-pulse: track a smoothed bass envelope in extraBuffer[133] and a last-trigger time in extraBuffer[134]; when bass exceeds its envelope by a threshold (kick transient), fire a screen-center mega-pulse (retrigger gap ~0.3s).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: extraBuffer persistent state goes in [133..255] ONLY ([0..4] reserved, [5..132] = engine FFT bins). Keep the final 0-1 output clamp and the wandering-center motion intact.

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
  "id": "gen-bioelectric-pulse",
  "name": "Bioelectric Pulse",
  "category": "generative",
  "url": "shaders/gen-bioelectric-pulse.wgsl",
  "description": "Reaction-diffusion-like organic pulses through a noise-driven substrate. Audio energizes the pulse field, and mouse activation emits a secondary bioelectric wave.",
  "features": [
    "generative",
    "reaction-diffusion",
    "organic-pulses",
    "glow",
    "fbm-noise",
    "palette",
    "audio-reactive",
    "mouse-driven",
    "depth-aware"
  ],
  "tags": [
    "procedural",
    "generative",
    "bioelectric",
    "organic",
    "reaction-diffusion",
    "pulse",
    "noise",
    "audio-reactive",
    "vj"
  ],
  "workgroup_size": [
    16,
    16,
    1
  ],
  "params": [
    {
      "id": "pulseCount",
      "name": "Pulse Count",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "speed",
      "name": "Pulse Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "pulseWidth",
      "name": "Pulse Width",
      "default": 0.45,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "hueShift",
      "name": "Hue Shift",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "supportsDepth": true,
  "supportsDof": false,
  "updated": true,
  "updatedParams": [
    {
      "index": 0,
      "name": "Pulse Count",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Pulse Speed",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Pulse Width",
      "default": 0.45,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Hue Shift",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ]
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Bioelectric Pulse - Reaction-diffusion-like organic pulses
//  Category: generative
//  Features: generative, reaction-diffusion, organic-pulses, glow,
//            fbm-noise, audio-reactive, mouse-activation, depth-aware
//  Agent 4a — Phase A shader upgrade swarm
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
  config: vec4<f32>,       // x=Time, y=unused, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=MouseX, y=MouseY, z=unused, w=MouseDown
  zoom_params: vec4<f32>,  // x=PulseCount, y=Speed, z=PulseWidth, w=HueShift
  ripples: array<vec4<f32>, 50>,
};

// ── Chunk: hash12 (from gen_grid.wgsl / chunk-library) ────────────
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Chunk: valueNoise (from gen_grid.wgsl) ────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uS = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, uS.x), mix(c, d, uS.x), uS.y);
}

// ── Chunk: fbm2 (from chunk-library) ──────────────────────────────
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ── Chunk: palette (from chunk-library) ───────────────────────────
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ── Chunk: glow (from anamorphic-flare.wgsl) ──────────────────────
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius + 1e-6)) * intensity;
}

// Reaction-diffusion wave kernel: sum of decaying radial pulses
fn rdPulse(p: vec2<f32>, center: vec2<f32>, time: f32, speed: f32, width: f32) -> f32 {
    let d = length(p - center);
    let phase = d * 8.0 - time * speed * 4.0;
    let wave = sin(phase) * 0.5 + 0.5;
    let envelope = exp(-d * d * 2.0) * (1.0 - smoothstep(0.0, 1.5, d));
    return wave * envelope * glow(d, width, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(gid.xy);
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / max(res.y, 1.0);
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;

    // Audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Clamp/normalize zoom_params
    let pulseCount = mix(1.0, 5.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let speed = mix(0.3, 1.5, clamp(u.zoom_params.y, 0.0, 1.0));
    let pulseWidth = mix(0.1, 0.4, clamp(u.zoom_params.z, 0.0, 1.0));
    let hueShift = clamp(u.zoom_params.w, 0.0, 1.0);

    // Mouse activation point
    let mouse = (u.zoom_config.xy - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDown = step(0.5, u.zoom_config.w);

    // Organic noise substrate
    let n1 = fbm2(p * 2.0 + vec2<f32>(0.0, time * 0.05), 4);
    let n2 = fbm2(p * 3.0 + vec2<f32>(5.2, 1.3) + time * 0.03, 4);
    let substrate = fbm2(p * 1.5 + 2.0 * vec2<f32>(n1, n2), 4);

    // Multiple organic pulse centers
    var pulseField = 0.0;
    let baseCenters = array<vec2<f32>, 5>(
        vec2<f32>(0.0, 0.0),
        vec2<f32>(0.35, 0.25),
        vec2<f32>(-0.3, 0.35),
        vec2<f32>(-0.25, -0.3),
        vec2<f32>(0.3, -0.35)
    );

    let nCenters = i32(pulseCount);
    for (var i = 0; i < 5; i = i + 1) {
        if (i >= nCenters) { break; }
        let fi = f32(i);
        let offset = vec2<f32>(
            sin(time * 0.1 + fi * 2.0) * 0.1,
            cos(time * 0.13 + fi * 1.5) * 0.1
        );
        let center = baseCenters[i] + offset;
        let pulse = rdPulse(p, center, time + fi, speed, pulseWidth * 0.25);
        pulseField += pulse * (1.0 + bass * 0.5);
    }

    // Mouse pulse when active
    let mousePulse = rdPulse(p, mouse, time, speed * 1.5, pulseWidth * 0.2) * mouseDown;
    pulseField += mousePulse * 2.0;

    // Vein network driven by noise
    let vein = abs(substrate - 0.5) * 2.0;
    let veinMask = smoothstep(0.55, 0.75, vein);
    let veinGlow = glow(vein, 0.15, 0.5 + mids * 0.5);

    // Color palette: bioelectric greens / cyans / magentas
    let bioPhase = hueShift + time * 0.05 + substrate * 0.3;
    let bioColor = palette(
        bioPhase,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.25, 0.55, 0.85)
    );
    let pulseColor = palette(
        bioPhase + 0.4 + bass * 0.1,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 0.7, 0.4),
        vec3<f32>(0.1, 0.6, 0.9)
    );

    // Combine
    var col = vec3<f32>(0.01, 0.02, 0.03);
    col += bioColor * substrate * 0.3;
    col += pulseColor * pulseField;
    col += bioColor * veinGlow * veinMask;

    // Sparkle along high-energy ridges
    let sparkle = step(1.0 - treble * 0.4, hash12(floor(p * 40.0) + vec2<f32>(time * 2.0, 0.0)));
    col += vec3<f32>(0.8, 0.95, 1.0) * sparkle * pulseField * 0.5;

    // Vignette
    let v = 1.0 - length(uv - 0.5) * 0.35;
    col *= clamp(v, 0.0, 1.0);

    // Output as generative background (alpha = 1.0)
    let finalColor = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, 1.0));
}
```
