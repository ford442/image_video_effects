# BRIEFS — fork A (gen-newton-fractal, gen-bismuth-singularity-loom-engine)

Written BEFORE any WGSL edit. Only pre-edit change in the tree for these files: `gen-newton-fractal.wgsl` header-only `python3 scripts/migrate_to_prelude.py` (pasted 13 bindings + `struct Uniforms` → `#include "_prelude.wgsl"`; infra, no `Upgraded:` bump; the script also removed the id from `src/contracts/prelude_migration.json` pending — coordinator-owned file, reported).

## HEAD renders (SwiftShader, saved-default sliders, SRC=img, 60 frames / 4 s, 192 px)

| file | case | meanL | stdL | meanA | frameMs | note |
|---|---|---|---|---|---|---|
| newton | idle (0.5,0.45,0.55,0.5) | **0.883** | **0.011** | 0.352 | 192 | washed-out pastel wall, structure only as faint tints |
| newton | held cursor | 0.882 | 0.012 | 0.349 | 205 | |
| newton | audio 0.8/0.5/0.9 | 0.911 | 0.009 | 0.352 | 179 | whiter |
| bismuth | idle (0.5,5,2,1) | 0.387 | 0.176 | 0.847 | 460 | busy; **hard vertical tear through screen centre** (576 px crop: small cubes left of x=288, long diagonal beams right of it, shadow disc cut in half) |
| bismuth | held cursor | 0.376 | 0.186 | 0.844 | 603 | |
| bismuth | audio | 0.550 | 0.110 | 0.957 | 247 | |

## HEAD defects found by reading + rendering (rescues — mandatory, not ideas)

### Newton
- **R1 — orbit traps sit on the roots → every pixel saturates.** `orbitMin`/`orbitSecond` are minima over ALL iterations, including the converged tail where z ≡ root. Roots lie on `|z|=1` (`dRing` = 0 there) and root k=0 lies on the real axis (`dAxis` = 0), so `orbitMin ≈ 0` everywhere → `trapGlow ≈ 1`, `trapIrid ≈ 1`; `sdfGlow` ≈ 0.55 at the root (`sdf = −rootRadius`). Pre-ACES sum ≈ (1.8, 1.9, 2.1) at the default → ACES white (meanL 0.88). Also `feed = trapGlow(1−trapGlow)·4` ≈ 0 → RD accent never fed on boundaries. Fix: accumulate traps only while the orbit is still travelling (`|dz| > gate`), as every orbit-trap renderer does.
- **R2 — `nearestIdx` is constant.** `fract(theta/rootStep + 0.5)·degree + 0.5`: a converged z has `theta/rootStep` ≈ integer m, so the fract is 0.5 and the index is `floor(0.5·degree+0.5)` for EVERY basin → 47 % of the colour is one blue for all basins. Basin identity is the point of a Newton picture. Fix: argmin over the root list inside the existing multi-root loop.
- **R2b — root list ≠ roots at non-integer degree.** Default degree = mix(3,6,0.45) = 4.35. With the principal-branch `cpower` the roots of z^n−1 are at angles m·TAU/n for |m| ≤ n/2 (m = 0, ±1, ±2 → 5 roots at 4.35), but HEAD lists k·rootStep for k = 0..3 (one fake root at 248° ≡ −112°, misses −83° and −166°) → colours/halos on a non-root. Fix: list m_k = [0, 1, −1, 2, −2, 3] with alive = 2|m_k| ≤ n (≤ 6 roots, same MAX_ROOTS).
- **R3 — smooth iteration count is not smooth where it matters.** `smoothIter = iters − log2(tol/max(|dz|,tol))`: for every converged pixel |dz| < tol so the term is exactly 0 → integer bands (isochrone contours and the 0.55 darkening step in whole iterations). Fix with the superattracting form `iters − log2(log|dz|/log tol)` (log-error doubles per step).
- Not rescued, noted: horizontal seam on the negative real axis at fractional degree = the branch cut of `cpower` (identity of the fractional-degree morph) — treated as a feature by N2.

