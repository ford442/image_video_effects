# generative-turing-veins — Algorithmist Notes (Kimi, 2026-07-22, batch 12)

**Role:** Algorithmist
**Shader:** `public/shaders/generative-turing-veins.wgsl`
**Line delta:** 165 → 244 (**+79**, within the +50…+90 window; target 215–255 ✓)

## Key changes

1. **Sliders wired to real sim constants (Priority 1).** The old code read
   `u.zoom_params` only through generic intensity/scale helpers that fed
   cosmetic terms. Rewired each slider to a constant of the RD algorithm:
   - `zoom_params.x` (Primary Scale) → **Gray-Scott kernel radius** of the
     5-point Laplacian (`mix(0.05, 0.35, p.x)`), reaching all three RD layers.
   - `zoom_params.y` (Secondary Scale) → scale of the **second RD layer**
     (`mix(0.75, 2.25, p.y)`); layers 1/3 keep fixed lattices.
   - `zoom_params.z` (Feed Rate) → **Gray-Scott feed**, locked to the
     striped-vein regime `0.03–0.07` (FEED_MIN/FEED_MAX consts, clamped).
   - `zoom_params.w` (Vein Glow) → **bioluminescent ridge gain**. NOTE: this
     slider's max is **1.5**, not 1.0 — the old code's blanket
     `clamp(zp, 0, 1)` silently truncated it; now clamped to 1.5 and
     normalized before mapping (`mix(0.2, 2.4, …)`).
2. **Real Gray-Scott step.** `turing_pattern` now computes a 5-point
   Laplacian of the activator/inhibitor fbm fields at the slider-driven
   kernel radius and applies one explicit Gray-Scott update
   (`a*b*b` reaction, kill = 0.062). Activator/inhibitor are **clamped to
   [0,1] after the update** per the CAUTION, so the explicit scheme is
   unconditionally stable. Combined coarse/fine/micro terms also clamped.
3. **Bass nutrient pulse.** `plasmaBuffer[0].x` × a slow radial sine wave
   from screen center (aspect-corrected) modulates the feed rate
   (±0.012, re-clamped to the regime) so veins visibly swell on beats.
4. **Click seeding.** Rising edge of mouse-down tracked via
   `extraBuffer[5]` (single-writer thread at (0,0), read by all next frame;
   [0..4] untouched per CAUTION). On click, colony position/birth-time are
   stored in `extraBuffer[6..8]` (in-bounds, ≤132); a decaying gaussian
   activator colony (`exp(-d²·220)·exp(-age·0.8)`) injects into `veinsRaw`
   and flashes cyan-green at the click point.
5. **Semantic alpha.** `writeTexture`/`dataTextureA` alpha now follows
   vein intensity + ridge glow instead of hardcoded 1.0 (matches the
   JSON's existing `semantic-alpha` feature tag).

## Preserved

- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, bounds guard.
- Core soul: 3-layer fbm-driven Turing vein field, veinThickness,
  nutrientFlow, chromatic activator/inhibitor colors, dataTextureC
  temporal feedback. All original hash/noise/fbm constants untouched.
- All 3 outputs (`writeTexture`, `dataTextureA`, `writeDepthTexture`)
  written every frame.

## JSON

`shader_definitions/generative/generative-turing-veins.json`: added
`updatedParams` (indices 0–3) + `"updated": true` exactly per the brief.
No other field touched — param ids/defaults/min/max/step/mappings are the
saved-preset contract.

## QA flags

- **No GPU in this environment** (headless VM, no WebGPU adapter) — visual
  QA deferred. Verified via `scripts/wgsl_precommit_gate.py`: naga OK,
  bindgroup compatible, workgroup OK, 0 warnings.
- Gate command: `python3 scripts/wgsl_precommit_gate.py --files
  public/shaders/generative-turing-veins.wgsl` → **exit 0**.
- JSON validated with `python3 -m json.tool`.
- Caveat: single-writer click-state in `extraBuffer[5..8]` is read by all
  threads in the same dispatch (no cross-dispatch barrier), so a click is
  reliably seen starting the *next* frame — the established idiom used by
  `gen_wave_equation.wgsl` etc. Also note the engine may write FFT bins to
  `extraBuffer[5..132]`; if the FFT writer is active it can race the click
  state. Same trade-off as existing shaders; flagged for review.
- Feed-regime clamps mean Feed Rate slider sweeps the full 0.03–0.07 band
  but can never leave it — intentional per brief (prevents pattern death).
