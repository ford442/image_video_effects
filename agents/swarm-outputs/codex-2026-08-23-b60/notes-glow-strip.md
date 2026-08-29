# Batch 60 notes — edge-glow-mouse + elastic-strip

**Branch:** `upgrade/batch-60-heat-echo-elastic`  
**Trackers:** #525 `edge-glow-mouse`, #526 `elastic-strip`  
**Date:** 2026-08-23

## Files changed

- `public/shaders/edge-glow-mouse.wgsl`
- `shader_definitions/interactive-mouse/edge-glow-mouse.json`
- `public/shaders/elastic-strip.wgsl`
- `shader_definitions/distortion/elastic-strip.json`
- `swarm-outputs/codex-2026-08-23-b60/notes-glow-strip.md` (this file)

## Contract (both)

- Source `params` ids/names/defaults/min/max preserved exactly.
- `updatedParams` aligned (added for edge-glow-mouse; elastic-strip already had matching set).
- 13 bindings, `@workgroup_size(16, 16, 1)`, B unused, no `extraBuffer[0..132]` writes.
- Click loops: `min(u32(u.config.y), 50u)`.
- Held via `u.zoom_config.w > 0.5`.
- Audio: `plasmaBuffer[0].xyz` + bins 1–8 shimmer.
- Exact `textureLoad(dataTextureC, …)` for trail; ACES on display; semantic (unpremultiplied) alpha.

---

## edge-glow-mouse (#525) — 2nd polish after Batch 59

### A packing

`(glowMask, mouseAura, packetEnergy, finalAlpha)`

- R: edge + click composite mask  
- G: mouse proximity aura  
- B: anisotropic tangent packet energy  
- A: semantic display alpha  

B unused. C = previous-frame trail RGB (exact load). No springs / extraBuffer.

### Visual deltas vs Batch 59

| Aspect | Before (B59) | After (B60) |
|--------|--------------|-------------|
| Neon palette | Soft cyan↔pink hue sine | Oil-slick magenta/teal film + HSV fringe; psychedelic poles |
| Bloom | 4-tap tangent samples | 5-tap anisotropic + dual-frequency packets racing along tangents |
| Click | Soft radial blobs | Thin expanding ring wavefront + angular sparkle lobes |
| Held | Radius ×0.82, intensity ×1.25 | Tighter ×0.68, hotter ×1.55 + film boost |
| Trail | C mix retained | Same ownership; slightly stronger trail blend |

Identity stays edge-neon — not a clone of cyan cyber recipes.

---

## elastic-strip (#526)

### A packing

Display RGBA: tonemapped `rgb` + semantic `alpha` (same ownership as prior upgrade).

B unused. C = previous-frame trail (exact load). No extraBuffer writes.  
Direction param `dir` (V/H via `zoom_params.w` / `isHoriz`) unchanged.

### Visual deltas

| Aspect | Before | After |
|--------|--------|-------|
| Bevel | Soft edge + single sub-rib ×3 | Harder bevel (`pow`), nested ×3 + ×7 micro-ribs |
| Packets | Soft fractal runners | Dual sharp traveling pluck packets along strip length |
| Soap film | Mild stretch tint | Stretch-energy driven film + HSV soap mix; stronger under held |
| Held | Drag ×1.45 | Drag punch ×1.85 + chroma/film/packet boosts |
| Click | Single band wave | Primary + trailing harmonic packet |

---

## Validation note

Structural gates / Jest / build are coordinator-side for the full Batch 60 cohort.  
Real-GPU visual QA required (Cloud VM has no WebGPU adapter).
