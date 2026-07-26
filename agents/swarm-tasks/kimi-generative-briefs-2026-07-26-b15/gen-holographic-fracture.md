# Swarm Brief: gen-holographic-fracture

**Role:** Interactivist
**Name:** Holographic Fracture
**Category:** generative
**Description:** Iridescent cracked planes with SDF fracture lines and thin-film holographic shards. Audio drives crack glow, and mouse interaction spawns new radial cracks.
**Current lines:** 183
**Target lines:** 233–273 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This shader has the mouse-coordinate bug class we fixed in Batches 13/14 - fix it first, then make the cracks answer to touch:
- FIX THE MOUSE BUG (priority 1): the shader reads mouse position from `u.zoom_config.xy`, but x is TIME - the crack origin drifts with time. Engine convention is `u.zoom_config.yz` = mouse position, `.w` = mouse-down (verified in src/renderer/UniformBuffer.ts). Change ONLY the `.xy` -> `.yz` swizzle - do not restructure the crack-network loop. Also fix the stale header comment documenting the wrong convention.
- Honest depth: the JSON claims `supportsDepth: true` but the WGSL writes flat 0.0 to writeDepthTexture - write a real depth derived from crack distance/edge field so the depth feature is earned.
- Click crack fronts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) spawning transient crack fronts that expand from each click point and fade with ripple age; spring-damper the mouse crack origin (extraBuffer[133..134]) so it eases rather than snaps. Add per-bin plasmaBuffer[1..k] phase shifts to the thin-film iridescence so each crack index shimmers to its own band.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the `hash22`/`valueNoise`/`fbm2`/`glow` chunk-library function bodies VERBATIM (shared-pattern chunks). extraBuffer persistent state in [133..255] ONLY. The hard clamp(col,0,1) may be upgraded to hue-preserve-clamp + ACES, but keep the final output in 0..1.

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
  "id": "gen-holographic-fracture",
  "name": "Holographic Fracture",
  "category": "generative",
  "url": "shaders/gen-holographic-fracture.wgsl",
  "description": "Iridescent cracked planes with SDF fracture lines and thin-film holographic shards. Audio drives crack glow, and mouse interaction spawns new radial cracks.",
  "features": [
    "generative",
    "sdf",
    "iridescence",
    "fracture-lines",
    "glow",
    "audio-reactive",
    "mouse-driven",
    "depth-aware"
  ],
  "tags": [
    "procedural",
    "generative",
    "fracture",
    "cracks",
    "holographic",
    "iridescent",
    "crystal",
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
      "id": "fractureCount",
      "name": "Fracture Count",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "iridescence",
      "name": "Iridescence",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "crackWidth",
      "name": "Crack Width",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "pulseSpeed",
      "name": "Pulse Speed",
      "default": 0.35,
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
      "name": "Fracture Count",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Iridescence",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Crack Width",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Pulse Speed",
      "default": 0.35,
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
//  Holographic Fracture - Iridescent cracked SDF planes
//  Category: generative
//  Features: generative, sdf, iridescence, fracture-lines, glow,
//            audio-reactive, mouse-crack, depth-aware
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
  zoom_params: vec4<f32>,  // x=FractureCount, y=Iridescence, z=CrackWidth, w=PulseSpeed
  ripples: array<vec4<f32>, 50>,
};

// ── Chunk: hash22 (from gen_grid.wgsl / chunk-library) ────────────
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ── Chunk: valueNoise (from gen_grid.wgsl) ────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uS = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash22(i + vec2<f32>(0.0, 0.0)).x;
    let b = hash22(i + vec2<f32>(1.0, 0.0)).x;
    let c = hash22(i + vec2<f32>(0.0, 1.0)).x;
    let d = hash22(i + vec2<f32>(1.0, 1.0)).x;
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

// ── Chunk: rot2 (from chunk-library) ──────────────────────────────
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ── Chunk: glow (from anamorphic-flare.wgsl) ──────────────────────
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius + 1e-6)) * intensity;
}

