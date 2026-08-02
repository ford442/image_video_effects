# Swarm Brief: luma-refraction

**Role:** Algorithmist
**Name:** Luma Refraction
**Category:** image
**Description:** Ripples propagate through the image with speed determined by brightness. Features chromatic refraction offsets (R/G/B at different normals), temporal wave damping memory, audio-driven wave amplitude, and semantic alpha handling.
**Current lines:** 110
**Target lines:** 160–200 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This wave sim drinks its own state buffer: the 'temporal wave memory' mixes dataTextureC.rgb - which is the wave STATE (h in [-10,10], v, 0), not color - into the display at ~7%, injecting simulation garbage into the image (spore-galaxy class, 4th sighting). Fix the plumbing, then make it rain:
- FIX THE MASK-AS-COLOR FEEDBACK (priority 1): remove the `prevRefraction` mix entirely - the wave state must never enter the display path (the refraction offsets already visualize the wave honestly). The A=(h, v, 0, 1) state write and all C reads of state stay EXACTLY as-is (engine-forced contract); only the color mix line dies.
- Click raindrops: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple drops a wave impulse at its click point (same form as the mouse stir: v += gaussian bump * 0.8, radius ~0.05, one-shot), so clicks splash the pond without holding the button.
- Audio rain: on strong bass transients, sprinkle random rain impulses (`if hash21(uv * 91.0 + floor(time * 3.0)) > 0.998 - bass * 0.002: v += 0.3` - branchless step form), so beats make the whole surface drizzle. Also widen the mouse stir slightly when mouseForce is high (radius 0.05 + mouseForce * 0.05).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the wave-equation core is SACRED - the laplacian, localSpeed (luma-driven propagation!), the v/h integration, the damping, the clamp(-10, 10), the A state write, and ALL dataTextureC state reads stay VERBATIM. Preserve the gradX/gradY normal and the r/g/b refraction tap structure. Sliders have custom ranges (Damping 0.9-0.999!) - keep roles AND ranges EXACTLY. extraBuffer (if used) in [133..255] ONLY.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins — persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "luma-refraction",
  "name": "Luma Refraction",
  "url": "shaders/luma-refraction.wgsl",
  "description": "Ripples propagate through the image with speed determined by brightness. Features chromatic refraction offsets (R/G/B at different normals), temporal wave damping memory, audio-driven wave amplitude, and semantic alpha handling.",
  "params": [
    {
      "id": "waveSpeed",
      "name": "Wave Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "mouseForce",
      "name": "Mouse Force",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "damping",
      "name": "Damping",
      "default": 0.98,
      "min": 0.9,
      "max": 0.999,
      "step": 0.001
    },
    {
      "id": "refraction",
      "name": "Refraction",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "features": [
    "mouse-driven",
    "simulation",
    "upgraded-rgba",
    "audio-reactive",
    "temporal",
    "chromatic"
  ],
  "tags": [
    "filter",
    "image-processing",
    "chromatic",
    "audio-reactive",
    "temporal",
    "refraction"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Wave Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Mouse Force",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Damping",
      "default": 0.98,
      "min": 0.9,
      "max": 0.999,
      "step": 0.001
    },
    {
      "index": 3,
      "name": "Refraction",
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
//  Luma Refraction
//  Category: image
//  Features: wave-propagation, mouse-interactive, audio-reactive, upgraded-rgba,
//            chromatic-refraction, temporal-wave-memory, audio-wave-amplitude
//  Complexity: Medium
//  Upgraded: 2026-05-31
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    let waveSpeed = u.zoom_params.x;
    let mouseForce = u.zoom_params.y;
    let damping = u.zoom_params.z;
    let refractionAmt = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let state = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    var h = state.r;
    var v = state.g;

    let texel = 1.0 / resolution;
    let n = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let s = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let e = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let w_val = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;

    let laplacian = (n + s + e + w_val) / 4.0 - h;

    let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

    // Audio-driven wave amplitude
    let localSpeed = waveSpeed * (0.2 + 1.0 * luma) * (1.0 + bass * 0.3);

    v = v + laplacian * localSpeed;
    v = v * damping;

    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    if (mouseDown > 0.5 && dist < 0.05) {
        v = v + (1.0 - dist / 0.05) * mouseForce * 0.5;
    }

    h = h + v;
    h = clamp(h, -10.0, 10.0);

    textureStore(dataTextureA, global_id.xy, vec4<f32>(h, v, 0.0, 1.0));

    let gradX = (e - w_val) * 0.5;
    let gradY = (s - n) * 0.5;

    let normal = vec2<f32>(gradX, gradY);

    // Chromatic refraction: R/G/B see different index of refraction
    let rOffset = normal * refractionAmt * 0.5 * (1.0 + treble * 0.2);
    let gOffset = normal * refractionAmt * 0.5;
    let bOffset = normal * refractionAmt * 0.5 * (1.0 - bass * 0.2);

    let rUV = clamp(uv - rOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv - gOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - bOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    var finalColor = vec3<f32>(0.0);
    finalColor.r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    finalColor.g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    finalColor.b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Temporal wave memory: previous refraction tint bleeds in
    let prevRefraction = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    finalColor = mix(finalColor, prevRefraction * 0.9, 0.05 + mids * 0.02);

    let alpha = clamp(0.8 + abs(h) * 0.05, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
