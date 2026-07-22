# Swarm Brief: emergent-calligraphic-weave

**Role:** Visualist
**Name:** Emergent Calligraphic Weave
**Category:** generative
**Description:** Sumi-e ink wash simulation with pressure-sensitive Bézier brush strokes, ink viscosity flow, paper absorption capillary action, and dry-brush texture. Audio drives brush speed and splatter; mouse acts as the brush with pressure from click duration. Depth scales paper grain.
**Current lines:** 160
**Target lines:** 210–250 (expand by +50 to +90)

## Role Instructions

You are the Visualist. Focus on the sumi-e brush feel: ink, stroke texture, and edge chromatics:
- Replace the generic applyGenerativePrimaryControls boilerplate mapping with real brush constants: stroke width, ink viscosity, dry-brush threshold, and chaos amplitude must each be visibly driven by one slider (ids/defaults unchanged).
- Curl-noise stroke direction field: advect the stroke direction with a low-frequency divergence-free curl field so strokes flow like brushed calligraphy instead of lying on a static field.
- Dry-brush edge sparkle: treble-driven (plasmaBuffer[0].z) ink-grain texture on stroke edges, masked by the dry-brush threshold so fast strokes sizzle.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional — only declare it if the shader already uses it.

## JSON Parameters / Controls

