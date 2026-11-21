# BRIEFS — fork A (liquid-rainbow-prismatic 2nd pass, liquid-lens 1st pass)

Written BEFORE any WGSL edit. HEAD = worktree files as of fork start (copies in the scratch dir `…/scratchpad/a/<id>_head.wgsl`).
Both files were read in full + their JSON. Baselines rendered at 480² (default / held pointer / two clicks): `meanL` 0.616 / 0.551, `nan 0`, no blank, no saturation.

---

## 1. liquid-rainbow-prismatic  (2nd pass)

```
SHADER: liquid-rainbow-prismatic
IDENTITY (one sentence): a curved, draining soap-film of rainbow interference bands that refracts the photo
  with per-channel Cauchy dispersion and gathers dispersed caustics, bent by the pointer lens and click fronts.
KEEP VERBATIM: 4 params and roles (viscosity→curvature, turbulence→dispersion, ripple_strength→filmScale,
  spectral_sat→saturation); `surface()`, central-difference gradient, pointer hover/held push, ripple fronts;
  Cauchy nR/nG/nB + per-channel uvR/uvG/uvB; EXISTING IDEA 1 (gravity drain `drain`, `blackFilm` Newton black film)
  and EXISTING IDEA 2 (6-tap dispersed caustic around each channel's own refracted uv) untouched; the 120° per-
  channel cosine offsets in `film`; history mix via `historyAt`; audio.x/y/z roles; ACES on display; depth write.
ADD (2 native ideas, both on the surface normal the file already derives from `gradient`):
  3. Film viewing-angle phase (§12.2F thin-film phase) — HEAD's phase is d·19/λ with NO cosθ_t term, so the
     bands look identical whether the film is flat or tilted. A real film's optical path is 2·n·d·cosθ_t: tilt
     the film and its colours blue-shift (shorter path, lower order). The slope is `gradient` (already computed);
     cosθ_i from it, Snell into the film (n = 1.33) gives cosθ_t, multiplied into the phase. Flat film = HEAD
     exactly; bulges, the held lens and click fronts get angle-shifted Newton-ring colour.
  4. Fresnel-weighted film reflectance, energy-conserving (§12.2F Fresnel–Schlick, applied to the film) — HEAD adds
     the film colour with a constant 0.12 weight and computes `fresnel` only for alpha (from a ×24 lever on a
     gradient that is ~1e-3, so it is ≈0.04 everywhere). The film is a REFLECTION: its weight should follow the
     Schlick reflectance of the same tilted normal, and the light it reflects must leave the transmitted photo.
     Result: rims of the lens / fronts glow with strong colour while the transmitted image dims by the same amount.
FORBID on this file: re-adding Cauchy (already there), a second thin-film model, coherence washout of high orders
  (that is liquid-oil-iridescence's idea), IQ palettes, new springs, extraBuffer state, new params, frame-hash noise.
A PACKING: ACES display RGBA, unchanged (A=C-read-as-colour via `historyAt`; alpha stays semantic coverage —
  its Fresnel term now comes from the film normal).
```

**§12.1 interrogation.**
- Tactic 1 (deepen the kernel): the film model is `cos(d/λ + offset)`; the next-better approximation of the *same* operator is path difference with the angle term, `4π·n·d·cosθ_t/λ`.
- Tactic 2 (physics one step further): a film seen in reflection shows (a) angle-dependent colour and (b) a reflectance that rises toward grazing — the first-order side effects the real soap film has and HEAD lacks.
- Tactic 3 (promote an intermediate): `gradient` is computed and used only for the uv shift; its length is a free tilt. `fresnel` is computed and used only for alpha.
- Tactic 6 (history): C is read as colour; I add no new continuity (the history mix already exists). No packing change.

**§12.4 admission.** Both rows are in the lighting/optical table; both consume `gradient` (already computed). Deletion test: removing either leaves exactly HEAD; removing the *film* and keeping only the idea is not a rainbow shader (it is a tilt shader) → additive. Same-noun: soap film / Newton rings / Fresnel — all this file's nouns. De-dup: the thin-film row is shared with liquid-oil-iridescence (≤2 files); this file takes the **angle + reflectance** halves, oil takes π-convention/coherence/continuity.

---

## 2. liquid-lens  (1st pass)

