# NOTES — fork E (gen-neuro-kinetic-liquid-gold-lotus, kimi-nebula-depth)

Cards + mechanism interrogation: `BRIEFS-forkE.md` (written before any WGSL edit). Scratch: `/tmp/claude-0/-root-image-video-effects/914950b4-f44b-4d87-a537-edda39759ec7/scratchpad/forkE/` (`mrE.mjs` = harness copy that zeroes extraBuffer per frame like the engine, injects ripples, reports `perfMin`; `vis/` = idea switch builds + diffs; `perf_*.txt`).
Visibility method: scratch build with the idea's `IDEA_n` switch at 0 vs the shipped build, same frames/time/sliders, % of pixels with max-channel |Δ| > 0.02 (the consts were stripped from the shipped files afterwards; stripped build verified bit-identical to the measured one).

## gen-neuro-kinetic-liquid-gold-lotus  (public/shaders/gen-neuro-kinetic-liquid-gold-lotus.wgsl)

KEEP VERBATIM held: yes — the four params and roles, smooth-union core+petals k=0.4 with the fbm liquid perturbation, torque wave `sin(7r−11t)·torque`, conductor Fresnel, phyllotaxis florets, rivulets, KH shear rolls, plasma runners + cyan↔magenta mix, gravity-well bend + click wells (ripple.w not read), blossom shocks, ACES→A with `max(ACES, advected exact C × decay)`, semantic alpha, depth. Saved params byte-exact (git diff of the JSON touches description + features only).
A packing: unchanged — ACES display RGBA; alpha semantic coverage. New terms are inside `col` before the single existing ACES (no ACES→C→ACES newly introduced).

### Rescues (HEAD defects; not counted as ideas)
| # | HEAD defect | status | where |
|---|---|---|---|
| R1 | camera looked horizontally along +z with the lotus 22° below the axis and used screen-down uv.y as world-up → upside-down lotus cropped in the top 30 % of the frame | **confirmed by render** (HEAD idle 192: meanL 0.046, lump top-left, half off-frame). Fix: look-at toward (0,−0.05,0), `−camUp·uv.y`; pointer/click wells flip y (`wellWorld`) so they stay under the pointer | L253-263 |
| R2 | `sdLotusPetals` rotated the **untwisted** p by `+a_mod` (sector centre lands at 2·a_mod), used the twisted point only for the sector id, never offset the petal radially → eight petals collapse into a ≤0.6-radius blob (reads as a gold pine-cone; camera-only diagnostic A confirmed it) | **confirmed by render** (diag A vs B). Fix: rotate twisted `q` by `−a_mod`, `p_w.z −= 0.85`, ellipsoid blade `rad=(0.2,0.3,0.55)` (twin lobe `abs(x)−0.06`, bowl lift and fbm kept). Torque wave now actually bends the petals | L87-117 |
| R3 | `mix(col, plasma·2, plasma_factor)` with `plasma_factor ≤ 2.5` extrapolates → negative channels → catalog ACES maps negatives bright (R flare where cyan plasma should be) | **read-confirmed, reachable at plasma_int ≈ 2 or loud audio**; at saved defaults factor < 1 so no default-look change. Fix: weight clamped to 1; `max(col,0)` before ACES | L359-361, ACES line |
| R4 | negative "pointer inactive" sentinel would rotate camera ±3 rad | guard only (cheap), not reproduced | L202 |

Truth notes: the `extraBuffer[133..138]` "spring" never persists (engine zeroes it every frame): `springPos == raw pointer`, `nextHeldGravity == mouseDown`; the unsynchronised reads are harmless because read and written values coincide. Not claimed as a feature. The JSON param **ids** (rotationSpeed / complexity / bloomIntensity / gravityWellStrength) do not describe the WGSL roles (names/mapping do); byte-exact, left.