### Bismuth
- **R1 — sector-boundary tear.** `a_mod = mod(angle + s/2, s) − s/2` is a ROTATION repeat; after it the twist (`rot3D(y, tProper·… + sm.x·2)`) makes the content asymmetric in z, so the SDF is discontinuous at all six wedge boundaries (the code comment claims the stage blend avoids tearing, but only the stage is continuous, not the position). The default camera sits exactly in the x=0 plane = a boundary at ±90°, so the tear is a vertical line through the screen centre; the marcher also over/under-steps across it (ribbon streaks, half a horizon disc). Fix: reflect alternate sectors (parity of `sectorId`; 6 is even so the ring closes) → position continuous across every boundary, stage already continuous → SDF continuous. Identity kept: six cubes, each at its own stage.
- Not rescued, noted: `extraBuffer[133..138]` spring is inert (HEAD note; sm ≡ raw pointer); FFT bins read from `extraBuffer[6,9,12]` are the engine's real FFT bins (`audioDepth.ts`: [5..132]) — fine.

## Idea Cards

```
SHADER: gen-newton-fractal
IDENTITY (one sentence): Newton-method basins of z^n − 1 with a continuously variable degree, FBM-warped plane, per-root colours, orbit-trap glow, root halos and a reaction-diffusion accent on boundaries; clicks relax the Newton step.
KEEP VERBATIM: 4 params and roles (zoom → view scale; polynomialDegree → n∈[3,6] + 0.04·bass; iterationPrecision → maxIter 28–84 and tol; boundaryDistortion → warp, perturbation, bloom, halo radius, root-blend); cpower/cdiv Newton step with `relax` (click waves / held mouse); complexNoise perturbation; four-shape orbit trap set (ring, axis, diagonal, spiral) and orbitMin/orbitSecond; multi-root colour accumulation; SDF smooth-union root halo; convergence-order sheen (q, isochrones); Newton-flow striations; wandering-orbit dust; RD accent in the sub-1/256 fraction of A.a (+ unpack/sampleState); 3 % temporal colour mix; chroma shift; ACES on the display colour; semantic alpha (convergence·vignette) and depth.
ADD (2 native ideas; rescues R1–R3 above are not ideas):
  1. Basin-boundary distance-estimate filament — Newton step derivative N′(z) = (zⁿ−1)(n−1)/(n·zⁿ) is accumulated along the orbit (one cdiv + one cmul per step from the zn the loop already has); with the Böttcher/Green potential G = 2⁻ⁿ·(−log(|c|·|zₙ−r|)), |c| = (n−1)/2, the distance estimate d = 2·sinh(G)·|zₙ−r|·2ⁿ/|zₙ′| gives a thin luminous filament that traces the true Julia boundary at constant pixel width at any zoom/degree. Belongs here: the boundary is what a Newton fractal is; HEAD only darkens it by iteration count.
  2. Riemann-sheet hop count — at fractional degree `cpower` lives on a branch of z^n; count how often the orbit crosses the cut (negative real axis) and tint those orbits' basins, amplitude |sin(π·n)| (the actual size of the jump of zⁿ across the cut: 0 at integer degree, max at half-integer). Belongs here: it is the visible cause of the horizontal seam at the default degree 4.35, turned into the picture's own structure.
FORBID on this file: springs / extraBuffer state, IQ palettes, replacing the root palette, new params, a second fractal, glitch costume, anything that changes the Newton step itself (relax / perturb stay as is).
A PACKING: ACES display RGBA in A; A.a = floor(convergenceAlpha·255)/256 + reactionState·(0.999/256) — unchanged (the filament and tint go into rgb only; alpha stays convergence-semantic).
```
Mechanism interrogation (§12.1): T1 kernel — the step is Newton's N(z) = z − f/f′; its first-order companion is N′ = f f″/f′², which the loop can accumulate for free; Halley/Householder would change the basins (identity) so rejected. T2 physics one step further — the derivative of the orbit map is what a distance estimator needs; for a superattracting basin the Green's function is lim 2⁻ⁿ·(−log|zₙ−r|), so the same iteration yields a distance to the boundary. T3 promote an intermediate — `zn`, `znm1`, `degree`, `relax` are already computed each step; `z` before/after gives the cut crossing for free; the root loop already has `dk`. T6 history — C.rgb is the 3 % temporal mix and C.a the RD state; nothing needs a new channel.
Same-noun / deletion / expert: (1) a Newton-fractal author would say "distance estimation for basin boundaries" — yes; deleting it leaves exactly HEAD; deleting the iteration leaves nothing. (2) "Riemann surface sheets of z^n for non-integer n" — yes; deleting leaves HEAD. Formula rows: native (derivative distance estimate; family §12.2E), native (branch-cut crossing); no §12.2 row reused elsewhere in the batch.

