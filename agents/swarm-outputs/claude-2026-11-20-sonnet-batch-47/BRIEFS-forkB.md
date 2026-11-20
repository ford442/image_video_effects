# BRIEFS — fork B (gen-strange-field-flow, gen-topological-acoustic-knots) — written BEFORE any WGSL edit

Both are **second pass**. Existing `Ideas:` entries are KEEP VERBATIM. HEAD = `git show origin/main:public/shaders/<id>.wgsl` (HEAD renders in scratchpad/B/head). Fork B owns the §12.2E orbit-trap / smooth-iteration / fold-count rows; the two files must not share a row → strange-field-flow takes the two §12.2E rows, acoustic-knots takes no §12.2E row (no liquid-crystal row exists in §12.2, so its ideas come from tactics 3 + 7, justified below).

## HEAD findings (rendered 256², defaults, 40 frames / 6 s, bass=mid=treble=0.3)

### gen-strange-field-flow
- Renders fine (acid-neon whorls, 0 NaN, meanL 0.245). No dead sliders (all four read), audio from `plasmaBuffer[0].xyz` (correct), C read as display RGBA and A written as display RGBA (consistent), no extraBuffer. **No rescue found.**
- Observation only: header says "paints streaks along the local flow direction" but the proximity kernel is isotropic `exp(-|uv-orbitUV|·30)`. Not touched (would be a reimagining of the look; mentioned for the coordinator).

### gen-topological-acoustic-knots
- **Rescue R1 — branch-cut spikes.** `theta = Σ ±½·atan2(...)` jumps by π across each defect's atan2 cut. A director is π-periodic (n ≡ −n), but `dTheta = (θ(p+ε) − θ)/ε` takes the raw difference → ±π/ε ≈ ±390 spurious |∇θ| on the cut line → bright horizontal streak lines at every defect (visible in HEAD panel 1, left edge). Fix: wrap Δθ to (−π/2, π/2] before dividing by ε (`d − π·round(d/π)`). Exact for the full-charge cuts; the partially-faded (`live<1`) cuts of annihilating pairs are genuine discontinuities and remain.
- **Rescue R2 — `defectGlow` polarity inverted.** `smoothstep(0.3, 0.0, defectStrength − 0.5)` = 1 for every pixel with `defectStrength ≤ 0.5` and falls to 0 only near the cores (the opposite of its name). Result: a flat warm veil `(1,0.8,0.4)·(0.5+0.5·treble)` over most of the frame and a dark hole at each core, which is why the default frame reads as a washed-out cream (HEAD meanL 0.662, stdL 0.163). Fix: `smoothstep(0.3, 0.8, defectStrength)` — glow *at* the cores. Scratch test of R1+R2 on HEAD: meanL 0.512, stdL 0.297, oil-slick stripes now visible. **Changes the default look of every preset — flagged for the coordinator.**
- **Rescue R3 (debatable, flagged) — defect positions not aspect-scaled.** `defectOrbit` returns uv-unit positions (x ∈ ≈[−0.3,1.3]) but the pixel/mouse coordinate `uvA.x` spans [0, aspect]; the mouse *is* aspect-scaled. On 16:9 the right ≈ 30–40 % of the frame has no defects. Fix: multiply defect x by `aspect` in `directorAngle`. Identical output at aspect 1.
- Not rescued (inherent to HEAD): `stripe = sin(dot(uvA,dir)·k + …)` is odd in `dir`, so the π jump across a full cut flips the stripe phase (thin seam). Pair-annihilation distance thresholds (0.04..0.16) are in uv units, so under R3 pairs meet slightly less often horizontally.

## Idea Cards

