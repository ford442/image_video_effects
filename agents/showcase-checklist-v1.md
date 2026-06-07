# Showcase Readiness Checklist v1

Use this checklist for new or upgraded flagship shaders before they become quality references for the library.

## Required Passes

| Check | Pass Criteria |
|-------|---------------|
| Naga validation | `naga public/shaders/{shader-id}.wgsl` exits 0 |
| Manifest generation | `node scripts/generate_shader_lists.js` exits 0 |
| Duplicate IDs | `node scripts/check_duplicates.js` exits 0 |
| Binding contract | WGSL uses the canonical 13 existing bindings only |
| Workgroup size | Uses `16,16,1` unless algorithmically justified |
| ACES | Exactly one canonical `acesToneMap` function and final color path uses it |
| Temporal feedback | `dataTextureC` reads are paired with `textureStore(dataTextureA, ...)` |
| Semantic alpha | Alpha is computed from effect presence, depth, luminance, density, or energy |
| Depth awareness | `readDepthTexture` affects color, alpha, parallax, focus, or depth output |
| Audio response | Bass, mids, and treble have distinct, non-strobing visual roles |
| Mouse claim | Mouse input produces a localized response without breaking idle composition |
| Header sync | WGSL header features match JSON features for real implemented capabilities |
| Parameter mapping | Four params have clear names, useful ranges, and visible effect |

## 12-Second Rotation Criteria

The shader should look intentional for a full 12-second auto-play slot:

- At 0-1 seconds, the image already has a readable composition.
- At 3-5 seconds, motion has evolved visibly without becoming noisy.
- At 8-12 seconds, the effect still has structure and has not washed out.
- With default params, there is no black frame, full-white frame, or flat static field.
- Temporal feedback improves continuity without accumulating stale artifacts.

## Visual Quality Criteria

- The main subject is legible at desktop and mobile canvas sizes.
- Motion is layered: large structure, medium detail, and small accents should not all move at the same speed.
- Audio reactivity changes visual qualities rather than only brightness.
- Mouse interaction feels like claiming or shaping the scene, not just toggling a post-process.
- The alpha channel supports stacking and does not make the shader fully opaque without reason.

## Rejection Conditions

Reject or send back for revision if any of these are true:

- Missing or extra bind group declarations.
- Missing `textureStore(writeTexture, ...)`.
- Hardcoded final alpha of `1.0` without a written justification.
- JSON claims a feature the WGSL does not implement.
- `dataTextureC` is read but `dataTextureA` is not written.
- Duplicate tone-map functions or double ACES application.
- Effect only looks good with one specific image input.
- Mouse or audio input can drive the output to persistent black, white, or NaN-like artifacts.

## Notes File

Each showcase shader should include a notes file under `agents/swarm-outputs/kimi-notes/` with:

- Shader ID and files changed.
- Intended visual behavior.
- Audio parameter mapping.
- Mouse behavior.
- Validation commands and results.
- Any known limitations.