// Signed distance to a line segment
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

// Iridescent thin-film color
fn iridescence(theta: f32, shift: f32) -> vec3<f32> {
    let t = theta * 4.0 + shift;
    return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189));
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
    let fractureCount = mix(3.0, 12.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let iridescenceAmt = clamp(u.zoom_params.y, 0.0, 1.0);
    let crackWidth = mix(0.002, 0.02, clamp(u.zoom_params.z, 0.0, 1.0));
    let pulseSpeed = mix(0.2, 1.5, clamp(u.zoom_params.w, 0.0, 1.0));

    // Mouse crack origin
    let mouse = (u.zoom_config.xy - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDown = step(0.5, u.zoom_config.w);

    // Background substrate with subtle FBM
    let substrate = fbm2(p * 2.5 + time * 0.05, 4);

    // Fracture network: radial cracks from center + mouse point
    var minDist = 1000.0;
    var crackIntensity = 0.0;

    let centers = array<vec2<f32>, 2>(vec2<f32>(0.0), mouse);
    for (var c = 0; c < 2; c = c + 1) {
        if (c == 1 && mouseDown < 0.5) { continue; }
        let center = centers[c];
        let toP = p - center;
        let polar = vec2<f32>(length(toP), atan2(toP.y, toP.x));

        let nCracks = i32(fractureCount) + select(0, 3, c == 1);
        for (var i = 0; i < 16; i = i + 1) {
            if (i >= nCracks) { break; }
            let fi = f32(i);
            let baseAngle = fi / fractureCount * 6.28318;
            let angle = baseAngle + polar.y;
            let wave = sin(angle * 3.0 + polar.x * 12.0 + time * pulseSpeed) * 0.03;
            let r = polar.x + wave + substrate * 0.05;

            let a = center + vec2<f32>(cos(baseAngle), sin(baseAngle)) * 0.02;
            let b = center + vec2<f32>(cos(baseAngle + wave), sin(baseAngle + wave)) * (1.2 + bass * 0.3);
            let d = sdSegment(p, a, b);
            let w = crackWidth * (1.0 + mids * 0.5);
            let line = 1.0 - smoothstep(0.0, w, d);
            crackIntensity = max(crackIntensity, line);
            minDist = min(minDist, d);
        }
    }

    // Holographic shard coloring based on angle and distance
    let angleToCenter = atan2(p.y, p.x);
    let distToCenter = length(p);
    let iridShift = time * 0.1 + distToCenter * 3.0 + bass * 0.2;
    let shardColor = iridescence(angleToCenter + substrate, iridShift);

    // Shard boundaries via Voronoi-like cell edges
    let cellScale = fractureCount * 0.6;
    let cellId = floor(p * cellScale);
    let cellFract = fract(p * cellScale) - 0.5;
    let rnd = hash22(cellId);
    let cellCenter = (rnd - 0.5) * 0.8;
    let edgeDist = abs(length(cellFract - cellCenter) - 0.35);
    let edgeGlow = glow(edgeDist, crackWidth * 3.0, 0.5) * (0.3 + treble * 0.5);

    // Pulse along cracks
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed * 3.0 + distToCenter * 10.0);
    let crackGlow = glow(minDist, crackWidth * 4.0, 1.0 + pulse * 0.7) * (0.4 + bass * 0.6);

    // Compose
    var col = vec3<f32>(0.02, 0.03, 0.05);
    col += shardColor * substrate * 0.25;
    col += shardColor * iridescenceAmt * 0.2;
    col += vec3<f32>(0.7, 0.9, 1.0) * crackGlow;
    col += shardColor * edgeGlow * iridescenceAmt;
    col += vec3<f32>(1.0, 0.9, 0.7) * crackIntensity * (0.6 + treble);

    // Vignette
    let v = 1.0 - length(uv - 0.5) * 0.4;
    col *= clamp(v, 0.0, 1.0);

    // Output as generative background (alpha = 1.0)
    let finalColor = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, 1.0));
}
```
