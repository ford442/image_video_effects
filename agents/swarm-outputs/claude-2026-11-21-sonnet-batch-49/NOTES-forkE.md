# NOTES — fork E (heat-haze-volumetric, 1st pass)

Files touched: `public/shaders/heat-haze-volumetric.wgsl`, `shader_definitions/advanced-hybrid/heat-haze-volumetric.json` (description line only). Not committed. Scratch: `.../scratchpad/e/`.

## Idea Card — ADD list (as implemented; each has a `// ── Idea n` comment at the place it acts)

1. **Sun-baked surface source** (tactic 3, no §12.2 row) — `sunlit = smoothstep(0.45,0.9,luma(base))`; `heat += sunlit²·0.0065·strength`, `column += sunlit·0.0016·depth`. `base` was already sampled at the end of `main` and only multiplied by `trans`; it is now sampled at the top and reused. Rides the existing `heat_gain` (zoom_params.x → `strength`) and `fog_density` (`depth`) sliders, no new param.
2. **Boussinesq buoyancy** (§12.2D, `f_y = (αT − βρ)g`) — `velocity.y −= (heat − 0.35·column)·0.03` (hot rises, dense residual haze settles); the semi-Lagrangian drift term uses the same lift, taken as `max(lift(this cell), lift(cell below))`. Constants: α=1, β=0.35, g=0.03 (HEAD 0.018 with the wrong sign; scanned 0.018/0.04/0.08, 0.03 puts plumes ~15–20 % of the frame above a bright source at 256², 0.04 reaches the top).
3. **Coherent convective eddies** (tactic 5 + algorithmist curl; Gladstone–Dale weight) — `eddyCurl()` = curl of quintic value noise with its analytic gradient (lattice hash = `_std` `hashCell21`/`pcg2d` copied verbatim, integer → vendor-identical, no big-argument `sin`). Two evaluations per pixel (`eNear` at eddy size 0.05·H, `eFar` at 2.2× and scrolling slower), scrolled up the plume (`rise = 0.8·t` lattice units/s); slice `j` uses `mix(eNear,eFar,z)` so far slices see larger eddies. Replaces BOTH the per-slice white-hash `shimmer` and the white velocity jitter `hash21(p ± t)·0.015·turb`. Amplitude `× (0.4 + min(heat,1.5)) × turb × (1.5, 2.0)` — the refractivity contrast (n−1 ∝ ρ_air) so only hot air shimmers; vertical-dominant like a real isotherm gradient.

## Rescues (loud)

- **R1 — idle pass-through (Finding 1): CONFIRMED and fixed** by idea 1. HEAD idle at defaults: `meanA 0.000`, output == source photo (90 frames, 3 s). New: haze rises off the bright regions (`meanA 0.012–0.023`).
- **R2 — haze sank: CONFIRMED and fixed.** Measured on HEAD with the pointer held still at (0.5,0.5): alpha centroid y 0.520 → 0.533 → 0.536 (20/60/120 frames), top-half share 0.325 → 0.278. HEAD's `+heat*0.018` velocity, `+c.z*0.4` drift and the brush kick `+(0.08+audio.x*0.1)` all pointed +y, which is DOWN the screen (y = 0 is the top, back-trace moves content toward +vel). New: centroid 0.477 → 0.464 → 0.461, top-half share 0.672 → 0.720.
- **R2b — (found while fixing R2) HEAD's drift could not lift heat into empty air.** The back-trace offset used only the DESTINATION cell's heat (`c.z*0.4`); an empty cell above a hot one has heat 0, zero drift, so nothing was ever pulled in (sign-fixing alone produced exactly 0 alpha above a hot disc, measured). Fixed inside idea 2 (`max` of this cell and the cell below). Plume alpha at 24–31 / 16–24 / 8–16 px above the disc top: 0.067 / 0.031 / 0.001 at g = 0.018 (was 0.000 / 0.000 / 0.000).
- **R3 — `depth-aware` tag with no depth read (Finding 3)**: `readDepthTexture` is now read (`sceneZ`, 1 = near, 0 = far / no map, same convention as the catalog fog shaders) and scales the optical path `path = 0.5 + 0.5·(1 − sceneZ)`; no depth map reads 0 → ×1.0 = HEAD scale. Measured on the harness depth map (seeded uniform hot column, 1 frame): mean refraction residual on the near disc is 0.92× its no-depth value, far disc 0.99×. Also `writeDepthTexture` now stores a passthrough (HEAD stored nothing).
- **R4 — `pow(x,2.0)` negative base** in the click ring → `x*x`. Latent on real GPUs, **unproven on SwiftShader** (HEAD click render `nan 0`).
- Changed on purpose, not rescue: the eddy gain doubled after a first pass was sub-pixel at defaults (≈0.6 px).

