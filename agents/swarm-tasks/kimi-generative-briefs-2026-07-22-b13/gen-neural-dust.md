# Swarm Brief: gen-neural-dust

**Role:** Interactivist
**Name:** Neural Dust
**Category:** generative
**Description:** Drifting luminous particle field driven by domain-warped FBM. Audio reactivity controls density and jitter, while mouse gravity attracts nearby dust motes.
**Current lines:** 171
**Target lines:** 221–261 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. Make the dust field feel alive and aware of the viewer:
- Comet trails: wire the declared-but-unread dataTextureC feedback so motes leave ~0.9-decay streaks (mix color with previous frame); clamp the accumulated trail pre-tint at ~1.2 (luma-echo-warp lesson).
- Per-bin spectrum response: use plasmaBuffer[1+n] bins so different dust grid cells jitter/glow to different frequency bands instead of the whole field following bass+treble globally.
- Depth-aware parallax: offset the dust field sample position by a readDepthTexture sample so motes drift around foreground silhouettes of the input frame.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: mouse coords are u.zoom_config.yz (not .xy) and u.zoom_config.w is MouseDown - follow that convention. The 4 sliders are already shader-specific (density/speed/glow/hue) - keep those mappings and EXTEND them, do not rewire.

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
  "id": "gen-neural-dust",
  "name": "Neural Dust",
  "category": "generative",
  "url": "shaders/gen-neural-dust.wgsl",
  "description": "Drifting luminous particle field driven by domain-warped FBM. Audio reactivity controls density and jitter, while mouse gravity attracts nearby dust motes.",
  "features": [
    "generative",
    "fbm-noise",
    "domain-warping",
    "glow",
    "palette",
    "audio-reactive",
    "mouse-driven",
    "depth-aware"
  ],
  "tags": [
    "procedural",
    "generative",
    "particles",
    "dust",
    "neural",
    "noise",
    "glow",
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
      "id": "dustDensity",
      "name": "Dust Density",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "flowSpeed",
      "name": "Flow Speed",
      "default": 0.35,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "glowRadius",
      "name": "Glow Radius",
      "default": 0.5,
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
      "name": "Dust Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Flow Speed",
      "default": 0.35,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Glow Radius",
      "default": 0.5,
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
//  Neural Dust - Drifting luminous particle field via FBM + glow
//  Category: generative
//  Features: generative, fbm-noise, domain-warping, glow, palette,
//            audio-reactive, depth-aware
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
  zoom_params: vec4<f32>,  // x=DustDensity, y=FlowSpeed, z=GlowRadius, w=HueShift
  ripples: array<vec4<f32>, 50>,
};

// ── Chunk: hash12 (from gen_grid.wgsl) ────────────────────────────
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

// ── Chunk: fbm2 (from gen_grid.wgsl / chunk-library) ──────────────
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

// ── Chunk: palette (cosine, from chunk-library) ───────────────────
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ── Chunk: glow (from anamorphic-flare.wgsl) ──────────────────────
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius + 1e-6)) * intensity;
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
    let dustDensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let flowSpeed = mix(0.1, 1.2, clamp(u.zoom_params.y, 0.0, 1.0));
    let glowRadius = mix(0.008, 0.06, clamp(u.zoom_params.z, 0.0, 1.0));
    let hueShift = clamp(u.zoom_params.w, 0.0, 1.0);

    // Mouse influence
    let mouse = (u.zoom_config.xy - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDown = step(0.5, u.zoom_config.w);

    // Domain-warped drifting field
    let t = time * flowSpeed;
    let q = vec2<f32>(
        fbm2(p * (2.0 + dustDensity * 4.0) + vec2<f32>(0.0, t * 0.1), 4),
        fbm2(p * (2.0 + dustDensity * 4.0) + vec2<f32>(5.2, 1.3 + t * 0.1), 4)
    );
    let warped = p + vec2<f32>(
        fbm2(p * 3.0 + 4.0 * q + vec2<f32>(1.7 - t * 0.15, 9.2), 4),
        fbm2(p * 3.0 + 4.0 * q + vec2<f32>(8.3 - t * 0.15, 2.8), 4)
    ) * 0.3;

    // Particle grid layer
    let gridScale = mix(8.0, 24.0, dustDensity);
    let gridPos = warped * gridScale;
    let cellId = floor(gridPos);
    let cellFract = fract(gridPos) - 0.5;

    // Random offset per cell
    let rnd = hash12(cellId + vec2<f32>(time * 0.05, 0.0));
    let offset = (hash12(cellId + vec2<f32>(1.0, 2.0)) - 0.5) * 0.6;
    let drift = vec2<f32>(
        sin(time * flowSpeed * 2.0 + rnd * 6.28318),
        cos(time * flowSpeed * 1.5 + rnd * 6.28318)
    ) * 0.25;
    let particlePos = cellFract - offset + drift;

    // Distance from particle center with audio jitter
    let jitter = 1.0 + (bass + treble) * 0.4;
    let d = length(particlePos) / jitter;

    // Mouse gravity attracts nearby particles
    let toMouse = mouse - p;
    let mouseDist = length(toMouse);
    let mousePull = exp(-mouseDist * 3.0) * mouseDown * 0.15;
    let mouseGlow = glow(mouseDist, 0.4 + mids * 0.3, 0.6 * mouseDown);

    // Layered glow field
    let density = mix(0.3, 1.2, dustDensity);
    let particleGlow = glow(d, glowRadius, density);
    let softField = glow(d, glowRadius * 4.0, density * 0.25);

    // Color palette
    let phase = hueShift + time * 0.04 + rnd * 0.2 + bass * 0.1;
    let dustColor = palette(
        phase,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    let accentColor = palette(
        phase + 0.3,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 0.7, 0.4),
        vec3<f32>(0.15, 0.45, 0.75)
    );

    var col = vec3<f32>(0.02, 0.02, 0.04);
    col += dustColor * particleGlow;
    col += accentColor * softField;
    col += accentColor * mouseGlow;
    col += dustColor * mousePull;

    // Subtle vignette
    let v = 1.0 - length(uv - 0.5) * 0.35;
    col *= clamp(v, 0.0, 1.0);

    // Output as generative background (alpha = 1.0)
    let finalColor = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, 1.0));
}
```
