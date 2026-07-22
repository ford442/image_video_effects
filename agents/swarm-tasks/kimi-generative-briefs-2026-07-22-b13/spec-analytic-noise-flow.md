# Swarm Brief: spec-analytic-noise-flow

**Role:** Optimizer
**Name:** Analytic Noise Flow
**Category:** generative
**Description:** Perlin noise with analytic derivatives for ultra-smooth flow fields. Gradient computed alongside noise value in single evaluation, eliminating finite-difference jitter for perfectly parallel streamlines.
**Current lines:** 175
**Target lines:** 225–265 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This shader's analytic-derivative Perlin noise is its raison d'etre - exploit the free gradient, don't touch the math:
- Iso-contour ridges: use the already-computed analytic gradient magnitude (free byproduct) to draw flow iso-contour lines (fract(noise1.x*N) ridge mask) that sharpen with treble - contour density tied to the Detail-adjacent slider mapping.
- Bass surge: multiply advection strength by a bass envelope (plasmaBuffer[0].x) so kicks visibly surge the flow field.
- Temporally coherent streamlines: dataTextureA already stores velocity in .rg - read prev.rg as velocity and apply an exponential smoothing filter frame-to-frame so streamlines stop shimmering; keep the existing light color feedback (mix ~0.03) intact.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve noiseWithDerivative EXACTLY (k0/k1/k2/k4 quintic coefficient form) - do not 'simplify' it. Note dataTextureA stores velocity vectors, not color; the existing prev.rgb color read at 3% mix is harmless - keep it, and add the velocity read as a separate path.

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
  "id": "spec-analytic-noise-flow",
  "name": "Analytic Noise Flow",
  "url": "shaders/spec-analytic-noise-flow.wgsl",
  "description": "Perlin noise with analytic derivatives for ultra-smooth flow fields. Gradient computed alongside noise value in single evaluation, eliminating finite-difference jitter for perfectly parallel streamlines.",
  "tags": [
    "analytic-derivatives",
    "flow-field",
    "noise",
    "perlin",
    "streamlines",
    "curl"
  ],
  "features": [
    "analytic-derivatives",
    "flow-field",
    "noise",
    "mouse-driven",
    "temporal",
    "chromatic",
    "depth-aware"
  ],
  "params": [
    {
      "id": "flow_scale",
      "name": "Flow Scale",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "flow_speed",
      "name": "Flow Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "advection",
      "name": "Advection",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "curl",
      "name": "Curl Amount",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.6,
  "updatedParams": [
    {
      "index": 0,
      "name": "Flow Scale",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Flow Speed",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Advection",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Curl Amount",
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
//  spec-analytic-noise-flow
//  Category: generative
//  Features: analytic-derivatives, flow-field, noise, temporal, chromatic, depth-aware
//  Complexity: High
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  Upgraded: 2026-05-31
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Noise with Analytic Derivatives for Flow Fields
//  Implements Perlin noise with analytic derivatives — gradient is
//  computed alongside noise value in a single evaluation. Creates
//  perfectly smooth flow fields without finite-difference jitter.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash2(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash12(p), hash12(p + vec2<f32>(37.0, 17.0)));
}

// Analytic derivative noise: returns x = value, yz = gradient
fn noiseWithDerivative(p: vec2<f32>) -> vec3<f32> {
    let i = floor(p);
    let f = fract(p);

    // Quintic interpolation with analytic derivative
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    // Hash corners
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));

    // Value interpolation
    let k0 = a;
    let k1 = b - a;
    let k2 = c - a;
    let k4 = a - b - c + d;

    let value = k0 + k1 * u.x + k2 * u.y + k4 * u.x * u.y;
    let derivative = vec2<f32>(
        (k1 + k4 * u.y) * du.x,
        (k2 + k4 * u.x) * du.y
    );

    return vec3<f32>(value, derivative);
}

// Multi-octave analytic noise
fn fbmAnalytic(p: vec2<f32>, octaves: i32) -> vec3<f32> {
    var value = 0.0;
    var grad = vec2<f32>(0.0);
    var amplitude = 0.5;
    var frequency = 1.0;

    for (var i: i32 = 0; i < octaves; i = i + 1) {
        let n = noiseWithDerivative(p * frequency);
        value += amplitude * n.x;
        grad += amplitude * frequency * n.yz;
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    return vec3<f32>(value, grad);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let flowScale = mix(1.0, 5.0, u.zoom_params.x);
    let flowSpeed = mix(0.2, 2.0, u.zoom_params.y);
    let advectionStr = mix(0.0, 0.3, u.zoom_params.z);
    let curlAmount = mix(0.0, 1.0, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Sample base image for advection source
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Analytic noise flow field
    let p = uv * flowScale + time * flowSpeed;
    let noise1 = fbmAnalytic(p, 4);
    let noise2 = fbmAnalytic(p + vec2<f32>(5.2, 1.3), 4);

    // Build velocity field from analytic gradients
    var velocity = vec2<f32>(noise1.y, noise2.y);

    // Add curl (perpendicular to gradient)
    let curl = vec2<f32>(-noise1.z, noise1.y) * curlAmount;
    velocity += curl;

    // Mouse vortex
    if (isMouseDown) {
        let toMouse = mousePos - uv;
        let dist = length(toMouse);
        let vortexStrength = exp(-dist * dist * 500.0);
        let perp = vec2<f32>(-toMouse.y, toMouse.x) / (dist + 0.001);
        velocity += perp * vortexStrength * 0.5;
    }

    // Advect sample position along flow
    let advectedUV = uv + velocity * advectionStr;
    let warpedColor = textureSampleLevel(readTexture, u_sampler, fract(advectedUV), 0.0).rgb;

    // Flow visualization: color by direction
    let flowAngle = atan2(velocity.y, velocity.x) / 6.28318 + 0.5;
    let flowColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * flowAngle),
        0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.67))
    );

    // Blend warped image with flow visualization
    let blendFactor = 0.6;
    var outColor = mix(warpedColor, flowColor * 0.5 + warpedColor * 0.5, blendFactor);

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Add streamline highlight
    let streamline = smoothstep(0.0, 0.1, abs(noise1.x - 0.5));
    outColor += vec3<f32>(0.1, 0.15, 0.2) * streamline * (1.0 - curlAmount);

    // ─── Chromatic dispersion ───
    let chrStrength = 0.004 + bass * 0.008;
    let chrR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chrStrength * (1.0 + mids * 0.5), 0.0), 0.0).r;
    let chrG = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, chrStrength * (1.0 + treble * 0.3)), 0.0).g;
    let chrB = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-chrStrength * 0.7 * (1.0 + bass * 0.4), chrStrength * 0.3), 0.0).b;
    let chrColor = vec3<f32>(chrR, chrG, chrB);
    outColor = mix(outColor, chrColor, 0.2 + bass * 0.15);

    // ─── Temporal feedback ───
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    outColor = mix(outColor, prev.rgb * 0.9, 0.03 + bass * 0.01);

    let flowDepth = length(velocity) * 0.5 + 0.25;
    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, length(velocity)));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(flowDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(velocity, noise1.x, 1.0));
}
```
