# BRIEFS fork D — galaxy-sim (galaxy.wgsl), lenia (both FIRST pass)

Written before any WGSL edit. HEAD = origin/main 8c537fe6 (only galaxy's header differs: coordinator prelude migration).

## HEAD findings (rescues to make)

galaxy.wgsl
- **Arm seam**: `arms = mix(2,6,armCountP)` is fractional (default 3.6) and enters `cos(spiralAngle * arms)` where `spiralAngle` contains `atan2` — the branch cut at angle = ±π is a visible hard seam (left of centre, confirmed in the 320² render). Fix: integer arm count (`round`), default 3.6 → 4 arms, so the default picture keeps the look but loses the seam.
- **Strobing stars**: `hash3(vec3(floor(screenP*50), time*0.01))` — the third component sits inside `sin(dot(..))*43758`, so a 0.02 s time step fully re-rolls the hash (measured: 0 px overlap between t=1.00 and t=1.02, 28 vs 22 star px). The whole star field re-randomises every frame (frame-hash strobing, §12.5 avoid list). Fix: drop `time` from the star hash; the existing `twinkle` (treble) is the scintillation.
- Square star cores (one full 50-cell/unit square per star → 10 px blocks at 1080p): make the core round (small, same brightness at centre).

lenia.wgsl
- `pow((potential - mu) / sigma, 2.0)`: base can be negative → undefined `pow` on real GPUs (SwiftShader tolerates it, hence 0 NaN here). Fix: `d*d` (identical value where defined).
- Otherwise HEAD is the 2026-10-05 rescue (alive Lenia, numpy-gated); do not change the update rule's role.

## SHADER: galaxy-sim (public/shaders/galaxy.wgsl)
IDENTITY: audio-reactive spiral galaxy — bass-breathing rotating arms over a blue core, golden arms, diffraction-spike stars, a pulsing central eye, silence reversing the flow.
KEEP VERBATIM: 4 params + mappings (opacity 0.5..1, arms 2..6, rotation 0.5..3, spread 0.1..0.5); spiral phase (`bassRot`, `armTwist`, `cos(spiralAngle*arms)`), breathing, core/arm density mix, core→arm palette, 4-point diffraction spikes, treble twinkle, central eye, vignette, ACES, presence alpha, depth composite, mouse parallax, A = (density, armDensity, starBright, alpha).

MECHANISM INTERROGATION
- Tactic 2 (physics one step further): a real spiral's arm is a density wave; the gas shocks on its inner (concave) edge, compresses, forms **dust lanes** that absorb the disc light behind them (blue more than red) and then **star formation** lights up just past the lane. HEAD draws the arm as pure emission — no absorption, no star-forming gradient.
- Tactic 3 (promote an intermediate): `armModulation`/`spiralAngle`/`armDensity` are computed and only used for glow brightness; `armDensity` can place the dust lane (phase-shifted) and weight the star population. `starHash.z` is currently a random temperature unrelated to location.
- Tactic 6/1/other: no history is read (C unused; A is display-adjacent output) — no new state needed. Kernel (cos of spiral phase) unchanged.

ADD
 1. **Arm dust lanes — wavelength-dependent Beer–Lambert extinction (§12.2F)** — a narrow lane at a phase offset on the inner edge of each arm, zero in the nucleus and fading outward, multiplies the *disc glow* by `exp(-tau·(0.6,1.1,1.8))` (dark and reddened, blue eaten most). Belongs: a galaxy's arms are exactly where dust lanes live; consumes `spiralAngle`/`breathRadius` the shader already has.
 2. **Arm-born stellar population + HII knots (tactic 3, native to galaxy)** — star density rises with `armDensity` (young clusters follow the arms), star colour is pulled blue-white in arms and yellow-orange in the bulge (old population) instead of a random temperature; sparse pink HII knots sit on the arms' outer edge. Belongs: uses the star cells and `armDensity`/`breathRadius` already computed; no new layer.
FORBID: springs/ripples (not pointer-led beyond the existing parallax), IQ palette, new params, anything that changes the spiral phase or arm layout, a different creature.
A PACKING: unchanged (density, armDensity, starBright, alpha); ACES applied to display RGB only.
FORMULA ADMISSION: Beer–Lambert row is §12.2F "Lighting/optical"; family match by the one-sentence rule (the dust lane *is* absorption of an already-drawn emission field). Operates on existing quantities. Deletion test passes both ways (remove lanes → HEAD galaxy; remove the arms → no lane at all).

## SHADER: lenia (public/shaders/lenia.wgsl)
IDENTITY: Lenia-inspired continuous cellular automaton — 3-ring smooth kernel, Gaussian growth mapping, travelling growth packets, click inoculation, thresholded violet/teal display with trails.
KEEP VERBATIM: 4 params + roles (radius → kernel R; growthRate → dt; accumulation → trail persistence; threshold → μ shift + display cutoff); the kernel (`PEAKS`, bump), Gaussian growth, viscosity, packets, click fronts, mouse inoculation, spores, seeding; A = (field, growth, trail, 1 = initialised), field is raw continuous state (display thresholds only on writeTexture).

MECHANISM INTERROGATION
- Tactic 1/4 (deepen kernel; second-order the parameter): μ (the growth window centre) is one scalar for the whole world, so the world self-organises into a single regime (HEAD default: a uniform field of spots/stripes). Lenia research calls the spatially varying version *parameter localization* (Flow-Lenia): different regions host different species/regimes in one world. Same noun, same mechanism, one literal.
- Tactic 3 (promote an intermediate): `potential` (the kernel-weighted neighbourhood) is computed per pixel and used only to evaluate `growth` and gate spores — never shown. The Lenia viewer's classic "potential/growth" panels show it; outside the body it is the kernel's *sensing reach* and the bright thin ring where growth ≈ +1 is the front about to advance.
- Tactic 6: C is read as field + trail (state, not colour); no extra continuity is needed.
ADD
 1. **Parameter localization of μ (tactic 4)** — μ varies slowly in space and time with a smooth noise (zones ≈ 3 kernel diameters wide, drifting over ~minutes); amplitude clamped to the numpy-verified alive band so every slider position still keeps the field alive; σ already scales from μ (0.094·μ) so the growth window stays proportionally narrow. The threshold slider keeps its role (global μ shift + display cutoff); localization rides on top.
 2. **Sensing-reach aura + growth front (tactic 3)** — outside the body, the kernel potential U is shown as a faint teal aura (U relative to μ) and the thin ring where `growth > 0` as a brighter front: you see where a creature will expand next. Reuses `potential`/`growth` already computed; the aura is gated off inside the body so the existing species/growth/trail tints are unchanged.
FORBID: spring, IQ palette, new species palette, a second field/channel, extraBuffer state, changing the kernel peaks or the viscosity, any new param. No B.
A PACKING: unchanged — (field, growth, trail, 1 = initialised) raw; display only changes writeTexture.
FORMULA ADMISSION: not from the §12.2 table (the toolkit has no Lenia row) — admitted by §12.1 tactics 3/4 and the three tests; both consume `mu`, `potential`, `growth` the file already has; no new state.
