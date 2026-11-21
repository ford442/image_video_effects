# NOTES — fork E (sonnet/batch-50): gen-radiant-cyber-plasma-astro-griffin, gen-inverse-mandelbrot

Cards, interrogation and formula admission are in `BRIEFS-forkE.md` (written before any WGSL edit). Scratch renders: `/tmp/claude-0/-root-image-video-effects/12631154-16b4-44ad-a621-195684eec032/scratchpad/e/`. VM = SwiftShader, no real GPU: **no visual-QA claim**; box load was 55-72 during all timing, so timing is p25 / paired-median, not min.

---

## gen-radiant-cyber-plasma-astro-griffin — 2nd pass + 6 rescues

**HEAD finding (measured, `g_head_t2.png`):** HEAD did not draw a griffin. It drew an infinite perspective lattice of striped slabs to a horizon, the head and beak small and upside-down at the bottom, a blurry rift. Root causes below.

### Rescues (HEAD defects; default look changes loudly)
| # | Defect | Fix |
|---|---|---|
| R1 | `wingFeathers` repeated with `fract()` in x AND z; the feather box half-length (≈0.63) exceeds the cell half-size (0.25), so the wing was an infinite z-striped floor; `wing_span` only changed stripe width | limited repetition: `clamp(floor(p.x*2), -1, 3)` = 5 primaries per side, one feather in z, SDF stays exact; tip feathers lengthen (×0.9→×1.5) and trail (swept 0.8) so it reads as a wing |
| R2 | `uv.y` not flipped (y=0 top) for a y-up scene → upside-down | `uv.y = (0.5*res.y − id.y)/res.y` |
| R3 | camera at `(0,0,3)` looking −z, but head/beak at −z → saw the rear; **beak shear glint (shipped idea) was unreachable** | front-three-quarter camera (yaw 0.62, pitch 0.30, dist 4.2) via precomputed orthonormal basis consts; fog distance re-based to the creature (`tFog = t − (CAM_DIST−3)`) |
| R4 | `anomaly = mouse*2`, whole creature translated by it (off-centre at the default pointer), and twist `1/(d+0.1)` = ~5 rad at the creature centre (would wreck the body once centred) | pointer-follow in screen space (`POINTER_REACH 3.0`, centred at 0.5,0.5); twist `0.6·warp/(d+0.5)` (0.6 rad at the centre at warp 0.5). `Warp Intensity` keeps its role |
| R5 | tint (`p.y`, `abs(p.x)`) and seam grid (`p.xy + p.z*0.35`) used WORLD coords, so they swam across the creature when the pointer moved | use creature-space `pw = anomalyWarp(p)` |
| R6 | `pow(col, 1/2.2)` AFTER ACES: the Narkowicz fit is already display-referred → double-encoded, creature washed to near-white (426 of 429 ACES generative shaders omit it; scratch A/B in `g_ng.png`) | gamma line removed. **Look decision: darker, saturated violet/cyan; flag for the user** |
Also the ghost shift sign was flipped with the y flip (still trails opposite to the wing motion).

### Ideas added (all findable by `// ── Idea n`)
1. **Flap kinematics (avian, domain-native, not a §12.2 row).** (a) `wingFrame`: flexion wave `sin(t − 0.45·|x|)`, tip lags the root (rigid flap vs wave: 6.7 % of pixels differ at fixed pose); (b) `wingFeathers(…, open)`: upstroke openness `smoothstep(-0.35,0.65,cos t)` widens the primary slots 0.74→0.56 and each primary supinates about its own long axis (tip feathers twist more; wing coverage 11.31 %→10.90 %, 3.0 % of pixels differ, open 0 vs 1 at fixed pose).
2. **Rachis + barb vane with plasma flow along the shaft (not a row).** Shading in feather-local coords re-derived from the same helpers as `map()`: chevron barb albedo, bright rachis ridge, pulses `pow(max(sin(fz·6 − 3.2t − hash·2π),0),6)` travelling root→tip, bass lifts them; rides existing `glowCol` + `plasma_glow`.
3. **Step-count AO (§12.2E, owned; shared with the serpent only).** `aoFive(p,n)` = 5 taps of the file's own `map()`; applied to key/fill/back diffuse, not to seams/spec/rim/emission. Effect is subtle (1.7 % of pixels differ >2/255, max 11/255).

### KEEP VERBATIM (verified in the diff): params + roles, 3-point rig, facet normals, `triGridEdge` seams (coords changed per R5), golden head, primary-feather slots (0.74 closed), beak glint, flap ghost (reads exact C, sign flip only), rift background, ACES, semantic alpha, depth out, body/head SDF, smin blends.

**A packing:** ACES display RGBA in A (unchanged; C read as display colour only by the ghost). **Features tags unchanged** (audio-reactive via `plasmaBuffer[0].xyz` ✓, mouse-driven ✓ — now truly pointer-following). JSON `params` byte-exact; `description` appended.

