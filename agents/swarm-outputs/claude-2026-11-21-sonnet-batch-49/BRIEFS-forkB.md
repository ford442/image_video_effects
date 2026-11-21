# BRIEFS — fork B (liquid-metal-prismatic, liquid-oil-iridescence) — written BEFORE any WGSL edit

HEAD = worktree file after `migrate_to_prelude.py` (copies in scratch `b/<id>_head.wgsl`). Both are creative first pass (no `Ideas:`; only a "Codex (e) audited" hygiene comment). HEAD renders at saved defaults (320 px, 60 frames, SRC=img): metal `nan 0 meanL .658 stdL .133 meanA .845`, oil `nan 0 meanL .381 stdL .061 meanA .796`. Neither is blank, neither is pass-through (both have ambient sources: analytic facets / analytic stream + island seeding).

HEAD defect scan (fork checklist): no dead sliders (all four of each are read), no `plasmaBuffer` misuse (`audio=clamp(plasmaBuffer[0].xyz)`), no negative base `pow` (`pow(1-abs(sin),N)`, `pow(1-angle,5)` with angle ∈ [.2,1]), no illegal store to C, no extraBuffer use, alpha is semantic. **No rescues expected.** (Oil writes `writeDepthTexture` from `depth`, metal from `baseUV` depth — both fine.)

---

## SHADER: liquid-metal-prismatic

IDENTITY: silver liquid-metal facets that split the photo into four persistent spectral bands (violet / cyan / amber / red), with shard seams, curvature ribbons, a rotating light sweep and click refraction fronts.

KEEP VERBATIM: 4 params and roles (`ripple_speed`→`speed`, `ripple_intensity`→`intensity`, `curvature`→`curvature`, `spectral_sat`→`saturation`); the `facets` field, `seam`, `sweep`, `disp` (facets + pointer swirl + ripple fronts); the four-tap band sampling (violet from s0.b, cyan s1.g, amber s2.r, red (s3.r+s3.g)/2); the `fresh`/`old` history blend 0.17 along `disp*0.5`; silver `luma*(.42,.5,.62)+(.11,.13,.17)`; `spectral` recombination; ACES on write only; semantic alpha; depth write.
A PACKING: raw four-band intensities in A/C, clamped 0..2.5, **not** tone-mapped (unchanged; JSON `feedbackPacking` already says so).

§12.1 mechanism interrogation
- Tactic 1 (deepen the kernel): the four band taps are placed at uniform offsets (+1.6, +.5, −.5, −1.6)·spread — a linear fan. The next-better approximation of the *same* operator is a Cauchy fan: offset_i ∝ n(λ_i) − n(λ_mid) with n = A + B/λ², which is violet-heavy and compresses the amber/red end.
- Tactic 2 (physics one step further): a prism's angular spread is proportional to its own deviation (δλ ≈ (n(λ)−1)·α). HEAD's fringe width is `0.002 + intensity·.25` everywhere — a constant — so flat facet interiors fringe exactly as much as steep ones. A faceted prism disperses on the steep part and goes clean on the flat part.
- Tactic 3 (promote an intermediate): `disp` is the reflection offset already applied to the *photo*. The light sweep (`sweep`) is evaluated at the undisplaced `p`, so the strip light does not bend on the facets while the reflected photo does — an inconsistent environment map. `disp` is also a facet-slope field (disp ∝ slope·intensity) from which a normal is free.
- Tactic 6 (history): C is read as band intensities (field-like). The only continuity it affords is the existing 0.17 blend; nothing added.

ADD (2 native ideas, a third gated on a measured visible diff):
 1. **Cauchy band spacing, deviation-proportional** (§12.2F *Cauchy dispersion*): replace the uniform ±1.6/±.5 tap offsets with `n_i = A + B/λ_i²` at 410/490/590/650 nm, centred and normalised to the same total span (HEAD span 3.2 → offsets ≈ +1.89, +.29, −.86, −1.31), **and** scale the fringe width by the facet's own deviation `|disp|/(intensity·1.6)` (0.55..1.45, mean ≈ 1) so fringes live on steep facets. No extra taps.
 2. **Reflected strip light** (tactic 3, no §12.2 row): evaluate `sweep` at the facet-displaced reflection position (`p + disp·aspectVec·K`) so the strip light bends and breaks across facets exactly like the photo does. `seam` keeps its position (it is the facet boundary, not an environment feature).
 3. *(gated)* **Conductor Fresnel** (§12.2F *Fresnel–Schlick*) on the facet normal taken from `disp` (`n = normalize(vec3(disp/intensity·S, 1))`, F0 = HEAD silver tint so flat facets are byte-for-byte unchanged). Honest risk: `(1−cosθ)^5` only departs from F0 at grazing, so it may be invisible at defaults. Admitted only if the render shows ≥ ~1% of pixels brightening visibly (steep facets / ripple fronts / pointer swirl); otherwise it is dropped and the NOTES say so.

