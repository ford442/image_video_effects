# Swarm Brief: gen-crystalline-nebula-weaver-void-spider

**Role:** Visualist
**Name:** Crystalline Nebula-Weaver Void-Spider
**Category:** generative
**Description:** (no description field)
**Current lines:** 131
**Target lines:** 181–221 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This raymarched nebula-spider has broken audio and a fake noise field. Fix the foundations, then make it glow:
- FIX THE FAKE AUDIO (priority 1): the shader computes `audioBass` from `u.ripples[0].x` with a stale comment claiming it is a plasmaBuffer proxy - ripples[] is click-ripple data, NOT audio, so audio reactivity is dead. Rewire to the real `plasmaBuffer[0].x` (bass) for the spider abdomen pulse and add `plasmaBuffer[0].z` (treble) driving web-thread glint/sparkle.
- Real fbm nebula: replace the fake `sin(dot(...))` accumulation with a true hash-based value-noise fbm (3-4 octaves, rotation matrix between octaves) for the crystalline nebula density, and add an IQ cosine palette `a + b*cos(6.28318*(c*t+d))` for the crystalline hue grading.
- Tame the blowout: plasma_intensity up to 2.0 stacked on glow with no tonemap clips to white - add a hue-preserving clamp at ~2.0 followed by ACES tonemapping before output, preserving the luminous look.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the canonical 13-binding header and Uniforms struct verbatim; keep the ray origin `ro = (0,0,-5*void_depth)` / `max_dist = 20*void_depth` coupling or the spider leaves frame. The JSON uses a non-standard `controls[]` schema - do NOT restructure it; only updatedParams/updated are added to the JSON (handled outside the WGSL).

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
  "id": "gen-crystalline-nebula-weaver-void-spider",
  "name": "Crystalline Nebula-Weaver Void-Spider",
  "type": "generative",
  "url": "/shaders/gen-crystalline-nebula-weaver-void-spider.wgsl",
  "controls": [
    {
      "name": "Web Complexity",
      "type": "slider",
      "min": 0.1,
      "max": 5.0,
      "default": 1.0,
      "step": 0.1,
      "uniform": "zoom_params.x"
    },
    {
      "name": "Gravity Distortion",
      "type": "slider",
      "min": 0.0,
      "max": 2.0,
      "default": 0.5,
      "step": 0.05,
      "uniform": "zoom_params.y"
    },
    {
      "name": "Plasma Intensity",
      "type": "slider",
      "min": 0.0,
      "max": 2.0,
      "default": 0.8,
      "step": 0.05,
      "uniform": "zoom_params.z"
    },
    {
      "name": "Void Depth",
      "type": "slider",
      "min": 0.1,
      "max": 4.0,
      "default": 1.5,
      "step": 0.1,
      "uniform": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Void Depth",
      "default": 1.5,
      "min": 0.1,
      "max": 4.0,
      "step": 0.1
    },
    {
      "index": 1,
      "name": "Web Complexity",
      "default": 1.0,
      "min": 0.1,
      "max": 5.0,
      "step": 0.1
    },
    {
      "index": 2,
      "name": "Gravity Distortion",
      "default": 0.5,
      "min": 0.0,
      "max": 2.0,
      "step": 0.05
    },
    {
      "index": 3,
      "name": "Plasma Intensity",
      "default": 0.8,
      "min": 0.0,
      "max": 2.0,
      "step": 0.05
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ----------------------------------------------------------------
// Crystalline Nebula-Weaver Void-Spider
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
    ripples: array<vec4<f32>, 50>
}

// ----------------------------------------------------------------
// Core SDF and Noise Functions
// ----------------------------------------------------------------

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    var pos = p;
    for (var i = 0; i < 5; i++) {
        // Simplified noise logic
        value += amplitude * sin(dot(pos, vec3<f32>(1.0, 1.5, 2.0)));
        pos *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// ----------------------------------------------------------------
// Spider Geometry
// ----------------------------------------------------------------

fn sdSpider(p: vec3<f32>, audioReact: f32) -> f32 {
    // Abdomen and Cephalothorax
    let abdomen = length(p * vec3<f32>(1.0, 1.5, 1.0)) - (1.0 + audioReact * 0.2);
    let head = length(p - vec3<f32>(0.0, 0.0, 1.5)) - 0.7;
    var body = smin(abdomen, head, 0.5);

    // Legs (Simplified Domain Repetition)
    var pLeg = p;
    pLeg.x = abs(pLeg.x) - 1.5;
    let leg = length(max(abs(pLeg) - vec3<f32>(0.2, 2.0, 0.2), vec3<f32>(0.0))) - 0.1;

    return smin(body, leg, 0.2);
}

// ----------------------------------------------------------------
// Web and Environment Geometry
// ----------------------------------------------------------------

fn sdWeb(p: vec3<f32>) -> f32 {
    let web_complexity = u.zoom_params.x; // Web Complexity
    let p_scaled = p * web_complexity;
    let thread1 = length(p_scaled.xy) - 0.02;
    let thread2 = length(fract(p_scaled * 2.0) - vec3<f32>(0.5)) - 0.01;
    return min(thread1, thread2) / web_complexity;
}

fn map(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> f32 {
    let gravity_distortion = u.zoom_params.y; // Gravity Distortion

    let distortedP = p + vec3<f32>(fbm(p + vec3<f32>(time * 0.5))) * gravity_distortion;
    let displacedP = distortedP - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);

    let spider = sdSpider(displacedP, audioReact);
    let web = sdWeb(displacedP) + fbm(p) * 0.1;
    return min(spider, web);
}

// ----------------------------------------------------------------
// Main Raymarching and Shading
// ----------------------------------------------------------------

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let id = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let uv = (id - 0.5 * vec2<f32>(f32(dimensions.x), f32(dimensions.y))) / f32(dimensions.y);

    let time = u.config.x;
    let audioBass = u.ripples[0].x; // Using plasmaBuffer[0].x proxy
    let mouse = u.zoom_config.yz;

    // Ray setup
    let void_depth = u.zoom_params.w; // Void Depth
    let ro = vec3<f32>(0.0, 0.0, -5.0 * void_depth);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching loop
    var t = 0.0;
    var d = 0.0;
    let max_dist = 20.0 * void_depth;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p, time, audioBass, mouse);
        if (d < 0.001 || t > max_dist) { break; }
        t += d;
    }

    let plasma_intensity = u.zoom_params.z; // Plasma Intensity

    // Basic shading
    var col = vec3<f32>(0.0);
    if (t < max_dist) {
        col = vec3<f32>(0.2, 0.8, 1.0) * (1.0 - t / max_dist) * plasma_intensity;
        col += vec3<f32>(1.0, 0.2, 0.8) * audioBass * plasma_intensity;
    }

    textureStore(writeTexture, vec2<i32>(i32(global_id.x), i32(global_id.y)), vec4<f32>(col, 1.0));
}
```
