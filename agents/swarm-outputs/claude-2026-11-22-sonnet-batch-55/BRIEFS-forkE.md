# BRIEFS — fork E (radial-rgb, focal-pixelate) — written BEFORE any WGSL edit

HEAD copies: `scratchpad/e/<id>_head.wgsl` (+ `_prelude.wgsl`). Harness: `agents/mr.mjs`, `SRC=img`, JSON defaults passed explicitly.

## HEAD verification done before the cards (what the user's checklist actually found)

| checklist item | radial-rgb | focal-pixelate |
|---|---|---|
| C load | none; stateless lens → a C read is NOT native, none added | none; stateless pixelator → none added |
| ACES | present, input ≥ 0 | present on `writeTexture` (`aces(color*exposure*fog)`), input ≥ 0 |
| plasmaBuffer | `plasmaBuffer[0]` bass/mids/treble all drive something visible (astig width, centre pulse, sparkle) — real | `plasmaBuffer[0].x/.z` drive block count, warp strength, exposure, alpha — real |
| dataTextureB write | `vec4(displacementMag, bass, depth, alpha)` — undocumented. Engine (`framePlan.getFeedbackCopyOrder`) copies B→C first and then A→C *last*, so a shader that writes both A and B never exposes B to anyone: **dead write** | `vec4(historyMix, depthOut, treble*0.1, fog)` — same: **dead write**; nothing in the file or the engine reads B |
| extraBuffer | none | none |
| header/JSON tags | true | header claims `shared-memory-tiling` (the `var<workgroup> tile` is declared and never touched) and `temporal-feedback` (no C read, `historyMix` is stored and read by nobody) — **both false**; JSON `features` does not carry them (JSON fine) |

**Defects proven on HEAD by varying inputs (rescues):**

* **focal-pixelate — the "big purple lens disc" is a bug.** `domainWarp()` returns `p + strength*q` with `p = uv*8.0`, i.e. an *absolute position*, but `main()` uses it as a uv *offset*: `sample_uv = floor((uv + warp*mix)*blocks)/blocks`. Outside the focus disc (mix = 1) that is `uv + 8*uv ≈ 9*uv`, clamped to 0.999 for every uv > 0.11 → the whole fringe samples the clamped right/bottom edge of the photo (the purple field and the streaks), and a 9×-minified copy of the scene lives in the top-left 11 % corner (visible as the tiny discs at HEAD 512 px). The `fr` aperture grid and the `depthSampleUV` fog sample use the same bad coordinate. Fix: use the displacement, `warp = (domainWarp(...) − uv*8)` (and centre the noise so the fringe is not biased diagonally). **This changes the default picture drastically (a real pixelated photo instead of an edge smear) — to be reported loudly.**
* **radial-rgb — the Dispersion slider is ~dead at the default and there is zero RGB split at the default.** `k1 = (p1−0.5)*2 = 0`, `k2 = 0` at the saved defaults, and the radial chromatic idea scales `k1` per channel (`k1R = k1*(1+…)`), so `uvR = uvG = uvB` exactly. Measured: dispersion 0.3 vs 0.0 at defaults → mean |Δ| 0.004/255, 0.0 % of pixels differ by > 4/255; R-vs-B edge cross-correlation best shift 0 px. A lens called "Radial RGB" shows no radial RGB at its own default.

Fixes for dead B writes + false tags are hygiene (no `Upgraded:` bump by themselves).

---

SHADER: radial-rgb
IDENTITY (one sentence): a Brown–Conrady lens on the photo — barrel/pincushion, radial chromatic fringes, tangential astigmatism, cat's-eye vignette, held pointer decentres the optical axis.
KEEP VERBATIM: 4 params and roles (k1 barrel/pincushion, k2 curvature, anamorphic stretch, dispersion → fringe/astig strength); `lensDistort` with k3 = k1·k2·0.35; R/B at different k1 (`k1R/k1B`); tangential astigmatism 3-tap smear; spectral tint; held-pointer decentred axis; cat's-eye vignette; Fresnel-style transmission alpha; ACES display RGBA; A = ACES display RGBA (unchanged).
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the per-channel model is "scale the k1 term per channel", which is a *distortion* difference, not what a real glass element does. The next-better approximation of the same operator is a per-channel *magnification* from Cauchy's n(λ) = A + B/λ² — lateral colour, present even with zero distortion.
  tactic 2 (physics one step further): a lens with distortion also has coma: off-axis point highlights are drawn as comets with the tail along the radial direction (astigmatism, already present, is the tangential partner).
  tactic 3 (promote an intermediate): `fieldVec`, `tangentDir`, `fieldR2` are already computed for the astigmatism smear; its radial partner `radialDir = normalize(fieldVec)` costs nothing; `displacementMag` is already computed and gates the sparkle.
  tactic 6 (history): nothing native — a lens has no memory. No C read.
