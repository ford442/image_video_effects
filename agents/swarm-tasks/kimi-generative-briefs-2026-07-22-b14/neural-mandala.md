# Swarm Brief: neural-mandala

**Role:** Interactivist
**Name:** Neural Mandala
**Category:** generative
**Description:** Concentric geometric rings with interconnected node networks that pulse and evolve. Audio drives ring expansion and node brightness.
**Current lines:** 177
**Target lines:** 227–267 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This kaleidoscopic mandala has ZERO mouse interaction - give it a sense of touch, then deepen the symmetry:
- Mouse re-centering + shock rings: mouse-down offsets the mandala center toward u.zoom_config.yz with a smooth spring, and clicks spawn expanding ring shocks via the ripples[] uniform (guard with min(u.config.y, 50u)) that momentarily perturb the ring radii as they pass.
- Per-ring audio: ring index ri reads plasmaBuffer[ri % 8 + 1] so inner rings pulse to bass bins and outer rings shimmer to treble bins, instead of the whole mandala following global bands.
- Sub-symmetry fold: add a second kaleidoscope fold pass at half the segment count, mixed in by the Complexity slider, for snowflake-like internal mirroring.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the existing dataTextureC color feedback (decay 0.92, mix ~0.05) is stable - if you increase any feedback/decay term, clamp accumulated color pre-tint at ~1.2 (luma-echo-warp lesson). Complexity intentionally drives both segment count and node count - keep that coherent double-duty.

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
  "id": "neural-mandala",
  "name": "Neural Mandala",
  "category": "generative",
  "url": "shaders/neural-mandala.wgsl",
  "description": "Concentric geometric rings with interconnected node networks that pulse and evolve. Audio drives ring expansion and node brightness.",
  "features": [
    "audio-reactive",
    "generative",
    "geometric-recursion",
    "upgraded-rgba",
    "pulsing-nodes"
  ],
  "params": [
    {
      "id": "rings",
      "name": "Ring Count",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "complexity",
      "name": "Node Complexity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "pulse",
      "name": "Pulse Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "connections",
      "name": "Connection Density",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "mapping": "zoom_params.w"
    }
  ],
  "tags": [
    "generative",
    "mandala",
    "geometric",
    "network",
    "nodes",
    "audio-reactive",
    "pulsing",
    "abstract"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Ring Count",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Node Complexity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Pulse Speed",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Connection Density",
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
//  Neural Mandala — Algorithmist Upgrade
//  Polar kaleidoscope symmetry + Warped FBM distortion + Clifford nodes
//  Quasi-random hue distribution with golden-ratio stepping
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

const PI     = 3.14159265358979323846;
const TAU    = 6.28318530717958647692;
const PHI    = 1.61803398874989484820;
const INV_PI = 0.31830988618379067154;

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var a = 0.5; var s = 0.0; var q = p;
  for (var i = 0; i < 5; i = i + 1) {
    s = s + a * valueNoise(q);
    q = q * 2.02; a = a * 0.5;
  }
  return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)),
                    fbm(p + vec2<f32>(5.2, 1.3)));
  let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2)),
                    fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8)));
  return fbm(p + 4.0 * r);
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
  return vec2<f32>(sin(a * p.y) + c * cos(a * p.x),
                   sin(b * p.x) + d * cos(b * p.y));
}

fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
  let r = length(uv);
  var a = atan2(uv.y, uv.x);
  let seg = TAU / max(segs, 1.0);
  a = abs(((a % seg) + seg) % seg - seg * 0.5);
  return vec2<f32>(cos(a), sin(a)) * r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let ringCount = 4 + i32(u.zoom_params.x * 8.0);
  let complexity = u.zoom_params.y;
  let pulseSpeed = u.zoom_params.z * 3.0;
  let connectionDensity = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let segs = mix(3.0, 12.0, complexity);
  let fp = kaleido(p, segs);
  let seg = TAU / segs;

  var color = vec3<f32>(0.02, 0.01, 0.04);
  var glow = 0.0;

  for (var ri = 0; ri < ringCount; ri = ri + 1) {
    let r = f32(ri);
    // Domain-warped FBM for organic ring radius distortion
    let warp = warpedFBM(p * 4.0 + r, time * 0.08) * 0.015;
    let radius = 0.05 + r * 0.06 + warp;
    let ringPulse = sin(time * pulseSpeed + r * 1.3) * 0.5 + 0.5;
    let ringWidth = 0.003 * (1.0 + ringPulse * bass);

    let distR = length(fp);
    let ringMask = smoothstep(radius + ringWidth, radius, distR) *
                   smoothstep(radius - ringWidth, radius, distR);

    let nodeCount = 4 + i32(r * complexity * 8.0);
    for (var ni = 0; ni < nodeCount; ni = ni + 1) {
      let nodeAngle = f32(ni) / f32(nodeCount) * seg * 0.5 +
                      time * 0.1 * (0.5 + r * 0.1);
      let nodePos = vec2<f32>(cos(nodeAngle), sin(nodeAngle)) * radius;
      // Clifford attractor perturbation for living node drift
      let perturb = clifford(nodePos * 3.0 + time * 0.05, 1.5, 2.3, 1.1, 1.7) *
                    0.01 * connectionDensity;
      let nodePosPerturbed = nodePos + perturb;
      let nodeDist = length(fp - nodePosPerturbed);
      let nodeSize = 0.008 * (1.0 + bass * 0.5) * (1.0 + ringPulse);
      let nodeGlow = smoothstep(nodeSize * 2.0, 0.0, nodeDist);

      if (ri < ringCount - 1) {
        let nextRadius = radius + 0.06;
        let nextNodeCount = nodeCount + 2;
        let nextAngle = f32(ni) / f32(nextNodeCount) * seg * 0.5 +
                        time * 0.08 * (0.5 + (r + 1.0) * 0.1);
        let nextPos = vec2<f32>(cos(nextAngle), sin(nextAngle)) * nextRadius;
        let nextPerturb = clifford(nextPos * 3.0 + time * 0.05, 1.5, 2.3, 1.1, 1.7) *
                          0.01 * connectionDensity;
        let nextPosPerturbed = nextPos + nextPerturb;
        let lineDir = nextPosPerturbed - nodePosPerturbed;
        let lineLen = length(lineDir);
        let lineDirNorm = lineDir / max(lineLen, 0.0001);
        let toPixel = fp - nodePosPerturbed;
        let proj = clamp(dot(toPixel, lineDirNorm), 0.0, lineLen);
        let closest = nodePosPerturbed + lineDirNorm * proj;
        let lineDist = length(fp - closest);
        let lineGlow = smoothstep(0.003 * (1.0 + connectionDensity), 0.0, lineDist);
        color = color + vec3<f32>(0.3, 0.6, 1.0) * lineGlow * connectionDensity * mids;
        glow = glow + lineGlow * connectionDensity;
      }

      // Golden-ratio hue stepping for quasi-random color distribution
      let hue = fract(r * 0.08 + time * 0.02 + bass * 0.05 + f32(ni) * PHI * INV_PI);
      let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
      let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
      let nodeColor = clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));

      color = color + nodeColor * nodeGlow * (0.8 + treble * 0.4);
      glow = glow + nodeGlow;
    }

    color = color + vec3<f32>(0.2, 0.5, 0.9) * ringMask * (0.3 + mids * 0.3);
    glow = glow + ringMask * 0.3;
  }

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, 0.05 + bass * 0.01);

  let caStr = 0.003 * (1.0 + bass) + glow * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  let alpha = clamp(glow * 0.6 + 0.15 + bass * 0.05, 0.0, 1.0);
  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(glow * 0.3, 0.0, 0.0, 0.0));
}
```
