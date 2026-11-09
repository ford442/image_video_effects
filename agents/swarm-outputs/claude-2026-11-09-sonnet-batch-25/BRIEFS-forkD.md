# BRIEFS — Fork D (sonnet/batch-25): frost-reveal-crystal (1st pass), chromatic-mosaic-projector (2nd pass)

Written 2026-11-09 BEFORE any WGSL edit. HEAD renders + emulations: scratchpad/forkD/ (frost_head_{long,late}_{idle,held}.png = 600/200 frames @192, frost_head_576_idle.png, cmp_head_576_{idle,held}.png, phase_emu*.py, e1/e2/e3 measurements).

---------------------------------------------------------------------------------------------------
## 1. frost-reveal-crystal

### HEAD observation
- Compiles, no NaN. 192 px idle: meanL 0.516 / stdL 0.166 / meanA 0.369. The frost layer is a faint whitening + fbm uv-wobble (`visibility = mask·combined_frost·max_opacity` ≤ 0.5 at default); it does not obscure anything — it reads as a hazy photo, and the melt window at the cursor is barely distinguishable from the frost.
- **Crystal growth is DEAD.** numpy emulation of the exact HEAD phase update (5-point Laplacian ×0.1·growthRate, reaction ×growthRate, growthRate = 0.002..0.012): centre seed r = 0.030 → 0.033 after 1200 frames (20 s @ 60 fps); slider x=1 → 0.036. Confirmed in minirender: 600-frame idle run is the same tiny rosette as frame 24. The `anisotropy` slider only scales a ~1e-6 per-frame reaction term, and `alignment` is ≡ 1 anyway (orientation is the RADIAL angle from the seed, so ∇phase ∥ dir everywhere).
- Orientation is only written where the mouse is held; grown/ring-seeded pixels keep orientation 0 → one magenta hue. Click ripples set `phase` toward 1 on a ring but never `orientation`.
- C packing is consistent (C read = (mask, phase, orientation, impurity); A writes the same raw state; display only goes to writeTexture) — no packing lie. `impurity` is written once at seed and never changed.
- Seeding is `time < 0.1` only. Late-start (T0=5, no seed) renders: C is inherited from the previous shader (display RGBA of that shader read as mask/phase/orientation/impurity) → garbage crystals/frost forever (the dynamics are too slow to heal it). Late-start looks identical to the idle run in minirender only because minirender's C starts as zeros; in the app C is the previous shader's A.
- The "critically damped spring" lives in extraBuffer[133..138] with a thread-(0,0) writer: extraBuffer is re-uploaded zeroed every frame, so `extraBuffer[138] > 0.5` is false for every thread except by race → the live app already runs RAW cursor. minirender (persistent extraBuffer) shows a spring that does not exist in the app.