**Diff vs migrated HEAD:** +137 / −47 lines; picture ≈100 % different (rescue). **Timing (A/B, 256 px, 3 rounds, loaded box):** min 0.95/0.87/0.74, p25 1.08/1.02/0.92, paired-median 1.35/0.99/0.76 — no cost over HEAD (bounded wing = far fewer march steps than the infinite lattice, pays for AO).
**Verified:** nan 0 at defaults, t=2 and 20, mouse drag, all params 1, all params 0, wing span 0.1 and 1.5 (saved range 0.1–1.5), audio 0..1.
**Gates:** wgsl_precommit 1/1, verify-naga-wasm 1/1, dead sliders 0 (all four zoom_params read), audit_extrabuffer pass (no extraBuffer used).

### Open calls / not verified
- The wing is still HEAD's flat slab primitive (planks with a noise-wobbled edge from the facet displacement); a griffin reads, but it is a stylised prism animal, not a majestic one. A curved/cambered feather would be a new motif — not done.
- R3/R4 camera and pointer-reach constants (yaw 0.62, pitch 0.30, reach 3.0) and R6 (gamma) are my judgement; the creature at 16:9 is untested (harness is square-only) — wings are ±3 wide.
- Beak glint now reachable (treble 0→1 changes 7.7 % of pixels incl. the seam treble term) but not isolated.
- Twist profile change (R4) alters what `Warp Intensity` feels like at the high end (swirl is milder near the centre, wider reach).
- Real-GPU visual QA external.

---

## gen-inverse-mandelbrot — 2nd pass, no rescue

**HEAD finding:** healthy (reads as a Mandelbrot set in pastel; nan 0 even at 4× iterations / deep zoom / bass 3). Latent only: `dwellBand` used `smoothstep(0.6, 0.4, x)` with reversed edges → replaced by the equal Hermite value `s·(1−s)` (hygiene, bit-near-identical, no `Upgraded` claim on it). JSON `params: []`; real defaults 0.4/0.3/0/0.3 live in `x-meta.upgrade.params`; all four `zoom_params` are read (grep).
**Owned rows (Orbit trap, Smooth iteration):** HEAD already has both (point trap `orbit_min`, Pickover stalk, `n+1−log2 log2|z|`), so no row was used — the two ideas below are domain-native.

### Ideas added
1. **Exterior distance estimate → filament glow (promote an intermediate).** `escapeNormal` already iterated `dz = 2·z·dz + 1` and discarded |dz|; it now returns `vec3(normal.xy (unchanged), |dz|)`. `DE = ½·|z|·ln|z| / |dz|`, divided by the c-plane pixel footprint `2.5/colorZoom/res.y`; `exp(−DE/2px)` in the hue complement of `hue1` lights the sub-pixel hairs along the boundary, added BEFORE the 0.36 temporal mix. (HEAD's dz starts at 1, so DE is within ~×2 of exact; tuned by eye, scale-free.)
2. **Interior colour-space Lyapunov rings.** `inverseMandelbrot` accumulates `log2|z|` per iteration (one `log2`, reusing the `length(z)` it already computed); mean + 1 = log2|multiplier| per step, = 0 on the boundary of every hyperbolic component and → −∞ at cycle centres; `cos(2π·2·m)` rings, `m` clamped to [−4,0]. Visible in the main cardioid and the period-2 bulb (`m_new_t3.png`). Breathes slightly with the bass-driven iteration count.

**KEEP VERBATIM:** 4 params and roles, noise z0, c from position + pan + pointer, smooth count, orbit-min hue, Julia probe, dwell bands (identical value), escapeNormal direction, fbm interior, ripple tint, stalks + arg bands, C feedback `0.92`/`0.36+0.04·bass`, A = raw pre-ACES HDR col + ACES on `writeTexture`, alpha/depth formulas. **A packing unchanged.** Features tags unchanged (audio ✓ `plasmaBuffer[0].xyz`; mouse pans c ✓).
**Diff vs migrated HEAD:** +43 / −8 lines; at 384 px t=3: 63.4 % of pixels differ >8/255 (72 % >2/255) — rings cover the whole interior and the DE halo the whole boundary region. **Timing (A/B 256 px, 3 rounds, loaded box):** p25 1.19/1.19/1.23, paired-median 1.28/1.17/1.19 (min noisy, 1.25–2.18) → ≈1.2×, inside the 1.3× cap (cost = one `log2` per iteration; DE rides the existing loop).
**Verified:** nan 0 at defaults, iterations 1.0 / zoom 1.0 / bailout 1.0 / bass 1, zoom 0.9 + bass 3 (iteration cap ≈ 320), all params 0.
**Gates:** wgsl_precommit 1/1, verify-naga-wasm 1/1, dead sliders: audit scanned 0 mandelbrot defs (params `[]`), grep by hand: x, y, z, w all read; audit_extrabuffer pass.

### Open calls / not verified
- Ring density (`×2` per log2 unit, ≈ 8 rings from boundary to the clamp) and filament strength (0.55, 2 px) are tuned by eye.
- Rings shift a little with bass (iteration count scales the transient share of the mean); intended as breathing, but unverified on a real GPU.
- Real-GPU visual QA external.