§12.4 admission: all three consume `disp`, the four taps or `sweep` that HEAD already computes (no new state, binding, solver or spring). Family: prism/metal ⊂ lighting-optical table; Cauchy claimed to this file only; Fresnel shared only with jelly (≤ 2). Deletion test: remove 1 → still four spectral bands; remove 2 → still silver facets with a stripe; keep only 1 or 2 → not an effect. Additive.
FORBID: springs, extraBuffer, thin-film/oil-slick colour, IQ palette, any new ripple overlay, a new param, any change to `facets`/`seam`.

---

## SHADER: liquid-oil-iridescence

IDENTITY: pearl-black film islands transporting magenta / cyan / lime interference contours through fast capillary streams, with held-pointer thinning.

KEEP VERBATIM: 4 params and roles (`viscosity`, `film_ior`→`ior` in the fringe phase, `intensity`, `turbulence`); `stream`, `island`, swirl flow, pointer stir, ripple swirl; semi-Lagrangian film advection + viscosity blend + island/depth seeding + pointer thinning; `phase = thickness·ior·13 + island·.45 + t·(1.4+audio.x)`; `contour = pow(1−|sin(phase·2.3)|,14)` magenta line; `blackPearl` base; accents mix; magenta/cyan/lime emissive additions; Fresnel alpha; depth write; the 3-phase 0/⅓/⅔ hue structure (it IS the magenta/cyan/lime look).
A PACKING: raw state — A.rgb = spectral interference RGB (clamped 0..2.5), A.w = normalised film thickness; **not** tone-mapped (unchanged).

§12.1 mechanism interrogation
- Tactic 1 (deepen the kernel): `spectral(h)` is one cosine with the **same period in all three channels** (+⅓ offsets), so every order repeats the identical hue sequence forever. Real interference has period ∝ λ, so channels slowly de-phase order by order and the film pastels out beyond a few orders (white-light coherence length). The next-better approximation of the same operator is a wavelength-scaled period with a coherence envelope.
- Tactic 2 (physics): an oil film punched thin under a pointer pushes its mass outward: a dewetting hole has a raised rim. HEAD subtracts `local·held·.085` and the mass simply vanishes. Also: lubrication mobility ∝ h^n — thin film barely flows, thick film slides.
- Tactic 3 (promote an intermediate): `thickness` is read only after advection; the pre-advection `filmAt(coord).w` is one load away; `local` (the pointer Gaussian) is already computed and can be re-used at a second width for the rim.
- Tactic 6 (history): C is read as colour+thickness fields. Nothing added to the packing.
- Rejected after reading: **shallow-water continuity as a divergence term** — every flow component is solenoidal by construction (stream: u(y), v(x); swirl: rotation; pointer & ripple: tangential), so `∇·flow ≈ 0` and semi-Lagrangian advection already conserves mass; a divergence term would add ~0. **π-phase / Newton's black film** — `phase` always carries `t·1.4` and `island·.45`, and thickness ≥ .04 maps to ≥ .9 cycles, so thickness never reaches the thin-film limit; the π convention would be a half-cycle palette shift with no visible consequence.

ADD (2–3 native ideas):
 1. **Order-dependent thin-film colour** (§12.2F *thin-film phase*): per-channel fringe period scaled by λ (550/λ_c, damped to ε = 0.07 so the cos 0/⅓/⅔ hue structure and fringe density survive) so hues drift and de-phase across orders, plus a **coherence washout** envelope on the thickness-based part of the phase (thick film → pastel, thin rim → vivid). Replaces the body of `spectral()` only; contour/magenta/cyan/lime terms stay.
 2. **Mass-conserving dewetting rim** (§12.2D *shallow-water continuity*, applied to the one place HEAD destroys mass): thinning under the held pointer becomes `local − ¼·local₂` (local₂ = same Gaussian at ½ the radius⁻¹), a zero-integral dipole, so the removed film re-appears as a raised rim ring whose extra fringes mark the hole edge. Thinning depth at the centre drops 0.085→≈0.064 (stated), nothing changes while no pointer is held.
 3. *(gated on cost/visibility)* **Thickness-dependent mobility** (lubrication h^n law): `flow *= mix(.55, 1.35, smoothstep(.1,.7,h0))` with `h0 = filmAt(coord).w` (1 extra load). Thick islands slide, thin film stagnates → shear at island edges. Dropped if it breaks the default look or exceeds the cost cap.

