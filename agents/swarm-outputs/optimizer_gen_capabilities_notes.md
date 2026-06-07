# Optimizer Notes: gen_capabilities v3

## Performance Improvements
- **Branchless data bars**: Replaced per-pixel `if (uv.y < 0.1)` + `if (uv.y < h*0.08)` divergence with smoothstep masks (`inZone * inBar`). Eliminates warp divergence in the bottom strip.
- **Halton-style hash**: Swapped bare fractal hash for a low-discrepancy Halton-style hash (`halton2`). Same ALU cost, significantly less banding in noise/grain.
- **Single texture sample**: History read stays at one `textureLoad` (no sampler overhead). No redundant samples added.

## Code Elegance
- Magic numbers → named constants (`GRID_COL`, `CURSOR_R`, `TRAIL_DECAY`, etc.).
- `applyControls` helper centralized uniform-driven tuning.
- Click color blend changed from `select(bool_from_uniform)` to `mix(..., step(0.5, uniform))` — still branchless, softer on the eye.

## Pipeline Integration
- Binding contract reordered to exact 0-12 numeric sequence for Pixelocity validation.
- Alpha channel now encodes bloom weight (`gridLine*0.15 + cursor*0.5 + scan*0.35`) for downstream post-process slot chaining.
- Premultiplied alpha output (`rgb*a, a`) ready for compositing.
- `dataTextureA` writeback preserves state for temporal chaining.

## Issues / Notes
- No effective early-exit target (full-screen HUD; every pixel carries UI elements).
- Line count 134 (target ~170) — kept tight to avoid bloat; all critical optimizations applied.