### Idea Card
```
SHADER: frost-reveal-crystal
IDENTITY: a frost layer on glass that the warm cursor melts away, revealing orientation-coloured
  ice crystals (phase-field Allen–Cahn sim in C) growing beneath; clicks melt + shock-freeze rings.
KEEP VERBATIM: 4 params + roles (growth_speed → frost regrowth rate AND crystal growth rate;
  melt_radius → melt window; max_opacity → frost opacity; anisotropy → crystal anisotropy);
  C/A packing (mask, phase, orientation, impurity) — raw sim state, ACES only on writeTexture;
  frost regrowth + melt (`mask` update); mouse seeding of phase with radial orientation (hue wheel =
  orientation); click melt/shock-freeze rings; fbm frost pattern + uv wobble; crystal hue colouring;
  interface highlight; alpha formula; depth passthrough; audio roles (bass → regrowth, mids →
  supercooling, treble → interface sparkle).
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): the 5-point Laplacian has a square-lattice bias, so any anisotropy
    the shader wants is fought by the stencil's own anisotropy. Next-better operator = isotropic
    9-point (0.2 edges / 0.05 corners); the only remaining anisotropy is then the one we put there.
  tactic 2 (physics one step further): (a) ice grows with SIX-FOLD lattice anisotropy — the growth
    rate depends on the angle between front normal and the crystal axes; that is what the
    "Anisotropy" slider is named for and what HEAD never expressed. (b) Frost is a forward SCATTERER:
    frosted glass diffuses the transmitted image (grainy blur whose radius follows frost thickness),
    it doesn't just wobble it. (c) Where frost melts, a thin water film with a meniscus forms at the
    melt boundary: it refracts and glints.
  tactic 3 (promote an intermediate): the sim already loads the 4 neighbours' full texels but only
    uses `.g` — `.r` gives ∇mask (the melt boundary) for free. `orientation` is already the
    per-pixel lattice-ish angle (radial from seed) — cos(6·orientation) is the six-fold lattice term.
  tactic 6 (history): C is raw state; no spare channel. impurity (A.a) is a pure function of uv
    (never updated) so it stays; state sentinel goes in texel (0,0) per the batch's A-texel scheme.
ADD (3 native ideas):
  1. Six-fold lattice anisotropy on an isotropic 9-point stencil — §12.2D "Isotropic 9-point
     Laplacian" (row budget: frost only) replaces the 5-point; reaction rate gets
     exp(6-fold·anisotropy·cos 6θ) with θ = the inherited `orientation`: crystals grow as six-lobed
     stars (slider 0 = round disc, 0.5 = star, 1 = pointed). Verified in a numpy emulation
     (scratchpad/forkD/emu_arms.png).
  2. Forward-scatter frost — 6-tap per-pixel-rotated disc gather around the existing wobble tap,
     radius ∝ frost thickness (mask·combined_frost); static per-pixel angle = frost grain, no strobe.
     max_opacity still gates how much frosted layer replaces the clear image.
  3. Meltwater meniscus — ∇mask (from the already-loaded neighbours) marks the melt boundary: the
     clear image is refracted along ∇mask (water-bead lens) and a thin lit highlight/shade pair is
     added on the rim; nothing at flat frost or flat clear.
RESCUES (separate from ideas):
  R1 late-start seeding: A-texel sentinel at (0,0) = (0,0,0,0.6182); no sentinel ⇒ seed like
     `time < 0.1` (field re-seeds when the shader is selected mid-session). Pixel (0,0) is state
     (invisible corner), loads of (0,0) remap to (1,0).
  R2 dead spring removed honestly (raw cursor = what the live app already ran).
  R3 dead crystal growth: diffusion D = 0.2 px²/frame (stable ≤ 0.25 for the 5-pt; 9-pt coefficient
     0.667·lap9 gives the same D) and reaction r = mix(0.06, 0.6, growth_speed) so the front creeps
     0.03–0.10 px/frame (emulated at 192 px: r=0.3 → 0.083 px/frame); orientation inheritance: a grown
     pixel adopts the orientation of its highest-phase neighbour (HEAD left it 0 → magenta), click
     ring seeds set the radial orientation like the mouse seeds do.
FORMULA ADMISSION: Isotropic 9-point Laplacian (D) — frost owns a phase field in C, consumes the
  C neighbours it already loads (+4 diagonals), deletion leaves HEAD's sim. Ideas 2 and 3 are tactic
  derived (no table row), consume taps/neighbours that exist. Deletion tests: removing any one leaves
  a recognisable frost reveal; keeping only the idea (no melt, no frost) is not one.
FORBID on this file: springs (removed), click shockwaves beyond HEAD's, IQ palettes, holographic
  scanlines, any new param, changing the crystal hue wheel, replacing the sim.
A PACKING: raw sim state in A (mask, phase, orientation, impurity) exactly as HEAD; texel (0,0) =
  (0,0,0,0.6182) sentinel (state, not a pixel). ACES only on writeTexture. A is rgba16float on most
  tiers: orientation/phase deltas verified f16-stable in the emulation (mean |Δ| 5e-5).
```