ADD (2 native ideas):
  1. Cauchy lateral colour (§12.2F "Cauchy dispersion", E owns it) — R/G/B channel positions scaled about the optical axis by n(650/550/450 nm)/n(550 nm) with B ∝ the existing Dispersion slider; G stays at scale 1 so `baseColor`/`displacementMag` are untouched. Keeps the k1-per-channel term. Rescues the slider at the saved default (see above).
  2. Radial coma tails (domain-native, not a §12.2 row) — 3 extra taps along `radialDir` pointing inward, soft-knee on tap luma (> ~0.62), weights 1/1.8/2.6 decaying, amplitude ∝ field radius × Dispersion (the slider's existing "lens aberration strength" role, same driver as the astigmatism); bass widens it like it widens the astigmatism. Energy is added only from taps already above the knee.
FORMULA ADMISSION: idea 1 is in §12.2F; radial-rgb is a lens → family match; it consumes the channel uvs already computed (`uvR/uvG/uvB`); deleting it leaves exactly the HEAD lens; deleting the k1-per-channel term and keeping only the Cauchy magnification would no longer bend with k1 → not a reimagining. Idea 2 is not a table row and needs no ownership; it consumes `fieldVec`/`uvG` + `readTexture` taps; deleting it leaves HEAD.
FORBID on this file: springs, click fronts, IQ palettes, neon edge pop, new params, any change to `lensDistort`, the k3 coupling, the vignette constants, the alpha model; no cos⁴ (a second vignette would double up with the HEAD cat's-eye + smoothVignette).
A PACKING: ACES display RGBA (unchanged). `dataTextureB` write removed (dead; documented nowhere).

---

SHADER: focal-pixelate
IDENTITY (one sentence): a mouse-held focus disc — sharp inside, quantised into pixel blocks with a hex-bokeh defocus kernel and aperture-corner darkening outside, depth fog on top.
KEEP VERBATIM: 4 params and roles (pixel_size → block count, focus_radius, focus_softness, invert_focus), `mix_factor` selection, `blocks` mapping (`mix(500,20,p1)·(1−0.3·bass)`, 2000 in focus), `lodForBlocks`, `sampleHexBokeh` 7-tap kernel, the pixel-aperture well (Idea 1 of 2026-10-31), CoC `mix(0.2,2.6,mix_factor)` (Idea 2), depth fog `exp(−depth·(1.5+mix))`, ACES with audio exposure lift, IGN dither, semantic alpha formula, depth write.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the hex kernel weights every tap equally (0.85, centre 1.35); a real defocus kernel integrates *light*, so a bright tap outweighs a dark one and highlights turn into aperture-shaped discs. Weight = base·(1 + k·max(luma−knee,0)) with Σw normalised (energy conserved).
  tactic 2 (physics one step further): a pixelator that imitates a low-res camera sensor also has the sensor's colour-filter array: luma is resolved at the pixel, chroma only on a coarser 2×2 mosaic → "zipper" colour fringing on every block edge.
  tactic 3 (promote an intermediate): the integer cell index `floor((uv+warp·mix)·blocks)` and `sample_uv` already exist; the coarser chroma cell is `floor(cell/2)·2` of the same index. The 7 taps' RGB already sit in registers for the luma weights.
  tactic 6 (history): nothing native; the `temporal-feedback` tag was never implemented (no C read, `historyMix` goes nowhere) → tag removed, nothing invented.
ADD (2 native ideas):
  1. CFA zipper (§12.2A "CFA zipper", E owns it) — inside the pixelated fringe only (× `mix_factor`): luma stays from the block sample, chroma is taken from the 2×2 super-block grid (one extra point tap at `(floor(cell/2)·2 + 1)/blocks`), so every pair of blocks shares one hue like a Bayer camera.
  2. Highlight-weighted defocus discs (domain-native) — the 7 hex taps are weighted by `1 + 3·smoothstep(0.55, 1.0, luma)` (normalised), so bright highlights in the fringe become hexagonal bokeh discs instead of a uniform blur; the CoC and tap geometry are HEAD's.
FORMULA ADMISSION: idea 1 is in the photographic table and §12.2A names pixelate-camera/sensor sims as native; it consumes the existing cell index + `readTexture` point taps; deleting it leaves HEAD. Idea 2 is not a row; consumes the 7 taps already fetched; deleting it leaves HEAD.
FORBID on this file: springs, click fronts, IQ palettes, neon edges, new params, a C-read history (a pixelator is not a feedback effect), any change to the block mapping or the aperture well.
A PACKING: HEAD = "raw metadata (mix, 1/blocks, bass, alpha); ACES on writeTexture only". Nothing reads it (no C read in this file; the engine's C is just "last slot's A", so a downstream slot that samples C would read focus metadata as colour). **Changed to display RGBA (ACES tone + alpha, same value as `writeTexture`) — the §8 packing, and I say so here. `dataTextureB` write removed (dead; B→C copy is overwritten by A). Open call for the user (rescue, default A content differs; nothing in this file or the engine consumes either).**
