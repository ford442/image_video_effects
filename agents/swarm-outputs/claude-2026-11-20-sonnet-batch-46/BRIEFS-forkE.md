# BRIEFS fork E — cosmic-flow, gen-raptor-mini-flow (both FIRST pass)

Written BEFORE any WGSL edit. HEAD = origin/main 673d780a (coordinator's prelude migration of gen-raptor-mini-flow is header-only; cosmic-flow already included the prelude). Scratch renders in the session scratchpad `forkE/`.

## HEAD measurements (SwiftShader mini-renderer `agents/mr.mjs`, synthetic image + depth)

**cosmic-flow** — clean at HEAD. All 4 sliders read (speed, scale, intensity, color_shift); audio via `plasmaBuffer[0].xyz`; ripples via `.z`; C read with exact `textureLoad`; A = HDR pre-tonemap (C read as colour history → consistent); no negative into ACES; every `pow` base is `abs`/`max(0,…)`. NaN 0. No rescue needed. One observation: the star layer is `pow(sin(t),18)·step(seed)` over the WHOLE integer cell — i.e. a flat ~10 px square (no point profile), and it is added to `live` *before* the advected-history blend, so in dense nebula it is dragged into jagged pale-blue smears (see `cf_head_stars_crop.png`). That is the hook for Idea 2.

**gen-raptor-mini-flow**
- **Raptors flee the cursor.** `st += dir*time*maxSpeed*(1+coherency)` shifts the *sample* point toward `dir`, so lattice features travel along **−dir**. `dir = mix(normalize(uv), mix(toMouse, eigenvec, flow), turn)`: with `toMouse = normalize(mouse − uv)` the content moves *away* from the pointer. Measured: flat source, turn 1, flow 0, mouse (0.9, 0.5), frames at t = 2.0 and 2.4 (`shift.py`): best match shift **dx = −3 px** (predicted 0.4·0.5 cell·16 px = −3.2 px, i.e. away from the mouse on the right). Header says "predatory raptor agents … hunting".
- **Degenerate eigenvector → `normalize(vec2(0))`.** `eigenvec = normalize(vec2(λ1−Jyy, Jxy))` is the zero vector whenever `Jxy = 0` and `Jxx < Jyy` (pure horizontal stripes, gradient only in y) while the HEAD guard (`abs(Jxy)>1e-4 || abs(Jxx−λ1)>1e-4`) still passes. SwiftShader returns finite for `normalize(0)` (render of exact horizontal stripes: NaN 0), so this is **not VM-reproducible**; on drivers where `x*inverseSqrt(0)` is NaN the whole stripe region goes NaN. Same for `normalize(uv)` at the exact centre pixel (`uv = (coords − dims/2)/dims.y`, centre pixel gives `uv = 0` for even dims) and `normalize(mouse − uv)`. Fixed defensively; marked "unverified on VM".
- Dead sliders: none (turn, speed, rage, flow all read). Audio: `plasmaBuffer[0].x` real. Upside-down: no (`uv` and `mouse` both y-down).
- Floor gaps: HDR red (`rage*0.8`) is returned un-tonemapped (> 1), `dataTextureA` never written, alpha semantic OK (coverage).

## Rescues (kept apart from ideas)
- raptor R1: travel direction flipped (`st -= dir·…`) so raptors move **along** `dir` — toward the cursor / along the flow. Same speed and lattice; only the sign of travel. **Open decision for the user** (changes every saved look's motion direction; at t = 0 the picture is identical).
- raptor R2: dominant eigenvector from `θ = ½·atan2(2Jxy, Jxx−Jyy)` (identical to `(λ1−Jyy, Jxy)/|·|` when non-degenerate, x ≥ 0 branch kept, `(1,0)` in flat areas as HEAD) — no zero-vector normalize.
- raptor R3: `safeNorm` on `normalize(mouse−uv)` and `normalize(uv)`.
- raptor R4 (floor): ACES on display RGB, `dataTextureA` written with the display RGBA (HEAD wrote none; C is never read here — written for the contract), alpha semantic.

---

## SHADER: cosmic-flow
IDENTITY: braided magnetohydrodynamic nebula currents over the source photo — domain-warped fBm, curl eddies, phase-ridge braids and knots, cosine-palette glow, twinkling stars, advected HDR persistence; pointer lens + click vortices.
KEEP VERBATIM: fbm/curl/`q,r,field` stack; braidA/braidB/filament/knots/density; palette (`cosinePalette`, `color_shift`); 4 param roles (speed, scale, intensity, color_shift); depth-curl + chromatic source taps; pointer lens, click vortices; C history advection `historyOffset`/`historyWeight`; ACES on display; A = HDR pre-tonemap RGB + semantic alpha; star *placement* (cell grid displaced by curl, seed, treble gate, twinkle).
MECHANISM INTERROGATION:
- tactic 1 (deepen the kernel): the source is dimmed by `0.78 − density·0.10` — a linear stand-in for extinction. The next-better approximation of the same operator is Beer–Lambert with a wavelength-dependent coefficient.
- tactic 2 (physics one step further): real nebulae are emission *and* absorption: dark dust lanes thread the bright gas and redden the stars behind them. The shader models only emission. Real stars through a telescope are PSFs with diffraction spikes, not flat tiles.
- tactic 3 (promote an intermediate): `phase` (the braid phase) is computed for the bright ridges and only `sin` of it is used; its quadrature (`cos`) is the lane between ridges for free. `field` already gates the filaments.
- tactic 6 (history): C is read as colour history and advected by curl. A point-source layer must NOT enter that history (it smears to comets) — compose it after the blend.
ADD (2 native ideas):
1. **Dust lanes with reddening (Beer–Lambert, §12.2F)** — `τ = 0.95·|cos(phase·1.7 − flowTime·3.1)|⁷·smoothstep(0.30,0.65,field)` (quadrature of braidA, so lanes follow the braids), transmission `exp(−τ·(0.85, 1.0, 1.22))` (∝ 1/λ → blue absorbed most). Multiplies the source photo and stars fully and the nebula emission by half (only the gas behind the lane is cut). Adds a small coverage term to alpha. Zero new taps, no new param.
2. **Point-spread stars with diffraction spikes (Airy, §12.2F)** — replaces the flat cell tile by the star's own profile: jittered centre inside its cell, Airy core (`airy(r·14)`, polynomial J1 clamped to the first zero), 4-point cross spike (longer on the rarest `big` seeds), cell-edge fade. Placement/twinkle/treble gate verbatim. Composited **after** the history blend and kept out of A (A stays gas + source, no star smear); attenuated + reddened by Idea 1's transmission.
FORMULA ADMISSION: both rows in the Lighting/optical table; cosmic-flow is a luminous nebula over a photo (emission + source transmission) → family match. Idea 1 consumes `phase`, `field`, `source`, `nebula`; Idea 2 consumes the existing star cell/seed/twinkle and `filament`. Deletion test: delete either → still exactly this braided nebula; keep only the idea → no braids/gas, not cosmic-flow. Same-noun test: dust, extinction, reddening, PSF, diffraction spike are all astronomy words for a nebula.
FORBID on this file: springs, extra click fronts, a second palette, ripples-as-new-motif, new params, extraBuffer state, thin-film/hologram.
A PACKING: unchanged — HDR pre-tonemap RGB + semantic alpha; star layer excluded from A (documented).

## SHADER: gen-raptor-mini-flow
IDENTITY: a lattice of predatory "raptor" discs (scale-ringed bodies, green glow) navigating a structure-tensor flow of the source image, hue-coded by flow angle, enraged by bass; cursor is the prey.
KEEP VERBATIM: `structureTensor`/`smoothTensor` (3×3 Sobel tensor smoothed 3×3); `coherency`; 4 param roles (turn, max speed, rage duration, flow influence); `dir = mix(normalize(uv), flowDir, turn)`; cell lattice `st = uv·20`; `rng`; `bodyRadius` incl. `rage` growth; scale-ring texture `fract(length(f·rageDuration·10))`; flow-angle hue body colour; green glow / dark trail background; depth passthrough.
MECHANISM INTERROGATION:
- tactic 7 (direction, not just magnitude): the file computes an orientation and a coherency per pixel but the body is an isotropic disc and the only thing coherency does is a speed multiplier. A moving predator is streamlined along its heading.
- tactic 2 (physics one step further): something that moves at speed `maxSpeed` leaves a wake behind it; HEAD's "trail" is a radial halo, not a trail.
- tactic 3 (promote an intermediate): `coherency` (0..1) is only used for speed — promote it to the body aspect ratio. `dir` (the heading) is already computed — promote it to a body frame.
- tactic 6: no C history is owned (HEAD reads/writes none); not inventing one — both ideas are stateless.
ADD (2 native ideas):
1. **Streamlined body (structure-tensor orientation → anisotropic kernel, §12.2A)** — measure the body SDF in the heading frame, stretched `s = 1 + 0.8·coherency` along `dir`, squeezed `1/s` across (area-preserving; `s` clamped so the body never exceeds its cell). Strongly oriented image regions (edges) give long slim raptors; flat regions give HEAD's discs. Glow follows the same metric.
2. **Pursuit wake (soft inverse-square, §12.2F)** — behind each raptor a comet tail along `−dir`: length `(0.16 + 0.34·maxSpeed)·(1 + 0.6·coherency)` (≤ 0.45 cell), width tapering to a point, intensity `1/(1+(a/0.35L)²)·taper` (core radius, no singularity), tinted by the flow-hue, lifted by `rage`. Drawn in HEAD's trail branch and added to alpha as coverage.
FORMULA ADMISSION: Idea 1 row is A (structure-tensor orientation); the shader literally computes a structure tensor (a hybrid "chunk" from conv-structure-tensor-flow) → family match; consumes `coherency`, `dir`, `f`. Idea 2 row is F (soft inverse-square falloff) used for the tail profile; consumes `dir`, `f`, `bodyRadius`, `maxSpeed`, flow-hue. Both stateless. Deletion test: delete either → still the raptor lattice; keep only idea → no lattice/flow field → not this shader. Same-noun: predator body, heading, wake.
FORBID on this file: C history/trail buffer, springs, click ripples, IQ palette, a new motif (feathers, particles), new params, extraBuffer state.
A PACKING: ACES display RGBA (HEAD wrote none; A written for the contract, C never read).

## Batch-level note (fork E)
Four ideas, no shared formula row (F Beer–Lambert, F Airy | A structure-tensor orientation, F soft inverse-square); the only F-row overlap is across two different F formulae and two different files with different second ideas.

---

## Amendments after measuring (cards above were written first; these are what the diff actually does)
- **cosmic-flow rescue R1 (found while rendering the star layer):** HEAD derives the twinkle rate AND phase from `starSeed`, the same seed that gates the star (`seed > 0.96`). The gated range is 4 % wide, so every star pulses in unison. CPU check of HEAD's hash/phase: 201 of 312 gated cells lit at t = 0.7, **0 of 312** at t = 1.3 and t = 2.1 (dark ~85 % of each ~2 s cycle). Rate/phase now come from `hash21(starCell + 29.9)`.
- **cosmic-flow Idea 2 touches HEAD's star placement:** the cell grid was displaced by `curl · 0.025` (≈ 2.4 cells × |curl|, gradient ≈ 1 → stars sheared into arcs; see `cf_dbg_star3`). Reduced to `curl · 0.007` so the PSF reads as a point; the residual still shimmers with the flow. Everything else about placement (cell size, seed gate, treble gate, `(0.5 + filament)`) is verbatim.
- **gen-raptor-mini-flow Idea 2 reworked three times:** (a) tail started at the body's rear edge with a `step` → visible hard vertical seam; (b) measured from the centre but without a rear-half gate → bright strip *ahead* of the body too; (c) final: `rise = smoothstep(0, 0.12, −hFrame.x)` gate, taper to a point, `a0 = 0.8·tailLen`, amplitude `2.0 + 0.5·min(rage, 2)`, tint `0.7·flowHue + 0.3`. At 480 px (24 px cells) the wake is only a few px long; it scales with the cell.
- Header `Ideas:` lines and JSON `features` (`upgraded-rgba` added to both because ACES + both ideas are in the WGSL) updated.