---------------------------------------------------------------------------------------------------
## 2. chromatic-mosaic-projector (2nd pass — keep: cell-boundary diffraction fringe; wavelength step)

### HEAD observation (192 + 576 px, idle + held, audio 0 / 0.4,0.3,0.2)
- Compiles, NaN 0. meanL 0.257 / stdL 0.114 / meanA 0.736 (192 idle, T0=2).
- **The mosaic is not readable** and every cell has a dark DOT at its seed: `voronoi()` returns `minDist` = distance to the nearest SEED, but `edgeFade`, `edgeLayer`, `fringeEnv` and `fringePhase` are all named/commented as cell-EDGE terms. Distance-to-seed is 0 at the seed, so colour ×0.65, alpha →0.1 at the cell centre (the dot lattice in the 576 render) and the "cell-boundary diffraction fringe" of the last pass is concentric rings around the seed, not along the border. True borders are never drawn.
- Bass term: `cellSize *= 1 + bass·0.25` rescales the whole lattice about the origin and re-hashes every cell (colour temp, chroma gain, projection rotation). Measured: bass 0.4 vs 0 changes 21.1% of pixels by >0.1 (mean |Δ| 0.046); with that one term removed 0.34% (0.024). Mids 0.4: 7.0%, treble 0.4: 6.1%.
- Click ring `distance(uv01, rp.xy)` has no aspect correction → elliptical ring on non-square canvases.
- Negative values from the fringe go into ACES: measured max effect 0.0006 mean |Δ| (8e-5 of pixels) — hygiene only, no claim.
- Pointer: raw cursor (no spring in this file; idle (0.5,0.5) = projector axis centre). A = pre-ACES RGB trail + feedbackAlpha, C read as colour history, exact textureLoad. Premultiplied output (`color·feedbackAlpha`) is the file's documented compositor — kept.

### Idea Card
```
SHADER: chromatic-mosaic-projector
IDENTITY: a projector that throws a Voronoi mosaic of per-cell displaced, colour-split copies of the
  photo radiating from the cursor (gravity warp when held), with tile-belt runner, click blast rings,
  temporal trail and layered premultiplied alpha.
KEEP VERBATIM: 4 params + roles (cellSize → cell count, chromatic → R/G/B split strength, voronoi →
  seed jostle amplitude, angle → projection rotation + trail decay); crossed conveyors; per-cell
  projection direction from the cursor; the three channel offsets and the wavelength step (idea
  2026-10-09); the cell-boundary diffraction fringe (idea 2026-10-09 — now ACTUALLY at the boundary);
  belt runner; blackbody per-cell tint; click blast palette; trail mix; ACES + IGN dither; layered
  alpha compositor; A packing (pre-ACES trail RGB + feedback alpha, C = colour history).
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): the Voronoi pass is a first-nearest search. Second-nearest in the same
    9-tap loop gives the exact distance to the cell BORDER — the quantity every "edge" term here was
    already trying to be — plus the seed→pixel vector, i.e. a local lenslet coordinate.
  tactic 2 (physics one step further): a lens-array projector's real artifacts: (a) transverse
    chromatic aberration is RADIAL about each lenslet's own axis (red image slightly larger than blue),
    not a uniform shift; (b) each lenslet has power: it magnifies about its own axis; (c) the gap
    between lenslets is a plain window — light passes unrefracted.
  tactic 3 (promote an intermediate): `src` (undisplaced sample) is already fetched and used only for
    alpha; the seed→pixel vector falls out of the loop for free; `dist` (cell→cursor) already exists
    and is the "throw" of that lenslet.
  tactic 6 (history): C is colour trail, exact load, unchanged.
ADD (3 native ideas; existing two kept):
  3. Lenslet lateral colour — R and B are additionally displaced ±(seed→pixel)·k, k from the existing
     per-cell chromatic strength: radial rainbow rims inside every cell, G is the axis.
  4. Lenslet throw — all three channels magnify about the cell's own seed by a power that grows with
     the cell's throw distance from the cursor axis (`dist`), so near-axis cells are flat and far
     cells act as stronger lenses.
  5. Unlensed grout window — in the true border band the source passes undisplaced (`src`), so the
     lens-array gaps read as gaps instead of the old dark seed dots; edge darkening/fade now uses the
     true border distance.
RESCUES:
  R1 true border distance (second-nearest, exact bisector distance) replaces distance-to-seed in
     edgeFade / edgeLayer / fringeEnv / fringePhase → removes the dot lattice, puts grout lines and the
     diffraction fringe on the real cell borders. DEFAULT LOOK CHANGES (measured before/after in NOTES).
  R2 bass no longer rescales/re-hashes the lattice: bass now jostles the seeds (amplitude) instead —
     same "bass pulses the mosaic" role, bounded, no relabelling.
  R3 click ring uses an aspect-corrected distance (circular on non-square canvases).
  Floor: `max(color, 0)` before the trail/ACES (measured no visible change).
FORMULA ADMISSION: no §12.2 row used (no Cauchy, no Airy/ghost, no bloom). Ideas are tactic-derived:
  lateral colour (tactic 2/5), lens power (tactic 4: second-order the throw), grout window (tactic 5).
  All consume quantities the file already computes/fetches (seed vector, dist, src).
FORBID on this file: springs/ripples beyond HEAD's click ring, IQ palette, thin-film, bloom, a second
  conveyor, any new param.
A PACKING: unchanged — pre-ACES trail RGB + feedbackAlpha in A, C read as colour history (exact
  textureLoad); writeTexture = ACES + dither, premultiplied by feedbackAlpha.
```

