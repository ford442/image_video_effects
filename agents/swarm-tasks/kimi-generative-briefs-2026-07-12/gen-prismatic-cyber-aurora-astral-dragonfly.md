# Swarm Brief: gen-prismatic-cyber-aurora-astral-dragonfly

**Role:** Algorithmist
**Name:** Prismatic Cyber-Aurora Astral-Dragonfly
**Category:** generative
**Description:** A majestic, hyper-organic biomechanical dragonfly forged from liquid auroral plasma and shattered chromatic crystal.
**Current lines:** 168
**Target lines:** 218–258 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Focus on mathematical/algorithmic depth:
- Replace naive noise with domain-warped FBM, curl noise, or Worley/Voronoi layers.
- Add SDF primitives, orbit traps, strange attractors, or fractal iterations where thematically appropriate.
- Use branchless select()/mix() instead of per-pixel if blocks.
- Preserve the original "soul" and theme of the shader.


## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.

## JSON Parameters / Controls

```json
{
  "id": "gen-prismatic-cyber-aurora-astral-dragonfly",
  "name": "Prismatic Cyber-Aurora Astral-Dragonfly",
  "description": "A majestic, hyper-organic biomechanical dragonfly forged from liquid auroral plasma and shattered chromatic crystal.",
  "category": "generative",
  "url": "shaders/gen-prismatic-cyber-aurora-astral-dragonfly.wgsl",
  "uniforms": [
    {
      "name": "Wingspan",
      "type": "float",
      "min": 0.05,
      "max": 0.5,
      "default": 0.1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "name": "Plasma Intensity",
      "type": "float",
      "min": 0.1,
      "max": 1.0,
      "default": 0.2,
      "step": 0.05,
      "mapping": "zoom_params.y"
    }
  ]
}
```

## Current WGSL Code

```wgsl
// ----------------------------------------------------------------
// Prismatic Cyber-Aurora Astral-Dragonfly
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

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Pseudo-random function
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1313);
    p3 += dot(p3, p3.yzx + 3.333);
    return fract((p3.x + p3.y) * p3.z);
}

// 2D Noise
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)),
                   hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)),
                   hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Fractal Brownian Motion
fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var pt = p;
    for (var i = 0; i < 5; i++) {
        value += amp * noise(pt);
        pt *= 2.0;
        amp *= 0.5;
    }
    return value;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let resolution = vec2<f32>(dims);
    var uv = (vec2<f32>(id.xy) - 0.5 * resolution) / min(resolution.x, resolution.y);

    let time = u.config.x;
    let audio = u.config.y;
    let mouse = (u.zoom_config.yz - 0.5) * 2.0;

    // Sliders
    let wingspan = u.zoom_params.x;      // Default 0.1
    let plasmaIntensity = u.zoom_params.y; // Default 0.2

    // Apply mouse rotation
    uv = rot(mouse.x * 2.0) * uv;

    // Create cosmic background
    let bgDist = length(uv);
    var bgColor = vec3<f32>(0.0);
    let nebula = fbm(uv * 3.0 + time * 0.1);
    bgColor += vec3<f32>(0.1, 0.05, 0.2) * nebula * (1.0 + audio * 2.0);

    // Astral Dragonfly body
    var d = 1000.0;

    // Core body (vertical segment)
    let bodyX = abs(uv.x);
    let bodyY = uv.y;
    let bodyShape = length(vec2<f32>(bodyX * 4.0, max(0.0, abs(bodyY) - 0.2)));
    d = min(d, bodyShape);

    // Four-fold wings
    // Animate wing flapping with high frequency, influenced by audio
    let flapSpeed = time * 20.0 + audio * 50.0;
    let wingAngle1 = sin(flapSpeed) * 0.4 + 0.5;
    let wingAngle2 = sin(flapSpeed + 1.5) * 0.4 + 0.3;

    // Wing 1 (Top)
    var w1Uv = vec2<f32>(abs(uv.x) - 0.05, uv.y - 0.1);
    w1Uv = rot(wingAngle1) * w1Uv;
    // Wing 1 shape: elongated ellipse scaled by wingspan
    let wingScale1 = wingspan * 10.0;
    let w1Shape = length(vec2<f32>(w1Uv.x * 0.5 / wingScale1, w1Uv.y * 3.0)) - 0.1;

    // Wing 2 (Bottom)
    var w2Uv = vec2<f32>(abs(uv.x) - 0.05, uv.y + 0.1);
    w2Uv = rot(wingAngle2 + 0.5) * w2Uv;
    // Wing 2 shape
    let wingScale2 = wingspan * 8.0;
    let w2Shape = length(vec2<f32>(w2Uv.x * 0.5 / wingScale2, w2Uv.y * 3.0)) - 0.08;

    // Only show wings if x > 0 (already mirrored with abs)
    // Actually w1Uv and w2Uv are constructed using abs(uv.x), so we need to ensure they only extend outward
    var wingDist = min(w1Shape, w2Shape);
    // Add fractal patterns to wings
    if (wingDist < 0.1) {
       let wingPattern = fbm(uv * 20.0 - time);
       wingDist += wingPattern * 0.02 * audio;
    }

    d = min(d, wingDist);

    // Colorization based on distance
    var finalColor = bgColor;

    if (d < 0.05) {
        // Biomechanical shell & Prismatic wings
        let baseColor = vec3<f32>(0.1, 0.5, 0.9);

        // Chromatic aberration / Iridescence on wings
        let iridescence = 0.5 + 0.5 * cos(time * 2.0 + uv.xyx * 10.0 + vec3<f32>(0.0, 2.0, 4.0));

        // Plasma core glow
        let coreGlow = smoothstep(0.05, 0.0, bodyShape) * plasmaIntensity * 5.0;
        let coreColor = vec3<f32>(1.0, 0.2, 0.8) * coreGlow * (1.0 + audio * 3.0);

        // Combine
        var bodyColor = mix(baseColor, iridescence, 0.7);
        bodyColor += coreColor;

        // Add auroral plasma flow over the body
        let flow = fbm(uv * 15.0 - vec2<f32>(0.0, time * 3.0));
        bodyColor += vec3<f32>(0.0, 1.0, 0.5) * flow * plasmaIntensity;

        // Smooth edge
        let alpha = smoothstep(0.05, 0.02, d);
        finalColor = mix(bgColor, bodyColor, alpha);
    } else {
        // Outer glow
        let glow = exp(-d * 10.0) * plasmaIntensity * (0.5 + 0.5 * audio);
        finalColor += vec3<f32>(0.2, 0.8, 1.0) * glow;
    }

    // Add trailing shattered crystal particles (using ripples buffer conceptually or just noise)
    let particleNoise = noise(uv * 50.0 + time * 5.0);
    if (particleNoise > 0.95 && d > 0.05 && d < 0.3) {
        finalColor += vec3<f32>(1.0, 0.8, 0.2) * (particleNoise - 0.95) * 20.0 * audio;
    }

    textureStore(writeTexture, id.xy, vec4<f32>(finalColor, 1.0));
}

```