```
SHADER: gen-strange-field-flow
IDENTITY: per-pixel 8-step Clifford↔de Jong orbit; each pixel glows where its own orbit lands back near it, giving acid-neon whorls with burn-in trails and audio-pulsed coefficients.
KEEP VERBATIM: 4 params + roles (drift_speed / chaos_blend / orbit_density / trail_persistence); the two map steps and their `mix` by chaos; Gaussian-ish orbit proximity density; hue from orbit_hue; Lyapunov stretch tint (log|Δstep|, existing Idea); Pickover stalks min(|x|,|y|) (existing Idea); history pull+rotate+chroma-split feedback; ACES display; A = display RGBA; depth = density+stalks.
MECHANISM INTERROGATION:
  tactic 1 (kernel): the orbit is an itinerary through the plane; the standard next descriptor of a chaotic map's orbit after the stretch rate (Lyapunov) and trap distance (Pickover) is its *symbolic itinerary* — which side of each axis it visits.
  tactic 2 (physics one step further): a chaotic map's invariant skeleton is the partition made by the preimages of its folding lines; orbits in different cells fold a different number of times. The loop already computes prevPt/pt each step, so the crossing is free.
  tactic 3 (promote an intermediate): the loop computes `pickover = min(...)` and throws away *which iterate* produced the min; it also computes prevPt·pt and discards the sign relation.
  tactic 6 (history): C is display RGBA read as colour → nothing new asked of it; both ideas are per-frame loop quantities, packing unchanged.
ADD (2 native ideas, both §12.2E):
  1. Fold count as material — §12.2E "Fold count as material": per step `folds += (1 − smoothstep(−w, w, pt.x·prevPt.x)) + (same for y)` = soft count of axis crossings in the 8-step orbit (the orbit's symbolic itinerary). Becomes a hue offset (`folds·0.045`) and a tiny saturation trim so cells that fold the same number of times share a material; boundaries between cells trace the map's folding skeleton. Soft (not integer) so cell edges do not alias.
  2. Trap-hit iteration — §12.2E "Orbit trap" (promote the argmin): record the iterate index `trapIter` at which the Pickover min was achieved; the stalks' flat warm colour becomes mix(warm, hsv(trapIter/ITERS…), 0.55) so stalks born from early iterates (near the pixel) and late iterates (deep in the orbit) read in different tints — depth-of-trap, the standard trap-colouring.
FORMULA ADMISSION: both in the generative table; both consume `pt/prevPt/pickover` the loop already computes; deleting either leaves exactly this effect; either alone would not be a strange-attractor flow (no mechanism replaced).
FORBID: springs/ripples/click fronts, IQ palette, any change to the map coefficients, ITERS, density kernel, or feedback chain; no new param.
A PACKING: ACES display RGBA (unchanged).
```

```
SHADER: gen-topological-acoustic-knots
IDENTITY: nematic liquid-crystal director field θ(x) = Σ ±½·atan2 around orbiting ±½ disclinations (+ pointer defect); iridescent oil-slick stripes along the director, defect glow/cores, pair annihilation, Schlieren brushes.
KEEP VERBATIM: 4 params + roles (defect_density → count, defect_speed → orbit rate, iridescence → stripe gain, flow_strength → stripe frequency); `defectOrbit` motion; ±½ charges and `live` pair-annihilation fade (existing Idea 1); mouse-pinned defect; `iridescent()` cosine ramp on θ; Schlieren `abs(sin 2θ)` brushes (existing Idea 2); singularCore; C feedback 0.97/0.2; ACES display; A = display RGBA; alpha/depth semantics.
MECHANISM INTERROGATION:
  tactic 1 (kernel): |∇θ| is the one-constant Frank elastic energy density. The next better description of the *same* distortion is the Frank decomposition into splay and bend.
  tactic 2 (physics one step further): at a disclination core the scalar order parameter S → 0 (the nematic melts to isotropic); a physicist expects the director texture to vanish into the core, not to alias to infinitely fine stripes.
  tactic 3 (promote an intermediate): `dTheta` (∇θ) and `dir` (n) are both computed and only |∇θ| is used. dot(∇θ, n) and dot(∇θ, n⊥) are free.
  tactic 7 (direction): a +½ defect is a comet — splay on the head, bend on the tail. That anisotropy is invisible today.
  tactic 6 (history): C read as display colour; unchanged.
ADD (2 native ideas; no §12.2 row exists for liquid crystals → justified by tactics 3 + 7 and the expert test: any LC physicist recognises both):
  1. Frank splay/bend tint — `splay = dot(∇θ, n⊥)` (= ∇·n), `bend = dot(∇θ, n)` (= n×(∇×n) magnitude); the defect glow colour moves from warm (splay) to cool (bend) via `(|splay|−|bend|)/(|splay|+|bend|)`. Head/tail lobes of each ±½ defect read in different hues. Uses the existing `dTheta`/`dir`; the amount of glow is unchanged.
  2. Order-parameter core melt — Landau–de Gennes S(r)=r/√(r²+ξ²) with r ≈ 0.5/|∇θ| (the ±½ defect's own 1/r law): the iridescent stripe and shimmer terms are multiplied by S so the director texture dissolves into an isotropic core of radius ξ≈0.06 instead of aliasing; the existing singularCore stays bright.
FORMULA ADMISSION: both read only `dTheta`, `dir`, `theta` that main() already computes; neither adds a state, binding or solver; deletion test: with either removed it is still the same director-field effect; with the original mechanism removed and either idea kept it is not (no θ field → nothing to decompose).
FORBID: orbit/fold/trap rows (those are on the sibling file), thin-film/Airy (fork E), springs/ripples, a new IQ palette, any change to the defect charge model or annihilation.
A PACKING: ACES display RGBA (unchanged).
```