```json
{
  "id": "emergent-calligraphic-weave",
  "name": "Emergent Calligraphic Weave",
  "url": "shaders/emergent-calligraphic-weave.wgsl",
  "category": "generative",
  "description": "Sumi-e ink wash simulation with pressure-sensitive B\u00e9zier brush strokes, ink viscosity flow, paper absorption capillary action, and dry-brush texture. Audio drives brush speed and splatter; mouse acts as the brush with pressure from click duration. Depth scales paper grain.",
  "features": [
    "stroke-based",
    "brush-dynamics",
    "ink-viscosity",
    "paper-absorption",
    "bezier-strokes",
    "sumi-e",
    "dry-brush",
    "chromatic-edge",
    "audio-field",
    "mouse-influence",
    "temporal",
    "upgraded-rgba"
  ],
  "tags": [
    "calligraphic",
    "emergent",
    "symbolic",
    "organic",
    "audio-reactive",
    "abstract",
    "sumi-e",
    "ink",
    "brush-dynamics",
    "dry-brush",
    "paper-texture",
    "chromatic-edge"
  ],
  "params": [
    {
      "id": "fieldComplexity",
      "name": "Field Complexity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "How intricate the underlying orientation field is"
    },
    {
      "id": "strokePersistence",
      "name": "Stroke Persistence",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "How long strokes remain visible before fading"
    },
    {
      "id": "coherence",
      "name": "Pattern Coherence",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Encourages formation of larger connected structures"
    },
    {
      "id": "chaos",
      "name": "Field Chaos",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Adds turbulence to the orientation field"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Field Complexity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Stroke Persistence",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Pattern Coherence",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Field Chaos",
      "default": 0.3,
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
//  Emergent Calligraphic Weave v2
//  Category: generative
//  Features: stroke-based, brush-dynamics, ink-viscosity, paper-absorption,
//            bezier-strokes, sumi-e, dry-brush, chromatic-edge, upgraded-rgba, aces-tone-map
//  Complexity: Very High
//  Created: 2026-05-31
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.5;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Brush dynamics parameters
    let pressure = mouseDown * (0.6 + hash12(mouse * 10.0 + time) * 0.4);
    let brushSpeed = 0.5 + bass * 2.0;
    let inkConcentration = 0.4 + mids * 0.6;
    let viscosity = 0.85 + mids * 0.15;

    let strokeLength = 0.008 + brushSpeed * 0.012;
    let chaos = 0.2 + treble * 0.8;

    // Orientation field with mouse influence
    let toMouse = normalize(uv - mouse + vec2<f32>(0.0001));
    let mouseAngle = atan2(toMouse.y, toMouse.x);
    let mouseInfluence = smoothstep(0.3, 0.02, length(uv - mouse)) * pressure * 2.0;

    let n1 = hash12(uv * 1.7 + time * 0.1) - 0.5;
    let n2 = hash12(uv * 4.3 - time * 0.17) - 0.5;
    let baseAngle = (n1 * 1.2 + n2 * 0.6) * (1.0 + chaos * 0.6);
    let angle = mix(baseAngle, mouseAngle, mouseInfluence);

    // Bézier stroke sampling modulated by velocity
    let dir = vec2<f32>(cos(angle), sin(angle));
    let perp = vec2<f32>(-dir.y, dir.x);
    let curvature = sin(angle * 3.0 + time * 2.0) * 0.015 * brushSpeed;
    let sampleUV = clamp(uv - dir * strokeLength + perp * curvature, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampled = textureSampleLevel(dataTextureC, u_sampler, sampleUV, 0.0);

    // Paper grain and absorption scale from depth
    let paperScale = mix(30.0, 100.0, depth);
    let grain = hash12(uv * paperScale);
    let paperAbsorb = 0.5 + depth * 0.5;
    let dryBrush = smoothstep(0.35, 0.55, grain);

    // Paper fiber visibility
    let fiber = sin(uv.x * paperScale * 2.3 + uv.y * paperScale * 1.7) * 0.5 + 0.5;
    let fiberMask = smoothstep(0.4, 0.6, fiber) * dryBrush * 0.2;

    // Ink viscosity flow and capillary bleed
    let decay = viscosity - bass * 0.02;
    let bleed = (sampled.r - prev.r) * 0.08 * paperAbsorb;
    var newStroke = sampled.r * decay + 0.035 * inkConcentration + bleed;
    newStroke = newStroke * (0.7 + dryBrush * 0.6);

    // Brush temperature from bass (faster = drier / hotter)
    let brushTemp = 0.5 + bass * 0.5;
    let evaporation = smoothstep(0.3, 0.8, brushTemp);
    newStroke = newStroke * (1.0 - evaporation * 0.08);

    // Treble-driven splatter
    let splatter = step(1.0 - treble * 0.25, hash12(uv * 60.0 + time * 5.0)) * treble * 0.4;
    newStroke = newStroke + splatter;

    // Coherence feedback from orientation alignment
    let coherence = 1.0 - abs(sampled.g - angle) * 0.7;
    newStroke += coherence * 0.03 * (0.5 + mids * 0.4);

    let density = clamp(newStroke, 0.0, 1.2);
    let ink = pow(density, 0.9);

    // Sumi-e ink wash palette
    let inkR = mix(vec3<f32>(0.06, 0.04, 0.03), vec3<f32>(0.9, 0.7, 0.5), ink);
    let inkB = mix(vec3<f32>(0.06, 0.04, 0.03), vec3<f32>(0.5, 0.7, 0.9), ink);
    let col = mix(inkR, inkB, smoothstep(0.3, 0.7, treble));

    // Chromatic edge darkening (yellowing at ink boundaries)
    let neighbor = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + dir * 0.004, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let edge = abs(prev.r - neighbor.r);
    let yellowing = vec3<f32>(0.9, 0.85, 0.5) * smoothstep(0.02, 0.08, edge) * 0.35;

    let hueShift = sin(angle * 2.0) * 0.06;
    var finalCol = col * (1.0 + hueShift) + yellowing;

    // Add paper fiber texture to final color
    finalCol = finalCol + vec3<f32>(0.05, 0.04, 0.03) * fiberMask;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    finalCol = vec3<f32>(finalCol.r + caStr, finalCol.g, finalCol.b - caStr * 0.5);

    // ACES tone map
    finalCol = acesToneMap(finalCol);

    let alpha = clamp(ink * paperAbsorb * depth + splatter * 0.5, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, applyGenerativePrimaryControls(vec4<f32>(finalCol, alpha)));
    textureStore(dataTextureA, gid.xy, vec4<f32>(newStroke, angle, inkConcentration, density));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(density * 0.5, 0.0, 0.0, 0.0));
}
```
