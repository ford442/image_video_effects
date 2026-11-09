# sonnet/batch-21 — fork B notes

Shaders: gen-hyper-labyrinth, gen-chromodynamic-glass-labyrinth, gen-fractured-monolith (2nd passes). Cards: `BRIEFS-forkB.md` (written before WGSL).
Renders: `forkB/` (`cmp_<id>.png` = before | after | audio 0 | audio .9/.8/.7 | held mouse; `new_many_<id>.png` = time samples; `final_576.png`). Mini renderer = SwiftShader, no real GPU — **real-GPU visual QA is external**.
Gates: naga/bind-group gate 3/3; `audit_dead_sliders` 0 new; `audit_extrabuffer` 0 new; no NaN at 128/192/576 px, audio 0 / 1,1,1, held mouse, t=7 / 300, slider extremes. Saved `params` and `x-meta.upgrade.params` untouched (JSON diff = `description` only). No new bindings/extraBuffer/springs.

## gen-hyper-labyrinth
- KEPT: 4 params + roles, XW/YZ rotation, gyroid sum, 3-point lighting, veins/pulse/click fronts/held swirl, Ideas 1–4, A = persisted raw neon RGB + alpha (ACES display only).
- IDEA 5 W-modulated wall thickness (tactic 4): `map()` — `wSwell = 1+0.3 sin(0.5 q.w+1.3)` scales the Wall-Thickness mean. Walls swell/thin as the XW rotation sweeps.
- IDEA 6 corridor step-count AO (§12.2E): `corridorAO()`, 5 taps; multiplies lit base + rim only (neon stays emissive), min 0.35.
- RESCUE A: camera inside a wall (python port: inside 20% of the loop, clearance < 0.15 for 50%; HEAD frames at t=0.5/3/9 were one flat colour). Fix = soft near plane `0.9·(1−smoothstep(0.1,0.6,clearance))` + march out through any wall the ray starts in. RESCUE B: camera basis was mirrored and upside-down (uv.y down added to `up`, `right=cross(up,fwd)`): now `right=cross(fwd,up)`, `−up·uv.y`, swirl uses the same basis.
- Residual: ~20% of time-samples are still a close wall face with big neon blobs (corridors are ~0.5 wide at scale 3) — that is the maze, not blank.
- Before/after (192 px, 24 frames t=2..5, default sliders, audio .4/.3/.2): meanL .510→.475, stdL .243→.257, nan 0. Glass: meanL .117→.196. Monolith: meanL .170→.074 (dark sky, no blue dome), stdL .205→.14.

## gen-chromodynamic-glass-labyrinth
- KEPT: lattice fold, spin, box∖sphere smax, 4 params (byte-exact; structuralDensity default 2.0 etc.), interior() march + Beer-Lambert, per-cell ior, band→wavelength mapping, palette, alpha = transmission, ACES display RGBA.
- IDEA 4 Cauchy dispersion (§12.2F): eta offsets ×−0.73 (R) / +1.27 (B) instead of ±1 (same mean spread, Dispersion slider unchanged).
- IDEA 5 Fresnel–Schlick from per-cell ior (§12.2F): `schlickF0`, replaces (1−cos)³; plus exit-face transmittance `(1−F_exit)` (0.4 on TIR) as `interior().z` multiplying `trans`.
- IDEA 6 reflection march: `reflectLattice()` ≤14 steps along `refl`; neighbouring cell's own palette tint (distance-attenuated) or sky replaces the lone white spec in the Fresnel branch (spec kept on top).
- RESCUE: camera-in-glass. On-axis ride crosses a cell boundary at every integer second; rotating cube corners (reach r=1.21) contain the point at r=1 (numpy probe: map = −0.006 @t=3, −0.026 @t=12/17) → flat frames. Fix = march out through the glass (Beer-Lambert tinted `camTrans`) + soft near plane `0.8·(1−smoothstep(0.05,0.5,map(ro)))` for the ≤0.2 near-contact frames.
- Time samples T = 3,5,7,9,12,17,21,31,45,60 all show lattice (HEAD T3/12/17 flat).