### Ideas (2 new, native)
1. **Mirror-gold reflection with petal inter-reflection** (L159-170 env helper, L320-336) — 8-step reflected march through `map()`; strike → that gold × F0² (double bounce, more saturated), escape → tiny studio (dark warm floor, warm horizon, cool fill echoing the background, key softbox on the existing light direction `l`), all × existing spectral `fresnel`, `gold_smooth` sharpens the mirror. §12.2 row: native (Fresnel family; consumes `n`, `v`, `fresnel`, `map()`). Visibility at saved defaults, idle: **10.8 % of the frame @192, 10.4 % @576** (lotus covers ≈ 22–25 % of the frame → ~45 % of lotus pixels), meanAbs 0.0077 / 0.0073.
2. **Anisotropic Kajiya-Kay vein highlight along the petal radial tangent** (L338-346) — second, streaked lobe `pow(√(1−(t·h)²), 24…140)` × `√diff` × `fresnel`; same direction the rivulets already run. Row: native (tactic 7). Visibility: **4.4 % @192, 4.3 % @576** of the frame (≈ 18 % of lotus pixels), meanAbs 0.0016. Quiet by design (a highlight, not a layer).

Default-look change (saved defaults 1,0.5,0.8,0.5, idle, 192): meanL 0.046 → 0.078, stdL 0.088 → 0.145 (R1/R2 put the whole bloom in frame and reflections lift the gold; **eyeball on a real GPU**). 576: 0.077 / 0.143. Held cursor (0.3,0.35) + bass/mid/treb 0.8/0.5/0.9, 40 frames @576 rendered and looked at: camera orbits higher, cyan/magenta plasma bands cross the petals, `nan` 0.

Timing: **not reliably measurable by this fork** — sibling forks kept the machine at load 10–24, and min-of-drained-frames still swung 110→440 ms for the same file. Interleaved rounds (lotus HEAD-vs-new 192 px, ideas-removed-vs-shipped 192/160 px, audio case; kimi 576 px, 6 rounds) gave per-round ratios 0.42–5.98 and medians 0.84–1.82, i.e. noise. Best lower bound: ratio of the lowest observed min per side for ideas-removed vs shipped ≈ 1.00 (160 px: 110.2 vs 109.7 ms; 192 px audio: 328.8 vs 321.9 ms), kimi lowest mins 135.2 (HEAD) vs 119.5 ms (new). By count: Idea 1 adds ≤ 8 extra `map()` calls (each 2 × 4-octave fbm) to a hit pixel that already pays ≈ 30–60 march steps + 6 normal taps + the 43-iteration floret loop → ≈ +10–20 % on hit pixels (hit pixels ≈ 22 % of the frame); Idea 2 is a handful of ALU ops. HEAD-vs-new is not comparable on the lotus anyway (HEAD drew a cropped lump, new fills ≈ 3–4× more pixels). **Coordinator: re-time alone** (`agents/mr.mjs` + the 6-line drained-frame patch; my copy is `scratchpad/forkE/mrE.mjs` with `PERF=1`, interleave script `perf.sh`). Kimi: 1 extra source tap, 2 extra hashes, no loops.

Slider sweep (192 px, min→max of each slider vs saved default, % pixels with |Δ| > 0.02): lotus x 22.3 / 25.6, y 10.4 / 16.3, z 16.8 / 12.2, w 17.8 / 21.7; kimi x 63.4 / 63.2, y 26.1 / 68.6, z 93.3 / 88.0, w 68.2 / 68.4 — all eight sliders live. Click case: lotus `RIPPLES=[[0.5,0.55,0.8]]` → meanL 0.078 → 0.145 (gravity-well warp + blossom shock + trail, HEAD behaviour, nan 0); kimi `[[0.4,0.4,0.9]]` → 9.0 % of pixels differ (misregister), nan 0. 60-frame runs (held cursor + audio 0.8/0.5/0.9) and `A16=1` real rgba16float A: lotus meanL 0.108 / 0.108, kimi 0.317 / 0.317, `nan` 0 in all. R3 check (plasma 2, audio 1/1/1): lotus renders magenta/cyan plasma with gold glints, no red flare, nan 0.

## kimi-nebula-depth  (public/shaders/kimi_nebula_depth.wgsl)

