# Showcase Shader Prompt — Batch 1

Use this prompt for flagship generative shaders intended to run well in a 12-second rotation. The goal is a finished visual instrument, not a rough algorithm demo.

## Role

You are a WGSL shader author for Pixelocity. Create or upgrade only WGSL shader files and shader definition JSON. Do not change renderer TypeScript, bind groups, uniforms, package dependencies, or workgroup parsing.

## Required Interface

Every compute shader must use the existing 13 bindings and `Uniforms` layout from `agents/swarm-tasks/kimi_6_6_26.md`. Default to `@workgroup_size(16, 16, 1)` unless the shader already depends on another size.

## Showcase Standard

A showcase shader must satisfy all of these:

- Strong idle composition within the first second.
- Visible motion evolution over 12 seconds without relying on user input.
- Mouse claim: mouse position or press creates a localized, satisfying response.
- Audio response uses `plasmaBuffer[0]` with bass, mids, and treble mapped to distinct visual qualities.
- Semantic alpha represents effect presence, opacity, or visual energy instead of a hardcoded `1.0`.
- `dataTextureC` temporal feedback is paired with `textureStore(dataTextureA, ...)`.
- `readDepthTexture` influences compositing, parallax, focus, or depth output.
- Final color uses one canonical `acesToneMap`.
- Header and JSON features include `upgraded-rgba`, `aces-tone-map`, and every real feature used.
- `naga public/shaders/{shader-id}.wgsl` validates successfully.

## Prompt: Ethereal Silk

Create `gen-ethereal-silk-veil`, a high-quality generative silk and veil effect.

Visual direction:

- Multi-layered translucent silk ribbons or veils flowing in a soft wind.
- Elegant luminous fabric folds with subtle gold, ivory, pearl, and warm shadow tones.
- Strong idle beauty: the shader should look composed with no image input and no mouse interaction.
- Mouse claim: the cursor gathers, parts, or disturbs the fabric locally like a hand moving through cloth.
- Audio response: bass changes ribbon weight or wave amplitude, mids change flow, treble adds shimmer or fine flutter.
- Depth-aware layering: nearer silk should feel brighter, more opaque, or more detailed.
- Temporal feedback should add smooth continuity, not heavy smearing.

Required params:

- `zoom_params.x`: flow speed.
- `zoom_params.y`: wave or fold intensity.
- `zoom_params.z`: layer density or ribbon count.
- `zoom_params.w`: sheen, shimmer, or translucency.

Output files:

- `public/shaders/gen-ethereal-silk-veil.wgsl`
- `shader_definitions/generative/gen-ethereal-silk-veil.json`
- `agents/swarm-outputs/kimi-notes/gen-ethereal-silk-veil.notes.kimi.md`

## Prompt: Fractal Ember

Create `gen-fractal-ember-lattice` only after Ethereal Silk passes showcase readiness.

Visual direction:

- A fractal crystal or ember lattice that glows, cracks, shatters, and reforms.
- Strong silhouette and readable structure in idle motion.
- Mouse claim: cursor press fractures or magnetically reforms nearby lattice cells.
- Audio response: bass drives ember pulse, mids drive lattice growth, treble drives sparks or edge glints.
- Temporal feedback should preserve ember trails and recovery state.

Required params:

- `zoom_params.x`: lattice scale.
- `zoom_params.y`: fracture intensity.
- `zoom_params.z`: ember heat or glow.
- `zoom_params.w`: reform speed or crystalline sharpness.

Output files:

- `public/shaders/gen-fractal-ember-lattice.wgsl`
- `shader_definitions/generative/gen-fractal-ember-lattice.json`
- `agents/swarm-outputs/kimi-notes/gen-fractal-ember-lattice.notes.kimi.md`

## Validation

Run:

```bash
naga public/shaders/{shader-id}.wgsl
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```

Then compare against `agents/showcase-checklist-v1.md`.
