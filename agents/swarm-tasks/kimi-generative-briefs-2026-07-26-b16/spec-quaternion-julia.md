# Swarm Brief: spec-quaternion-julia

**Role:** Optimizer
**Name:** Quaternion Julia
**Category:** generative
**Description:** 4D quaternion Julia set raymarched in real-time. The 4th dimension animates over time creating organic morphing fractal forms with orbit-trap coloring and physically-based lighting.
**Current lines:** 195
**Target lines:** 245–285 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This quaternion Julia set has a mislabeled slider and a spec-violating alpha - make both honest without touching the sacred math:
- MAKE 'DETAIL LEVEL' REAL (priority 1): zoom_params.w currently only divides the hue - wire it to the DE iteration count (`let iters = 8 + i32(u.zoom_params.w * 8.0)`) so the slider truly controls fractal detail. Keep the hue divisor role as a secondary effect if you like, but detail must be primary.
- Clamp the background alpha: background pixels store `alpha = orbitTrap / 10.0` with orbitTrap initialized at 1000 - alpha up to ~100 in an rgba32float target is a contract violation. Clamp alpha to 1.0. Also guard the DE `log(r)` against r ~ 0 on the first iteration (minor -inf risk).
- Audio + trap palette: bass (`plasmaBuffer[0].x`) multiplies the morph speed, mids (`plasmaBuffer[0].y`) offsets the 4D constant c.w for audio drift; add an IQ cosine palette keyed on the minimum orbit-trap distance over the whole march (classic Julia glow bands).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve `quaternionMul` component order, the DE escape radius (256.0), and the `0.5 * r * log(r) / dr` distance estimator VERBATIM - fractal correctness depends on exact quaternion algebra. The mouse-gated orbit (zoom_config.w) semantics are correct - do not change them.

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
  "id": "spec-quaternion-julia",
  "name": "Quaternion Julia",
  "url": "shaders/spec-quaternion-julia.wgsl",
  "description": "4D quaternion Julia set raymarched in real-time. The 4th dimension animates over time creating organic morphing fractal forms with orbit-trap coloring and physically-based lighting.",
  "tags": [
    "quaternion",
    "julia",
    "fractal",
    "4D",
    "raymarching",
    "morphing"
  ],
  "features": [
    "quaternion",
    "4D",
    "raymarched",
    "mouse-driven",
    "HDR"
  ],
  "params": [
    {
      "id": "zoom",
      "name": "Fractal Zoom",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "morph_speed",
      "name": "Morph Speed",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "color_cycles",
      "name": "Color Cycles",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "detail",
      "name": "Detail Level",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.9,
  "updatedParams": [
    {
      "index": 0,
      "name": "Fractal Zoom",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Morph Speed",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Color Cycles",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Detail Level",
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
//  spec-quaternion-julia
//  Category: generative
//  Features: quaternion, 4D, raymarching, fractal
//  Complexity: Very High
//  Chunks From: chunk-library (hash22)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  4D Quaternion Julia Set Raymarched
//  Raymarches a 4D quaternion Julia set projected into 3D and then
//  to screen. The 4th dimension animates over time creating organic
//  morphing fractal forms.
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn quaternionMul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(
        a.x*b.x - a.y*b.y - a.z*b.z - a.w*b.w,
        a.x*b.y + a.y*b.x + a.z*b.w - a.w*b.z,
        a.x*b.z - a.y*b.w + a.z*b.x + a.w*b.y,
        a.x*b.w + a.y*b.z - a.z*b.y + a.w*b.x
    );
}

fn quaternionJuliaDE(p: vec3<f32>, c: vec4<f32>) -> f32 {
    var q = vec4<f32>(p, 0.0);
    var dq = vec4<f32>(1.0, 0.0, 0.0, 0.0);

    for (var i: i32 = 0; i < 12; i = i + 1) {
        dq = 2.0 * quaternionMul(q, dq);
        q = quaternionMul(q, q) + c;
        if (dot(q, q) > 256.0) { break; }
    }

    let r = length(q);
    let dr = length(dq);
    return 0.5 * r * log(r) / max(dr, 0.001);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let zoom = mix(1.5, 4.0, u.zoom_params.x);
    let morphSpeed = mix(0.1, 1.0, u.zoom_params.y);
    let colorCycles = mix(0.5, 3.0, u.zoom_params.z);
    let detail = mix(6.0, 12.0, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -2.5);
    var rd = normalize(vec3<f32>((uv - 0.5) * 2.0, 1.0));

    // Mouse orbit
    if (isMouseDown) {
        let rotY = (mousePos.x - 0.5) * 3.14;
        let rotX = (mousePos.y - 0.5) * 1.57;
        let cy = cos(rotY);
        let sy = sin(rotY);
        let cx = cos(rotX);
        let sx = sin(rotX);
        ro = vec3<f32>(
            ro.x * cy + ro.z * sy,
            ro.y,
            -ro.x * sy + ro.z * cy
        );
        rd = vec3<f32>(
            rd.x * cy + rd.z * sy,
            rd.y,
            -rd.x * sy + rd.z * cy
        );
        rd = vec3<f32>(
            rd.x,
            rd.y * cx - rd.z * sx,
            rd.y * sx + rd.z * cx
        );
    } else {
        // Auto rotation
        let autoRot = time * 0.1;
        let ca = cos(autoRot);
        let sa = sin(autoRot);
        ro = vec3<f32>(ro.x * ca + ro.z * sa, ro.y, -ro.x * sa + ro.z * ca);
        rd = vec3<f32>(rd.x * ca + rd.z * sa, rd.y, -rd.x * sa + rd.z * ca);
    }

    // Animate 4D Julia constant
    let t = time * morphSpeed;
    let c = vec4<f32>(
        -0.2 + 0.1 * sin(t * 0.7),
        0.6 + 0.15 * cos(t * 0.5),
        0.1 * sin(t * 0.3),
        0.2 * cos(t * 0.4)
    );

    // Raymarch
    var t_dist = 0.0;
    var hit = false;
    var orbitTrap = 1000.0;
    var steps = 0;

    for (var i: i32 = 0; i < 64; i = i + 1) {
        let p = ro + rd * t_dist;
        let d = quaternionJuliaDE(p * zoom, c) / zoom;
        orbitTrap = min(orbitTrap, d);
        if (d < 0.001) {
            hit = true;
            steps = i;
            break;
        }
        if (t_dist > 10.0) { break; }
        t_dist = t_dist + d;
    }

    var col = vec3<f32>(0.0);
    var alpha = 0.0;

    if (hit) {
        // Normal via central differences
        let p = ro + rd * t_dist;
        let e = vec2<f32>(0.001, 0.0);
        let n = normalize(vec3<f32>(
            quaternionJuliaDE((p + e.xyy) * zoom, c) - quaternionJuliaDE((p - e.xyy) * zoom, c),
            quaternionJuliaDE((p + e.yxy) * zoom, c) - quaternionJuliaDE((p - e.yxy) * zoom, c),
            quaternionJuliaDE((p + e.yyx) * zoom, c) - quaternionJuliaDE((p - e.yyx) * zoom, c)
        ));

        // Lighting
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.3));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0);
        let ao = 1.0 - f32(steps) / 64.0;

        // Color from orbit trap and iteration count
        let hue = f32(steps) / detail + time * 0.05 * colorCycles;
        let baseColor = vec3<f32>(
            0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
        );

        col = baseColor * (diff * 0.7 + 0.3) * ao + vec3<f32>(spec * 0.5);
        alpha = 1.0;
    } else {
        // Background: sample input image distorted
        let bgUV = uv + vec2<f32>(sin(time * 0.1 + uv.y * 3.0), cos(time * 0.1 + uv.x * 3.0)) * 0.02;
        col = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb * 0.3;
        alpha = orbitTrap / 10.0; // Store orbit trap in alpha
    }

    let display = toneMapACES(col);
    textureStore(writeTexture, gid.xy, vec4<f32>(display, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(col, alpha));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
```