```
SHADER: gen-bismuth-singularity-loom-engine
IDENTITY (one sentence): six hopper-crystal bismuth cubes, each self-assembling at its own pace, orbiting a microscopic singularity — terraced boolean-carved lattice with iridescent thin-film fringes, lensed rays, a black horizon shadow, FFT flux veins, click rings and gravitational-memory trails.
KEEP VERBATIM: 4 params and roles (singularity_mass → rs + lens pull; bismuth_iterations → carve count; iridescence_frequency → cosine palette frequency; acoustic_extrusion_force → extrusion); six-wedge ring with per-sector assembly stage (Idea 1) and proper-time dilation (Idea 2); boolean-subtraction carve loop incl. fractional carve; step-wise lensing; glow/flux veins with FFT split; step-count AO; cosine iridescence on n·v; terrace-edge cathodoluminescence; shadow + photon-sphere arcs; click rings; memory trails; alpha/depth; HDR pre-ACES A packing.
ADD (2–3 native ideas; rescue R1 is not an idea):
  1. Terrace-depth oxide bands (§12.2E "fold count as material") — `map` returns which carve iteration defined the surface at the hit; the palette phase is offset per terrace level, so every stair step carries its own interference order, as the oxide layer on real hopper bismuth thickens/changes with the step. Belongs here: the terraces ARE the carve iterations.
  2. Hopper growth lines — concentric rectangular contour lines (median of |q| in the winning carve's box frame, scaled by that level's `scale`) on each terrace tread: the fine stepped growth rectangles every real hopper crystal shows on its faces. Belongs here: same mechanism, one scale finer.
  3. (conditional on measured visibility ≥ ~2 % of frame) Frame-dragged lensing — spin the singularity: add a Lense–Thirring tangential term (axis y, ∝ rs/r³) to the per-step ray bend, so lensed images shear around the spin axis instead of falling straight in. Belongs here: the lensing loop is already step-wise; this is the next physical term.
FORBID on this file: a spring (it is inert here and the engine zeroes it), accretion disc / jets, IQ palette swap, moving the cubes, changing the carve recipe, `fast-motion`.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha; C read back as HDR trail memory — unchanged.
```
Mechanism interrogation (§12.1): T1 kernel — the carve is `d = max(d, −sub_box)` per level; the next-better description of the same operator is "which level won", i.e. the surface's terrace index (free from the loop). T2 physics — hopper crystals: growth is fastest at edges → terraces; the oxide film is thickest/different per step (thin-film colour by thickness); the singularity is rotating → frame dragging after lensing. T3 promote an intermediate — `scale`, `q` and the winning level exist inside the loop and are thrown away; `map_res.y` is a constant 1.0 material id. T6 history — C is the HDR memory trail; nothing new needed.
Same-noun / deletion / expert: (1) a mineralogist would call the terrace colour "oxide thickness per step" — yes; deleting leaves HEAD's n·v bands. (2) growth lines — yes; deleting leaves HEAD. (3) an astrophysicist: lensing around a spinning hole drags — yes. Rows: §12.2E "fold count as material" (bismuth only); growth lines and frame dragging native.