## KEEP VERBATIM (verified by diff of the unchanged tokens)

4 sliders and shader roles; A/C packing (vx, vy, heat, column, raw — no ACES in storage); diffusion mixes 0.04/0.055/0.025; heat-gradient swirl `(n.z−s.z, w.z−e.z)·(0.15+0.55·turb)`; brush (`step(w)`, `exp(−250r²)`, audio.x/y terms); click ring (age<1.7, width 62, 0.2/s, audio.z); decay 0.6/0.22/1.3; 6-slice extinction accumulate; glow colour/gain; alpha `column·0.38 + heat·0.16`; ACES on the display write only. No new param, no spring, no extraBuffer, no B.

## A packing

Unchanged: raw sim state `(velocity.x, velocity.y, heat, column)`; `writeTexture` carries ACES display RGBA with semantic alpha (coverage). A is read back exactly as C via `textureLoad`. `dataTextureB`/`extraBuffer` untouched.

## Measurements (SwiftShader 256², SRC=tex unless noted, params 0.5, box heavily loaded)

Diff vs HEAD (max-channel |Δ| of the ACES display RGB): idle 150 f — mean 0.0091, 21.0 % of pixels > 0.01, 4.1 % > 0.05; pointer held & moving 100 f — mean 0.0168, 28.9 % > 0.01, 9.9 % > 0.05; click ring 90 f (SRC=img) — mean 0.0040, 16.0 % > 0.01, 1.0 % > 0.05. Idea 3 visually confirmed on a seeded uniform hot column: HEAD blurs/frays the stripes (white jitter averaged over 6 slices), new makes them wave coherently.

Stress (NaN count 0 in every run): all params 0, all params 1 (400 f, pointer held, loud audio), 3 clicks + loud audio, no source/no depth map, 900-frame idle at (1, 0.5, 1, 0.5) — `meanA` bounded (0.091), no runaway.

**Timing** (`agents/mr_perf.mjs`, SRC=tex, pointer held, params 0.5, HEAD/NEW interleaved with alternating order, 14 rounds in two batches at 384² and 256²): median of per-round ratios — min-of-drained-frames **1.18×**, p25 1.20×, median-frame 1.06× (cap ≤ ~1.3×). Per-round min-metric ratios ranged 0.65–1.90 because load average was 13–18 (four other forks timing at once), so treat the figure as "about 1.1–1.2×, under the cap", not a precise number; the coordinator should re-time on a quiet box. Cost shape: +1 depth sample, `base` hoisted (no extra sample), 2 `eddyCurl` evaluations per pixel (`eNear` is shared by the velocity forcing and the slices, `eFar` by the slices; BRIEFS planned 3) replacing 8 sin-hashes; no trimming was needed.

## Gates (this file)

precommit 1/1 (naga OK, bindgroup compatible, 0 pasted headers, 0 extraBuffer violations); verify-naga-wasm 1/1 valid; audit_dead_sliders 0 new (all four sliders read by hand: x → strength [brush heat + sun source], y → refract, z → depth [brush column, sun column, extinction], w → turb [swirl + eddies]); audit_extrabuffer PASS (the one known baseline violation is not this file). No real-GPU visual QA — structural/SwiftShader only.

## Could not verify

Real-GPU look and feel of the plume / shimmer; the `pow` NaN on a real GPU; whether the idle sun source reads well on real photographs (the harness image is synthetic); timing on a quiet box (see above).