---------------------------------------------------------------------------------------------------
## AMENDMENTS (written after implementation; both are MEASURED design changes to the cards above)

1. **frost Idea 1 — anisotropy angle.** The card said θ = inherited `orientation`. Implemented first, the lobes were weak:
   orientation is piecewise-radial (staircase chains through the 8-neighbour max-phase pick), so cos 6θ used a wrong angle
   on the diagonals. Final: θ = FRONT NORMAL angle from the Sobel gradient of phase (exact geometry), weight faded by
   `smoothstep(3e-4, 6e-3, |∇φ|)`. Result is a hexagonal ice plate (fast corners, slow facets), not the lobed flower of the
   emulation (the emulation used the radial angle, which equals the normal only for a round front). A "normalised"
   variant exp(k·a·(cos6θ − 1)) was tried and REJECTED: attenuating only the facets drops the 5.8 px seed under the
   critical nucleus radius and the crystal collapses (anisotropy 0.5 → 7 px blob, 1.0 → nothing).
   Scatter ring cut 6 → 4 taps and the meniscus tap is skipped where rim ≈ 0 (cost 1.35/1.28/0.98 × HEAD → ≈ 1.2×).
2. **projector Idea 4 — "lenslet throw" REPLACED by "lenslet dome glint".** Ablation on the 576 px render: throw changed
   0.6% of pixels (>0.05) at default cell size and 4% at large cells (in-cell sample shifts ≤ 6 px are far below the
   source's feature scale) — invisible, so it was not an added idea. Replaced by a native lens-array artifact: each
   lenslet is a tiny dome, the lamp sits on the cursor axis, the highlight lands at lc ≈ −dir·0.22 (toward the lamp);
   one static specular dot per cell, dimmed by the file's own lamp falloff, off the grout, brightened by treble.
   Ablation: 7.6% of pixels >0.05, 1.2–1.8% >0.15. Lateral colour strength was raised 0.7 → 1.3 for the same reason
   (3% → 10–12% of pixels >0.05).