§12.4 admission: 1 consumes `phase`/`thickness`; 2 consumes `local`/`held`/`thickness`; 3 consumes `flow`/C.w. Thin-film row is shared with rainbow-prismatic (≤ 2) and differs: oil = wavelength-period + coherence (no viewing angle); rainbow = surface-normal angle + Fresnel weight. Deletion test passes both ways (oil without 1 still magenta/cyan/lime islands; film-physics alone is not a pointer-thinned pearl slick). FORBID: springs, extraBuffer, new params, photo-reflection overlay, changing the 0/⅓/⅔ hue offsets, rewiring `film_ior`.

---

## AMENDMENTS after measurement (the cards above are unchanged; this records where the implementation deviated and why)

**liquid-metal-prismatic — Idea 3 (conductor Fresnel) DROPPED.** Prototyped with the slope taken from `disp` (`n = normalize(vec3(disp/intensity·S,1))`, F0 = HEAD silver tint). Measured vs the Idea 1+2 build at saved defaults: S=0.6 → max |Δ| 0.004 (0.0% of pixels > 0.01); S=1.2 → max |Δ| 0.025 (3.1% > 0.01, 0.0% > 0.03). With three click fronts + held pointer at ripple_intensity 0.9 and S=1.2: max |Δ| 0.040, 0.9% > 0.03. `(1−cosθ)^5` only leaves F0 at grazing angles, which this facet field almost never reaches — physically right, visually invisible, so it fails the "visible" gate and is not shipped. Final: 2 ideas.

**liquid-oil-iridescence — Idea 2 (mass-conserving dewetting rim) DROPPED, REPLACED by "reflected radiance".** Measured with a thickness-readout build (held pointer at centre, 120 frames at 16.7 ms steps, 320 px; deficit = held − free thickness):
- HEAD equilibrium: net deficit Σ(held−free)/n² = −0.063; radial profile 0.03:−.27 0.08:−.30 0.12:−.28 0.18:−.20 0.23:−.12 0.28:−.07 0.33:−.05 0.38:−.04 (the dent saturates at the 0.04 clamp out to r≈0.15, half-depth near 0.22).
- Rate-matched ring (r0 .13, w .055, amp .061): net +0.011 (mass *is* balanced) but the profile becomes −.22 −.12 **+.09 +.07** .01 — the ring fills the wide dent and shrinks the hole to r<0.1, and its peak is +0.63 (aliased dense fringes at 320 px). That changes what the held pointer does.
- Ring small enough to leave the dent alone (amp .0065 / .0045): net −0.057 / −0.058 vs HEAD −0.063 — i.e. invisible.
No amplitude both keeps the pointer's dent and shows a rim, so the idea is rejected and not shipped. Replacement (tactic 8, energy accounting — "where does the light the film reflects come from?"): **Idea 2′ reflected radiance** — display-only multiplier `0.7 + 0.6·luma(src)` on the fringe accents (the photo is already sampled as `src`); A is untouched. Deletion test: remove it → HEAD-style constant-brightness fringes over a 15% photo; keep only it → not an oil slick. Same-noun: oil-slick colour *is* reflected light.
Also recorded: **shallow-water continuity as a divergence term is vacuous** (flow is solenoidal by construction) and **π-phase / Newton's black film is unreachable** (phase always carries t·1.4 and island·.45, thickness ≥ .04 ⇒ ≥ .9 cycles) — neither is claimed.

**liquid-oil-iridescence — tuning decisions made by looking.** Idea 1 at full strength (ε .07, coherence .55+.45e^(−2.2h)) flattened the dense high-order rainbow fringes that are part of the look (68% of pixels > .03 vs HEAD, 14% > .08); shipped ε = 0.05 and envelope .72+.28e^(−2.2h). The dispersive period is applied to the thickness term only — applying it to the whole `phase` would de-phase R/G/B steadily with `t·1.4` (≈ one full relative cycle per ~40 s) and the magenta/cyan/lime identity would wander. Idea 3 (mobility) first shipped as mix(.55,1.35) which averages ≈ .76 at the seeded thickness and slowed the "fast capillary streams"; re-centred to mix(.75,1.75) so the mean multiplier ≈ 1 (thick film 2.3× the speed of thin film).
