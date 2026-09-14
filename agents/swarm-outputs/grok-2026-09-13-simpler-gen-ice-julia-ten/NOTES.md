# Grok-1 simpler generative ten — NOTES

Per shader: kept verbatim, packing, which ideas are visible in the diff. Five IDs were already stamped 2026-09-09 and were not edited.

---

## SKIP (no WGSL/JSON edit, no date bump)

- gen-ice-crystal-lattice — dendrite teeth; plate vs needle
- gen-interference-moire-field — 6.8% detune; Young path-difference
- gen-iris-bloom-fractal — collarette; Fuchs crypts
- gen-islamic-geometric-tiling — over-under strap; girih dart
- gen-julia-set-classic — exterior DE; log|z| stripes

---

## gen-ifs-fractal-flame
- KEPT: Iterations/Spread/Heat/CA; 4 affine maps; sin/spherical/swirl; gravity well; click burst; luma spawn; Beer-Lambert alpha
- A PACKING: ACES display RGBA in A
- IDEAS IN DIFF: `xfColor` mix from `idx` (color-by-transform); `fang` rotate+0.97 scale after variation
- FLOOR: bass_env extraBuffer[0] → [133] (engine-reserved slot)

## gen-inverse-mandelbrot
- KEPT: Iterations/ColorZoom/CmapRotate/Bailout; z0 noise; interior trap; dwell bands; julia probe; escape normal; fbm interior; ripples
- A PACKING: raw HDR display RGBA in A; ACES on writeTexture (HEAD had no A write)
- IDEAS IN DIFF: `stalkMin = min(|Re z|, |Im z|)` in inverseMandelbrot; `argBand` from `atan2(final_z)`
- FLOOR: bounds guard; semantic alpha; exact C load

## gen-islamic-star-rose
- KEPT: Pattern Complexity/Rotation/Zoom/Color Shift; hex cells; φ pentagram; girih palette; mouse rotation override
- A PACKING: ACES display RGBA in A
- IDEAS IN DIFF: `nested` sd_star at outer/φ; 10-fold `cos(roseAng * 10)` rose ring
- FLOOR: p1 extra strap + star-point range; textureLoad C; mouse UV 0–1 (was `mouse/resolution`)

## gen-isometric-city
- KEPT: Density/Traffic Speed/Neon Glow/Height Scale; isometric rd; cell hash; window grid; orange traffic; mouse pan
- A PACKING: ACES display RGBA in A (HEAD wrote no A)
- IDEAS IN DIFF: `dPodium`/`dTower` setbacks; `occ` time-hash on window cells

## gen-julia-set (`gen_julia_set.wgsl`)
- KEPT: Zoom/Exponent n/Trap Mode/Trap Scale; z^n+c; three traps; Lissajous c; held c override; 2-sample AA; interior filaments
- A PACKING: HEAD wrote telemetry (μ, trap, iter) into A while sampling C as color — lie. Now raw HDR display RGBA in A, textureLoad C, ACES on writeTexture
- IDEAS IN DIFF: circle↔line↔cross lerp via `smoothstep` on trapMode; `velTrap = min(|z-zPrev|)` glow

---

Floor: no new extraBuffer springs. Saved `params`/`updatedParams` names and defaults exact. `upgraded-rgba` added only where ACES + Idea Card are real.
