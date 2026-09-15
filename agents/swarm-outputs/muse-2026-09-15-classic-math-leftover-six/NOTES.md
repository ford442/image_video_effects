# NOTES — Classic math / CA / reaction leftover six (2026-09-15)

## gen-rgb-diffraction
- Kept verbatim: `slitIntensity()` sinc envelope + 6-slit loop, `applySymmetry()`
  6-fold mirror, zoom_params roles (speed/freq/chromatic spread/brightness),
  per-band audio chromatic offsets, vignette, display-RGBA A packing shape.
- Idea 1 (single-slit envelope): `envSinc`/`envArg` block multiplying the fringe
  sum — grep `envSinc`.
- Idea 2 (blaze steering): `blazeVec`/`blazePhase` from `zoom_config.yz` added
  into per-slit `phase` — grep `blazePhase`. First pointer response in file.
- Floor: `acesToneMap()` added (was clamp-to-3.0, no tonemap); feedback read is
  now exact `textureLoad(dataTextureC, coord, 0)` (was filtering sample of
  rgba32float history). JSON: features `[]` → audio-reactive/mouse-driven/
  upgraded-rgba; params/updatedParams byte-exact (empty + aligned).

## gen-verlet-cloth-wind
- Kept verbatim: h/v lattice sim on 64x64, pinned top row, gravity +
  Laplacian*stiffness, mouse poke, bilinear height sample, fabric/spec/
  backlight/SSS shade chain, ACES.
- Idea 1 (gust front): `frontT` phase-delay by lattice x feeding all three noise
  octaves — grep `frontT`.
- Idea 2 (thread-tension sheen): `warpHi`/`weftHi` from `|grad h|` along lattice
  axes — grep `warpHi`.
- Floor: non-lattice pixels now write display RGBA to A every frame (HEAD wrote
  A only inside the lattice); lattice region still raw sim. Packing documented
  in header (C reads clamp into the lattice, so the display region is unread).
  JSON features → audio-reactive/mouse-driven/upgraded-rgba.

## gen-sierpinski-tetrahedron
- Kept verbatim: V/E tables, branchless-argmin chaos loop, minTrap/trapIdx/
  density chain (jewelColor + edge spec + Schlick fresnel), warp/curl/worley
  background, ACES, raw trap-state A packing.
- Idea 1 (iteration shelving): `settleIters` captured in-loop, `depthShelf`
  strata + `shelfEdge` contour lines — grep `depthShelf`.
- Idea 2 (edge current): `currentPhase`/`current` pulse riding `edge` glow,
  phased by trap distance — grep `currentPhase`.
- Floor: smoothed-audio + mouse-smooth + click state moved extraBuffer[0..5]
  (engine-reserved/FFT — stomped with audio active) → [133..138], single-writer
  (0,0) kept, both readers remapped. Ideas header added; features +upgraded-rgba.

## gen-cellular-automata-tapestry
- Kept verbatim: Gray-Scott update + 3x3 convolution, luminance feed/kill
  modulation, seasonal plasma map, mouse-inject intent, raw sim A packing,
  saved params byte-exact.
- Idea 1 (contour banding): `bandF`/`bandEdge` isochrones of B — grep `bandEdge`.
- Idea 2 (anisotropy warp): `anisoPh`/`wAx`/`wAy` axis-weight bias, weights sum
  to 1.0 — grep `anisoPh`.
- Floor: exact `textureLoad` for center + 4 Laplacian taps (HEAD filtered
  rgba32float history); ACES on the display write (HEAD had none); mouse inject
  gated on pressed (`zoom_config.w`) instead of mouseY (`zoom_config.z`) —
  stops always-on B flood. Ideas header added; features +audio-reactive/
  upgraded-rgba/mouse-driven.

## gen-audio-spirograph-julia
- Kept verbatim: `epitrochoid()` rings + ratio/harmonic tables, `julia()`
  smooth iteration, mouse→juliaC + auto drift, trailLength feedback, 5-ring
  glow+core composite, saved params byte-exact.
- Idea 1 (hypotrochoid family): `hypotrochoid()` + parity `select` on both
  `pos`/`prevPos` — grep `hypotrochoid`.
- Idea 2 (orbit-trap filaments): `juliaTrap()` min-radius + `filament`
  condensing glow — grep `filament`.
- Floor: real bass/mids/treble replace the `zoom_config.x` time-proxy audio
  (anti-pattern fix); ACES added; semantic `alphaOut` (was hardcoded 1.0);
  truthful `depthOut` (was 0.0); nearest-curve reduction converted to `select`.
  Ideas header added; features +upgraded-rgba.

## gen-belousov-zhabotinsky
- Kept verbatim: (a,b) epsilon/Da/Db/feed update, spiral+hash seed values,
  blue→orange oxidized ramp, waveFront glow, mouseDown seed, raw A packing +
  B detail channel, saved params byte-exact.
- Idea 1 (refractory tail): `refractory` dark recovery band — grep `refractory`.
- Idea 2 (pacemaker gradient): `paceR`/`epsilonField` concentric excitability —
  grep `epsilonField`.
- Floor: exact `textureLoad` for center + 4 neighbor taps (HEAD filtered
  rgba32float history ×5); bounds guard added (HEAD had none — textureLoad
  needs it); seed branch converted to `select`. Ideas header added. JSON
  already fully tagged; untouched.

## Gates
- Naga 6/6 (naga-cli 30.0.1, installed via stable cargo 1.98.1 for this batch).
- `wgsl_precommit_gate.py --files` 6/6 (bindgroup compatible, 0 extraBuffer violations).
- `audit:extrabuffer` PASS (0 new; baseline 63 triaged + 23 dynamic review unchanged).
- `audit:dead-sliders` full-tree PASS (1268 scanned, 0 new).
- Catalog: lists + manifest regenerated, 1367/1367, `verify:catalog-counts` passed, README already current.
- Jest: 689 pass / 6 fail — the 6 are the pre-existing WASM `bridge/api.js`
  resolution failures (`WASMBridge.*`, `performanceStatus`, `WebGPUCanvas`
  suites), identical count/reason on main; no TS touched in this batch.
- `SKIP_WASM_BUILD=1 npm run build` green.
- Real-GPU visual QA: external (no adapter in Cloud VM).