KEEP VERBATIM held: yes — Sobel taps/weights (only the final magnitude line changed, R1), the four params and roles, rosette 0.26 + click `misreg`, luma-driven dot radius base `(1−luma)·0.7`, posterize `floor(c·levels)/levels`, bass dot pulse, mids/treble paper lift, wet-ink bleed from exact C alpha, ACES on display, alpha = ink coverage, depth = ink coverage (as HEAD).
A packing: ACES display RGBA, alpha = ink coverage (unchanged). `python3 scripts/migrate_to_prelude.py` ran first (pasted 13 bindings → `#include "_prelude.wgsl"`; the script also removed `kimi_nebula_depth` from `src/contracts/prelude_migration.json`; infrastructure, `Upgraded:` is bumped for the ideas, not the migration).

### Rescues
| # | HEAD defect | status | where |
|---|---|---|---|
| R1 | `edge = length(gx + gy)` = √3·\|gx+gy\| (gx, gy are broadcast scalars): exactly 0 for the "\" diagonal family, 1.41× too strong on "/" | **confirmed by read + render** (discs had outline on opposite arcs only; new render outlines every arc). Axis-aligned edges give the identical value; only the combination line changed | L189-191 |
| R2 | paper "grain" `hash12_(uv·time·0.001 + 100)` varies ≤ 0.001·t across the frame → one global brightness value, not grain | **confirmed by read**. Static per-pixel tooth (pixel hash blended with a 3-px block hash) | L203-205, L265-271 |
| R3 | vignette spring in `extraBuffer[133..138]` cannot persist (engine zeroes it every frame; effective behaviour = raw pointer) and thread (0,0) wrote it while every other thread read it in the same dispatch | read-confirmed hazard; stateless centre `select(pointer, 0.5, x<0)`. Visible behaviour = HEAD's | L113-115 |
| R4 | pasted bindings | migrated to prelude | header |
| R5 | dot AA cut by the binary `dist < radius` gate | folded into Idea 1: dot drawn from `dotMask` alone | L234-236 |
| R6 | JSON `features` claimed `volumetric`, `3d` (provably false; header says no raymarch) and omitted `audio-reactive` (bass pulse, mids/treble lift read `plasmaBuffer[0].xyz`) / `upgraded-rgba` | corrected | JSON |

### Ideas (3 new, native; quiet, photo-filter family)
1. **Dot gain + minimum printable dot** (L224-236) — ink amount `t=1−luma` gains `0.2·inkDensity·4t(1−t)` (peaks mid-tone, zero at paper/solid; rides Ink Density), dots below ≈ 3 % ink drop out (`smoothstep(0.02,0.06,t')`). Row: native (plate tone curve). Visibility: **22.3 % @192, 23.0 % @576** of pixels (+27 / +44 % of alpha pixels move), meanL 0.328→0.341 when removed (dots are ≈ 4 % darker/larger with it).
2. **Off-register colour plate** (L207-212) — colour plate sampled at `uv + (cos,sin)(0.26)·0.25·dotSize/res` while dots/outlines stay on the true uv. Visibility: **43.8 % @192, 18.7 % @576** (at 192 the 0.25-cell offset is ≈ 0.75 px of a 3 px cell on a high-frequency synthetic source; real photos fringe at edges only).
3. **Ink pools in the paper tooth** (L231-233, L246-247) — dot radius `·(1+0.3·(tooth−0.5)·(1.2−inkDensity))`, outline ink ×(0.75+0.5·tooth). Visibility: **13.2 % @192, 7.1 % @576**, alpha 10.6 / 16.9 %.

Default-look change (saved defaults, idle): meanL 0.340 → 0.328 @192, 0.377 → 0.361 @576; meanA 0.400 → 0.416 / 0.342 → 0.357; stdL 0.198 → 0.191. Held cursor 0.2,0.3 + audio at 576 HEAD meanL 0.382 (vignette moves with the pointer as before).

## Gates
`wgsl_precommit_gate.py --files` pass (both, 0 pasted headers, 0 extraBuffer violations), `verify-naga-wasm.mjs --files` pass (both), `audit:dead-sliders -- --files …` 0 new, `audit:extrabuffer` 0 new (2 known violations are other files). Side effect for the coordinator: the audits rewrote `reports/dead_sliders_audit.*` and `reports/extrabuffer_write_audit.json` (discard); `migrate_to_prelude.py` edited `src/contracts/prelude_migration.json` (keep; one id).
