# Notes: spec-distance-field-text (Batch 18, Algorithmist)

## Line delta
- Before (brief baseline): 220 lines
- After: 277 lines (+57, within +50 to +90 expansion budget; inside 270–310 target band)

## Changes per technique

### 1. Depth UV fix (priority 1) — FIXED
- Both `readDepthTexture` sampler-read sites (early-exit path and main-path
  `depth_in` passthrough) now sample with `uv01` instead of the `-1..1`
  remapped `uv`. Out-of-range clamp poisoning of the depth chain eliminated.
- Pixel-space `textureLoad(readDepthTexture, pixel, 0).r` was already correct
  and is unchanged.

### 2. Temporal feedback trails (dataTextureC) — MADE REAL
- Previous frame read back via `textureLoad(dataTextureC, pixel, 0)`.
- Decay `TRAIL_DECAY = 0.92`, accumulated trail clamped pre-tint at
  `TRAIL_CLAMP = 1.2`, mixed at `TRAIL_MIX = 0.25 * overlayMix`
  (≤ 0.3 as required), suppressed under fresh glyph strokes (`1.0 - glyphMask`).
- Store to `dataTextureA` now writes `(trailStore, d)` where
  `trailStore = clamp(glyphColor * glyphMask + trailAccum * (1-glyphMask), 0, 1.2)`
  — fresh stroke wins, decayed trail accumulates. Stable: decay < 1 and hard
  clamp prevent runaway feedback.
- Constants declared as named `const`s at file head.

### 3. Spectral glyph selection — IMPLEMENTED
- Per-bin FFT energy from `plasmaBuffer[1..4].x` (one bin per glyph).
- `spectralGlyphIndex()` = branchless argmax over the four band energies —
  loudest band picks the rune.
- `spectralGain = clamp((bin0+bin1+bin2+bin3) * 0.375, 0, 1)` gates a
  branchless `select()` hijack in `sdGlyphGrid`: hash pick survives at low
  energy, dominant band overrides as energy rises.

### 4. Click ripples — IMPLEMENTED
- `rippleDisplacement()` loops `u.ripples[0..min(u32(u.config.y), 50u)]`
  (guarded per engine contract), expanding SDF displacement rings in uv01
  space (`sin(ring*60) * gaussian envelope * age decay`), applied as
  `d -= rippleDisplacement(uv01, time) * 0.04`.

## Slider wiring (existing JSON contract preserved — ids/defaults/ranges untouched)
| Index | Mapping | Param | Drives |
|---|---|---|---|
| 0 | zoom_params.x | glyph_scale (0.3) | `glyphScale = mix(2.0, 12.0, p1)` — rune grid density |
| 1 | zoom_params.y | glyph_width (0.3) | `glyphWidth = mix(0.003, 0.02, p2)` — SDF stroke half-width (mask + shadow) |
| 2 | zoom_params.z | glow (0.4) | `glowRadius = mix(0.0, 0.05, p3)` — gaussian halo falloff; also scales `glowColor` intensity via `(0.5 + p3)` |
| 3 | zoom_params.w | overlay (0.7) | `overlayMix` — composite blend of shadow/glow/glyph/trail; `< 0.001` early-exit passthrough preserved |

`updatedParams` (index 0–3) written to JSON verbatim from brief.

## Binding compliance
- Canonical 13-binding layout preserved exactly (0 sampler … 12 plasmaBuffer read);
  no bindings added/renumbered; binding 13 not declared (unused).
- `@workgroup_size(16, 16, 1)` ✓
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame
  (including early-exit path) ✓
- `textureSampleLevel(..., 0.0)` for sampler reads, `textureLoad` for storage
  reads ✓
- `extraBuffer` declared but never written — no reserved-range violations ✓
- `sdGlyph0..3` and branchless `sdGlyph` index-weight selection preserved
  VERBATIM ✓; no reserved keywords used as identifiers ✓

## QA flags
- `wgsl_precommit_gate.py`: PASS (0 warnings; naga step skipped — binary not
  installed in this VM, environmental, gate exit 0)
- `audit_extrabuffer.py`: AUDIT PASS (0 violations)
- `audit_dead_sliders.py`: AUDIT PASS (0 dead sliders)
- JSON block matches brief fence byte-for-byte (verified by script diff).
- No GPU in this VM — visual verification not possible; correctness asserted
  via gates/audits and code review only.
