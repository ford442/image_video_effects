# Swarm Brief: pixel-explode

**Role:** Algorithmist
**Name:** Pixel Explode
**Category:** interactive-mouse
**Description:** (no description field)
**Current lines:** 109
**Target lines:** 159–199 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This shader's sliders are DECORATIONS - u.zoom_params is never read; grid size, radius, force, and search range are all hardcoded while four generic labels (Intensity/Speed/Scale/Detail) sit in the UI doing nothing. Wire every one, with default 0.5 reproducing the current look:
- WIRE ALL 4 DEAD SLIDERS (priority 1 - ids/names/defaults stay EXACTLY, only WGSL roles are born): x ('Intensity', 0.5) -> explosion_force = mix(0.0, 0.16, x) * (1.0 + mids * 0.3) - default = 0.08 bit-exact. y ('Speed', 0.5) -> NEW gentle particle wobble (offset += vec2(sin(time * mix(0.0, 4.0, y) + cellHash * 6.28)) * 0.01 * strength) - the shader currently has zero time animation; the slider was dead so any wiring adds motion, default 0.5 = speed 2.0. z ('Scale', 0.5) -> grid_size = mix(16.0, 64.0, z) - default = 40.0 bit-exact. w ('Detail', 0.5) -> range = i32(mix(2.0, 10.0, w)) - default = 6 bit-exact (search radius must grow when Scale enlarges particles).
- Wire the dead treble: per-cell crackle - cells inside the explosion zone flash brighter by treble bins (`plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x * strength * 0.3`), so the blast edge sparkles with the spectrum.
- Click detonations: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple acts as a decaying second explosion center at its click point (same smoothstep(radius, 0, dist) strength form, force exp(-age * 2.5), ~1.5s), so clicks scatter pixels without holding the cursor still.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the branchless z-buffer particle coverage (inParticle/closest_z), the particle scale-up (1.0 + strength * 2.0), the local_uv texture sub-sampling, and the dark-bg branchless fallback VERBATIM - the particle physics are hand-tuned. The neighbor loop bounds must stay compile-time-friendly (use the new `range` from w as the loop bound - WGSL allows var bounds; clamp range to [2, 10]). dataTextureA stays DISPLAY color. extraBuffer (if used) in [133..255] ONLY.

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
  "id": "pixel-explode",
  "url": "shaders/pixel-explode.wgsl",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Detail",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "tags": [
    "mouse-driven",
    "interactive"
  ],
  "name": "Pixel Explode",
  "updatedParams": [
    {
      "index": 0,
      "name": "Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Detail",
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
//  Pixel Explode
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(gid.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 0.001);

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;

    // Grid Setup — bass widens explosion radius
    let grid_size = 40.0;
    let grid_dims = vec2<f32>(grid_size * aspect, grid_size);
    let cell_size = 1.0 / grid_dims;

    let mouse = u.zoom_config.yz;
    let explosion_radius = 0.5 * (1.0 + bass * 0.2);
    let explosion_force  = 0.08 * (1.0 + mids * 0.3);
    let range = 6;

    var final_color = vec4<f32>(0.0);
    var closest_z   = 1000.0;

    let current_cell = floor(uv * grid_dims);

    for (var x = -range; x <= range; x++) {
        for (var y = -range; y <= range; y++) {
            let neighbor_cell = current_cell + vec2<f32>(f32(x), f32(y));
            let orig_center   = (neighbor_cell + 0.5) * cell_size;

            let to_mouse        = orig_center - mouse;
            let to_mouse_aspect = to_mouse * vec2<f32>(aspect, 1.0);
            let dist            = length(to_mouse_aspect);

            let strength = smoothstep(explosion_radius, 0.0, dist);
            let safeDir  = normalize(to_mouse + vec2<f32>(0.0001));
            let offset   = safeDir * strength * explosion_force;

            let new_center        = orig_center + offset;
            let scale             = 1.0 + strength * 2.0;
            let particle_half_size = (cell_size * 0.5) * scale * 0.9;

            let diff = abs(uv - new_center);

            // Branchless z-buffer and pixel coverage check
            let inParticle = select(0.0, 1.0, diff.x < particle_half_size.x && diff.y < particle_half_size.y);
            let z_depth    = dist;

            if (inParticle > 0.5 && z_depth < closest_z) {
                closest_z = z_depth;

                let local_uv = (uv - new_center) / max(particle_half_size * 2.0, vec2<f32>(0.0001)) + 0.5;
                let tex_uv   = clamp(neighbor_cell * cell_size + local_uv * cell_size, vec2<f32>(0.0), vec2<f32>(1.0));
                final_color  = textureSampleLevel(readTexture, u_sampler, tex_uv, 0.0);
                final_color  = final_color * (1.0 + strength * 0.5);
            }
        }
    }

    // Background — branchless: if final_color.a == 0 use dark bg
    let isBg = select(0.0, 1.0, final_color.a == 0.0);
    final_color = mix(final_color, vec4<f32>(0.05, 0.05, 0.1, 1.0), isBg);

    final_color = clamp(final_color, vec4<f32>(0.0), vec4<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: particle coverage (non-bg) + bass energy
    let alpha = clamp(final_color.a * 0.8 + bass * 0.15 + (1.0 - isBg) * 0.1, 0.0, 1.0);
    let fc = vec4<f32>(final_color.rgb, alpha);

    textureStore(writeTexture, vec2<i32>(gid.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), fc);
}
```
