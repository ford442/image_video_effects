# quantum-foam-lattice — Upgrade Notes (Batch 18, Algorithmist)

**Date:** 2026-07-26
**Lines:** 220 → 276 (**+56**, target 270–310 ✅)

## Changes per technique

### 1. Double-tonemap feedback fix (priority 1)
- **Before:** `dataTextureA` stored ACES-tonemapped display color; next frame `dataTextureC` read it back and the blend output was re-tonemapped → progressive contrast flattening.
- **After:** feedback blend (`mix(color, prev.rgb, 0.25 + bass * 0.15)` — weights preserved verbatim) now runs fully in linear space; `dataTextureA` stores `clamp(feedback, 0.0, 1.2)` linear HDR; `acesToneMap` applied once, only to the `writeTexture` display output.

### 2. Per-cell FFT spectrum
- Each voronoi cell derives an integer bin: `cellBin = u32(floor(cellId * 256.0)) % 8u`, reads `cellFFT = plasmaBuffer[1u + cellBin].x`.
- Cell hue: `hue = cellId + time*0.02 + cellFFT*0.85`; bubble hue offset by `cellFFT*0.5`.
- Extracted a `hueRotate(hue)` helper to avoid duplicating the RGB-hue inline math (used by both cell and bubble colors).

### 3. Ripple displacement waves
- New loop over `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`; active window `age in (0, 3)`.
- Expanding crest (`age * 4.0` in lattice space), band falloff `exp(-|rd - crest| * 2.5)`, temporal decay `exp(-age * 1.6)`, amplitude scaled by `warpStrength * rp.w`.
- Radial displacement accumulates into `warpedP` before foam/voronoi evaluation; a faint per-cell-colored `rippleGlow` is added to color and alpha.

## Slider wiring (4 params, ids/defaults unchanged — saved-preset contract)
| Param | Mapping | Drives |
|---|---|---|
| density (`zoom_params.x`) | index 0 | `latticeDensity = mix(2.0, 12.0, x)` — voronoi cell density |
| foam (`zoom_params.y`) | index 1 | bubble threshold window (`0.62-0.14y` … `0.80-0.10y`) + gain `0.25 + 0.95y` |
| warp (`zoom_params.z`) | index 2 | mouse warp influence AND click-ripple displacement amplitude |
| sparkle (`zoom_params.w`) | index 3 | sparkle threshold `1 - 0.15w` and output gain `* w` |

## Preserved verbatim (per CAUTION)
- Voronoi F2−F1 edge logic (`smoothstep(edgeWidth, 0.0, sqrt(v*.y) - sqrt(v*.x))`).
- 3-channel chromatic-dispersion voronoi re-evaluation (rOffset/gOffset/bOffset + vr/vg/vb + edgeR/G/B).
- Feedback blend weights `0.25 + bass * 0.15`.
- Core algorithm: planck-scale noise, fbm foam field, bass pulse, mids distortion, treble sparkles.

## Binding compliance
- Canonical 13-binding layout unchanged (0–12), no renumbering, no binding 13.
- `@workgroup_size(16, 16, 1)`; writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- `textureSampleLevel(..., 0.0)` for `dataTextureC`; no storage-texture loads.
- `extraBuffer` never written (declared only); no reserved-keyword identifiers.

## QA / gate status
- `wgsl_precommit_gate.py`: **PASS** (1 passed, 0 failed, 0 warnings; naga unavailable in VM — bindgroup + workgroup checks ran).
- `audit_extrabuffer.py`: **AUDIT PASS** (0 violations).
- `audit_dead_sliders.py`: **AUDIT PASS** (0 dead sliders).

## QA flags
- Naga binary not installed in this environment; syntax validated via bindgroup/workgroup gate checks only. Recommend a naga run on a machine with `naga-cli` installed.
- GPU not available in this VM — visual verification not possible here; logic verified by inspection.
