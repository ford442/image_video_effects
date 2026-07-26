# Notes: kimi_nebula_depth (Batch 18 — Optimizer)

## Line delta
- Before: 218 lines (per brief; naga-transpiled halftone/Sobel ink-stipple)
- After: 290 lines (`public/shaders/kimi_nebula_depth.wgsl`)
- Delta: **+72** (target +50..+90, final 290 within 268–308 ✓)

## Identity fix (priority 1)
- JSON description was "Volumetric nebula with 3D noise, ray marching..." — completely
  wrong for the actual halftone dot + Sobel ink-stipple algorithm. Rewritten honestly:
  "Halftone dot and Sobel edge ink-stipple effect: posterized luma rendered as
  resolution-independent dots with ink outlines, paper grain, and a mouse-driven vignette."
- Param display names updated: Intensity→Dot Size, Speed→Edge Threshold,
  Scale→Posterize Levels, Detail→Ink Density (both `params` and `updatedParams`).
- **Preserved verbatim (saved-preset contract):** param ids (param1..4), defaults (0.5),
  min/max/step, and mapping order (zoom_params.x/y/z/w). No renames, no re-defaults.

## Changes per technique
1. **Honest metadata** — see above; WGSL header comment also rewritten to describe the
   real algorithm and slider wiring.
2. **Bass-reactive dot pulse** — `plasmaBuffer[0].x` (clamped, guarded by
   `arrayLength(&plasmaBuffer)`) drives `dotPulse = 1 + bass*0.35*pulseWave`, scaling the
   halftone cell pitch for a subtle VJ throb. WGSL-only; no new JSON params.
3. **Spring-damped vignette center** — persistent state in extraBuffer safe zone:
   [133..134] position, [135..136] velocity, [137] last frame time, [138] init flag.
   Single writer (global_id == (0,0)) integrates a stiffness-36 / damping-8 spring toward
   the mouse; all threads read the smoothed center. Guarded by `arrayLength(&extraBuffer)`.
4. **Vignette edge-case fix** — the old `if (mousePos.x >= 0.0)` gate made the vignette
   vanish at the left edge (mousePos.x == -1 sentinel / 0.0 boundary). Gate removed;
   vignette is always applied, and a negative-x sentinel is retargeted to screen center
   (0.5, 0.5) so the spring glides home instead of popping.
5. **Dead `radius` variable removed** — `sqrt(luma)*0.5` was computed and never used; gone.
6. **Ink polish (kept subtle, soul preserved):**
   - `edgeSoft = smoothstep(edgeThresh, edgeThresh+0.08, edge)` for anti-aliased ink
     outlines (binary `isEdge` retained for the branch logic).
   - `dotMask = smoothstep(r+0.06, r-0.06, dist)` soft dot rims; dot interior nudged
     toward ink tone at high density.
   - Paper grain hash now also micro-modulates finalColor (±3%) in addition to ink_alpha.

## Slider wiring (u.zoom_params)
- **x — Dot Size:** halftone cell pitch `dotSizeBase = x*20 + 2` px, then scaled by the
  bass pulse. Visibly controls dot grid density.
- **y — Edge Threshold:** `edgeThresh = max(0.01, (1-y)*0.5)` — Sobel sensitivity;
  higher y = more ink outlines (drives both binary `isEdge` and soft `edgeSoft`).
- **z — Posterize Levels:** `levels = floor(z*10) + 2` quantization steps for the
  posterized base color.
- **w — Ink Density:** strength of edge-ink mix, dot alpha, and paper-tone fallback
  (`mix(0.15, 0.45, luma*w)`).
- All four map 1:1 to real constants of THIS shader's algorithm — no generic
  intensity/speed boilerplate. Dead-slider audit confirms 0 dead sliders.

## Binding compliance
- Canonical 13-binding layout preserved exactly (0 sampler … 12 plasmaBuffer read).
  No binding 13 (historyTexture) — shader never used it.
- `@workgroup_size(16, 16, 1)` unchanged.
- Writes `writeTexture`, `writeDepthTexture`, AND `dataTextureA` every frame
  (dataTextureA = composited stipple color + ink alpha aux output).
- Sampler reads via `textureSampleLevel(..., 0.0)`; no storage texture reads.
- extraBuffer writes confined to [133..138] (safe zone 133..255); [0..4] and engine FFT
  bins [5..132] untouched.
- No WGSL reserved keywords as identifiers; no ripple loop used (no guard needed).
- **Preserved verbatim:** Sobel double-loop with all `_eNN` temps, and `hash12_` —
  fragile naga-transpiled core untouched.

## QA flags
- `wgsl_precommit_gate.py`: **PASS** (1/1, 0 workgroup warnings, 0 extraBuffer
  violations). Note: naga binary not installed in this VM, so naga validation step is
  skipped by the gate itself (environmental, not a shader issue); bindgroup + workgroup
  checks ran green.
- `audit_extrabuffer.py`: **AUDIT PASS** (0 new violations, 0 dynamic-index, 0 OOR).
- `audit_dead_sliders.py`: **AUDIT PASS** (0 new dead sliders).
- JSON written verbatim from the brief's fenced block (ids/defaults/mappings unchanged;
  description + display names honest).
- Not visually verifiable in this VM (no GPU adapter); algorithmic correctness checked
  via gates/audits and manual review of the preserved naga core.