```
SHADER: liquid-lens
IDENTITY (one sentence): a multi-lobed liquid lens under the pointer (plus two orbiting lenslets) that refracts
  the photo with chromatic fringes, caustic meshes, click rings and held-pointer compression.
KEEP VERBATIM: 4 params + roles (refraction→flow gain, radius→lobe radius, dispersion→fringe gain, surface-wave→
  mesh amplitude); `lensLobe` geometry (5/3/4 lobes, phases, `held` shrink/boost), orbitA/orbitB paths, `mesh`
  wave term, ripple fronts + `ring`, the teal↔amber caustic colour, history mix `uv-flow*0.35` with
  `history.a*0.12`, Fresnel tint with the ×5 normal lever, semantic alpha, audio.x/y/z roles, depth write.
ADD (3 native ideas):
  1. Snell-law refraction (§12.2F Snell vector refraction) — HEAD's `flow = bend·refraction` is the small-angle
     limit of Snell. Use the true law for the slope of the same `bend` field: lateral shift per unit slope is
     (1 − η·cosθ_i/cosθ_t)/(1 − η) times HEAD's (η = 1/1.33). Identical at small slopes (so rim, skirt, ripples,
     mesh waves are unchanged), superlinear where the surface is steep (lens core, harder when held) and bounded
     (≤ 1/(1−η) = 4×). Pressing the lens now deepens the bend non-linearly.
  2. Jacobian-determinant caustic (§12.2F implied by “caustic”; claimed by this file) — HEAD's caustic is
     `|mesh|·|bend|·9`, an ornament unrelated to where the warp focuses light. The warp is uv' = uv − flow(uv);
     the screen→source area ratio |det(I − ∂flow/∂p)| is the ray density: >1 where the source is compressed
     into the screen (bright focusing rim at the lens boundary), <1 where the source is stretched (magnified,
     dimmer interior). The determinant is taken by forward differences of the SAME Snell-scaled lens field (3
     lens evaluations: centre, +x, +y). Feeds the existing teal↔amber caustic colour and mildly dims the stretched
     interior (energy moved, not added). `|mesh|·|bend|` caustic and `ring` stay.
  3. Deviation-proportional lateral CA (prism law) — HEAD's fringe is `dir·dispersion` with a CONSTANT width
     wherever |flow| > 1e-4, so the skirt and ripple tails carry full-width colour ghosts. A prism's colour fringe
     is a fixed fraction (the Abbe ratio) of its deviation: `spread = flow·dispersion/0.0445`. Same width as HEAD at
     the default lens core (0.0445 is the default `refraction`), vanishes where the surface is flat, scales with
     `refraction` and `dispersion` sliders. No Cauchy (claimed by liquid-metal-prismatic).
FORBID on this file: Cauchy/Brown–Conrady rows, new springs / extraBuffer, IQ palettes, new params, replacing the
  lobed lens or the mesh caustic, a ripple/shockwave overlay beyond the fronts it already has, thin-film colour.
A PACKING: display RGBA history (unchanged; A = writeTexture colour, C read as colour via `boundedLoad`).
```

**§12.1 interrogation.**
- Tactic 1: `flow = bend·k` is linearized refraction; Snell's law is the next-better approximation of the same operator. The caustic mesh is replaced-in-spirit by a real ray-density (Jacobian) — added alongside, not instead.
- Tactic 2: a refracting liquid drop shows (a) nonlinear bending at steep slopes, (b) bright focusing lines where the refraction map folds, (c) colour fringes proportional to deviation. HEAD has none of (a)/(b) and gets (c) wrong (constant width).
- Tactic 3: `bend` (a slope-like field) is the intermediate; Snell, the Jacobian and the Abbe fringe are all functions of it. `lensLobe` already returns exactly the displacement field needed for finite differences.
- Tactic 6: history already read as colour with `history.a`; no new continuity added.

**§12.4 admission.** Snell + Jacobian caustic + CA are all in the optical table / lens identity, consume `bend` (already computed), need no new state. Deletion: removing any one leaves the pointer-lens refraction picture. Replacing the mechanism with only the idea (a Snell blob with no lobes) is not a liquid lens → additive. Cost watch: the Jacobian is 2 extra lobe-sum evaluations (6 `lensLobe` calls); ripples/mesh are excluded from the difference (their gradient is ≪ the lobes'). If over the ~1.3× cap I trim the satellite lobes out of the difference.

**Latent hygiene (not an idea, not counted):** `lensLobe` uses `smoothstep(b, b*0.35, d)` with edge0 > edge1 — undefined by the GLSL/SPIR-V definition, implementation-defined in WGSL; SwiftShader renders it as the clamped formula. I rewrite it as `1.0 - smoothstep(b*0.35, b, d)` (algebraically identical). Latent, unproven on SwiftShader — flagged, not claimed as a bug. No `Upgraded:` implication.