## gen-fractured-monolith
- KEPT: 4 params + roles, box ∩ cell-shard SDF with drift/crackNoise, chips, seam glow/pulse/dust, Ideas 1–4 (+ earlier chips/dust), A = ACES display RGBA history.
- IDEA 5 per-shard levitation phase: shard bobs `(sin(t·lev·0.7+φ)−sin φ)·0.2·spread`, φ from `hash31(cellId)`; zero at t=0 / spread 0 / lev 0.
- IDEA 6 downdraft ring train (§12.2D deep-water dispersion) — **moved out of the SDF (round 2)**. Physics unchanged (`ringWave()`: λ 1.2/2.3/3.4, ω=√(gk), group speed ½ω/k, retarded-time emit from the bob speed; `ringHeight()` sums the 3 and fades 1/(1+0.6r)). It is no longer in `map()`: it is evaluated only at the floor hit (`ringHeight` at r and r+0.05 → slope) and acts as (a) a tilt of the floor normal (`nF`, so sheen/Fresnel/reflection terms ring), (b) a crest/trough modulation of the seam-pool light `(1+1.6·ringN)`, (c) a pale crest glint beyond the pool, fading with radius. `ringN = clamp(24·h, ±1)` is a display gain on the physical height. Reads as concentric rings expanding from under the slab (`forkB/r2_rings_floor.png`, T4..T9); a still slab (Levitation Speed 0) raises none.
- IDEA 7 chipped-edge wear (§12.2E SDF curvature): now the 4-tap tetrahedron Laplacian `(Σd(p+k_i·0.025) − 4d)/(2e²)` using the hit distance `d` the march already holds (was 7 map() calls); convex → pale edge, concave → grime. `calcNormal` also became a 4-tap tetrahedron gradient (was 6).
- RESCUES (HEAD defects): (1) camera upside-down (uv.y flip) — floor grid rendered at the top; (2) shard tumble was `∝ time` about the slab axis → slab eroded to a few fragments by t≈12: now bounded `tanh` wobble about each shard's own centre; (3) audio multiplied absolute time in bob/yaw/floor-wave phases (`slabBob`/`slabYaw` helpers shared with the seam-pool light now keep audio on amplitude / bounded wobble); (4) spall chips lived in every cell of the infinite fold (sky "snow") — intersected with a shell `baseBox−1.4`; (5) trail history: tone-mapped C was decayed ×0.82 and re-tone-mapped ×1.12 → non-zero fixed point 0.69, so the sky's blue channel climbed to a saturated hard-edged dome that never faded: now `acesInverse(prev)/1.12 · 0.82` before the max.
- The default look is therefore a dark night sky + intact fractured slab + cyan seam pool with expanding rings (HEAD: saturated blue dome, slab eroding). Rescue look re-checked after round 2 at 192 / 576 px, held mouse + loud audio, t=300 silent: upright slab, dark sky, no chip snow (`forkB/r2_final_mono.png`).
- Round-2 timing (frameMs, 192 px, 32 frames, t=2..5, default params, alternating HEAD/current, SwiftShader): round 1 HEAD 36–44 (min 36, med 37.5) vs current 44–82 (min 44, med 56.5; machine load ~10, ratio min 1.22); round 2 HEAD min 36, med 42.5 vs current min 43, med 53.5 (ratio min 1.19). Quieter earlier run: HEAD min 36 / med 40.5 vs current min 42 / med 48.5 (1.17 / 1.20). Before round 2 the coordinator measured 39 → 73 (+87%). Now ~1.2× HEAD (min-based), target ≤1.35×. Medians under load are noisy.
- Gates after round 2: naga/bind-group ✅, dead sliders 0 new, extraBuffer 0 new, no NaN.

## Formula tally (§12.4 de-dup)
Step-count AO ×1 (hyper), SDF curvature ×1 (monolith), Cauchy ×1 + Fresnel–Schlick ×1 (glass), deep-water dispersion ×1 (monolith). Over-relaxed tracing not used.
