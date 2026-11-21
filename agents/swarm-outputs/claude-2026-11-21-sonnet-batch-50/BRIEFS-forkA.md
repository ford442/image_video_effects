# BRIEFS — fork A (sonnet/batch-50): gen-alpha-aurora, aurora-borealis-loom

Written BEFORE any WGSL edit. Baseline = worktree file at start (prelude-migrated, pixel-identical to origin/main); copies in the scratch dir `.../scratchpad/a/<id>_head.wgsl`.

HEAD verification done before the cards (SwiftShader, mr.mjs, saved JSON defaults):

- **loom, defect 1 — the conveyor never wraps.** `uv.x += warpT*curtainFlow*0.35` is unbounded while the five curtains sit at fixed x in [0.15, 0.87] and the ion streaks/nodes at fixed x in [0,1). Single-frame renders at T0 = 0 / 3 / 8 / 30 s: five coloured curtains / two / **none / none**. After ~6 s (≈3.6 s at max Curtain Flow) the frame is stars + the fell arc only; it never recovers.
- **loom, defect 2 — the HDR-trail feedback is bistable.** `A` stores `acesToneMap(...)` (display, ≤1) but C is read back as HDR energy: `fbCol = col + prev*0.85` with the next ACES inside the loop (gain 0.85·1.1 vs an ACES toe slope > 1 above x≈0.1). Frames 1 / 4 / 12 / 40: meanL 0.081 / 0.526 / 0.741 / 0.740, stdL 0.124 → 0.026: the whole frame ratchets to a flat grey wash within ~0.2 s at 60 fps. The HEAD comment itself says "HDR trails".
- **alpha-aurora, defect 1 — mouse Y is inverted.** `altitudeShift = (0.5 - mouse.y)*0.4` with `mouse.y = 0` at the TOP: mouse at the top (y = 0.1) moves the bands DOWN the screen by 0.16 (verified: bands span y≈0.45–0.9 at mouse-top vs 0.3–0.6 at centre). Comment says "Y controls aurora altitude".
- **alpha-aurora, defect 2 — the bass envelope has no state.** `prevBass = extraBuffer[133]` but `writeExtraBuffer` (src/renderer/webgpu/audioDepth.ts:51) re-uploads all 256 floats every frame (`EXTRA_FLOATS = 256`), so 133 is always 0 on entry: `bass_env(0, bass, 0.15, 0.02)` = 0.15·bass. Every `smoothBass` use (audioBoost, band speed, band width) responds at 0.15× its designed strength.
- **both — fake chromatic aberration.** `vec3(r + caStr, g, b − caStr·0.5)` adds a constant to red and subtracts from blue everywhere (alpha-aurora after ACES → negative blue written to the output; loom before ACES → negative into ACES). Clamped, not redesigned.

---

## SHADER: gen-alpha-aurora

**IDENTITY (one sentence):** four spectral aurora bands (curl-noise-deformed Gaussian curtains with FBM structure, vertical rays, a green lower hem) over a faint star field, drifting with the audio and the mouse.

**KEEP VERBATIM:** 4 saved params and their roles (band_speed → drift speed, color_temperature → hue/temperature, band_density → density, atmospheric_glow → glow); the 4-band loop, `curlNoise` deformation, Gaussian band profile and width law, `dwfbm3` detail mask, `spectralColor` wheel, ripple boost (u.ripples age ≤ 3 s), `atmoFalloff`, "curtain rays along the curl" and "greener lower border" (both shipped Ideas), star field, the 0.15 persistence mix with exact C load, soft tone map, depth pass-through; **A = pre-ACES display RGBA** (clamped soft-mapped colour + band alpha) read back as colour — consistent, unchanged; ACES only on `writeTexture`.

**MECHANISM INTERROGATION (§12.1):**
- *Tactic 2 — physics one step further.* The aurora's colour is not a hue wheel: it is emission altitude. 557.7 nm atomic oxygen (≈100–150 km) is the green body; 630.0 nm O(¹D) has a 110 s lifetime so it survives only high up (≥ 200 km) as a diffuse red crown; N₂ first-negative 427.8 nm blue/violet and the N₂ first-positive pink band appear below the green hem, and harder (more energetic) precipitation reaches lower, so the pink skirt grows with the substorm (bass). HEAD has the green lower hem but nothing above or below it.
- *Tactic 2 again — the atmosphere between the viewer and the sky.* Light from a low-elevation curtain crosses several airmasses; the blue is extinguished first, so low aurora and stars go warm and dim near the horizon.
- *Tactic 3 — promote an intermediate.* `bandY/bandWidth` (signed position inside the band; negative = up the rays) is already computed for the Gaussian and hem; `rayCol`'s cell index is implicit in `uv.x*46 + curl.x*2`; `uv.y` is already the elevation proxy (`atmoFalloff` uses it).
- *Tactic 6 — history.* C is colour history with weight ≤ 0.14: no extra continuity is owed; no change.
- *Tactic 7 — direction.* Rays are vertical and static; real "flaming" aurora sends brightness packets UP along the rays.

**ADD (3 native ideas):**
1. **Emission-altitude layering** — a diffuse 630 nm red crown lobe centred ≈1.4 band-widths above each band centre (`bandY < 0`), and a narrow N₂ pink-magenta skirt just below the green hem (`bandY ≈ +1.6·width`) whose strength follows precipitation hardness (bass, with a small idle floor). Additive, small amplitude, structured by the existing detail mask and rays; the existing hue wheel stays the band body colour. Native: this is why real green curtains have red tops and pink bottoms.
2. **Beer–Lambert horizon extinction (§12.2F)** — per-channel transmission `exp(−τ_rgb·X)`, `X = 1/(cos z + 0.025·exp(−11·cos z))` (Young airmass) with zenith angle `z` from screen y (top = zenith). Applied to band colour, hem, the two new fringes and the stars. τ = (0.06, 0.11, 0.22): low bands and horizon stars go warm and dim, the sky near the top is untouched. `atmoFalloff` is kept as is (it is the geometric falloff; this is the spectral one).
3. **Flaming-aurora ray pulses** — brightness packets that travel UP each existing ray: `flame = 0.55 + 0.45·sin(k·bandY/width + ω·t + 2π·hash(rayId, band))` multiplies the existing `rayAmp`. Per-ray phase from the ray cell; rays themselves unchanged.

**FORMULA ADMISSION (§12.4):** Beer–Lambert is a §12.2F row owned by this file (COMMON.md). It consumes `uv.y` and the already-computed band colours; deleting it leaves the same aurora, keeping only it is not an aurora → additive. Ideas 1 and 3 are not table rows (domain mechanisms). No two rows are used.

**FORBID on this file:** springs, new click overlays (existing ripple boost stays), IQ palette, extra bands, new params, curl/vorticity extension, frame-hash strobing.

**RESCUES (reported loudly):** (a) mouse-Y altitude inverted → `(mouse.y − 0.5)·0.4` (mouse up = aurora up); (b) dead `extraBuffer[133]` envelope → `smoothBass = bass` and the reader/writer removed (audio response ×6.7 under music, silent default unchanged); (c) output chromatic tint clamped ≥ 0.

**A PACKING:** unchanged — pre-ACES display RGBA (colour after the soft map, band-density alpha), read back as colour; ACES only on `writeTexture`.

---

## SHADER: aurora-borealis-loom

**IDENTITY (one sentence):** aurora curtains as light threaded through a celestial loom's cloth — a weft/warp lattice that glows where the curtains are, a fell line with reed beat-up, slub yarn pools and pulsating patches.

**KEEP VERBATIM:** 4 params and roles (weave-density → thread count, hue-speed, ionization → ion streaks/nodes, curtain-flow → conveyor/fell speed); `auroraCurtain` waves + vFade; the five curtains' positions/widths/hue law; `weftPattern`/`warpPattern`; Idea 1 (fell line + reed beat-up), Idea 2 (slub yarn + light pools), Idea 3 (pulsating patches); ion streaks, ionization nodes, star field, mouse pull, bass swell, atmospheric noise, advected HDR trails (same `flowDir`/`histCoord` and `0.85 + 0.03·bass` decay), semantic alpha, depth.

**MECHANISM INTERROGATION (§12.1):**
- *Tactic 1 — deepen the kernel.* HEAD's cloth is `max(weft, warp·0.7)` — a lattice of lines, not an interlacement. A woven cloth is the next-better approximation of the same operator: at every crossing exactly one thread is over and the other under, alternating (plain weave = checkerboard parity of `row + column`). `floor(uv.y·density)` (row) and `floor(uv.x·warpDensity)` (column) are already computed for the slub lanes.
- *Tactic 5 — artifacts of the real device (loom).* Fell, reed beat-up, slubs are on the card. Not yet present: **selvedge** (the self-finished, doubled/tighter edge of a cloth where the weft turns back), **reed marks**, **floats**, **broken ends**, **warp tension**. The selvedge is the one that is a property of each *curtain-as-cloth-strip* edge, and `auroraCurtain` already computes the signed distance to that edge (`curtainEdge`) and throws it away (tactic 3).
- *Tactic 6 — history.* C is read as HDR colour for the advected trail, but A stores post-ACES display → packing lie (defect 2). Fix is a packing statement, not a new idea.

**ADD (2 native ideas):**
1. **Plain-weave interlacement** — over/under parity per crossing (`parity = (row + col) & 1`): at a crossing the thread that is "under" is occluded by the other (`weft·(1 − warpMask·underWeft·0.6)` and vice-versa), so the lattice reads as thread passing over and under instead of a flat grid. Uses the existing `weft`, `warp`, slub masks, row/col indices; no new noise.
2. **Selvedge hem on every curtain** — `auroraCurtain` also returns a thin ridge at `|curtainEdge| ≈ 0.8·width` (the doubled outer warp ends), brightest where the curtain is strongest; added as lit thread in the curtain's colour at ~0.35 of the curtain glow. The curtains stop being soft glows and read as woven ribbons with a finished edge.

**FORMULA ADMISSION:** no §12.2 rows used (both ideas are loom vocabulary, not table formulae) → no cross-fork claim needed. Both operate on quantities the file already computes; deleting either leaves exactly the HEAD loom.

**FORBID on this file:** springs, click shockwaves, IQ palette, ferrofluid/hologram nouns, a second fell/tear system, new params.

**RESCUES (reported loudly):**
- **R1 — conveyor wrap.** Curtain, ion-streak and node x positions use `fract(uv.x)` (all three live inside [0.09, 0.93] so there is no seam artefact); the weave functions keep the unbounded `uv.x` (their `fract` is already periodic). Curtains now loop forever instead of vanishing at ~6 s.
- **R2 — HDR trail packing.** A stores the RAW HDR value (pre-ACES, pre-CA); the trail is peak-hold `max(col, prev·decay)` (decay unchanged `0.85 + 0.03·bass`) instead of the runaway sum `col + prev·decay`; ACES on `writeTexture` only. Static content now converges to its own frame-1 look instead of the grey wash; moving content still leaves the advected trail.
- **R3 — CA tint** applied to the displayed value only, clamped ≥ 0.

**A PACKING:** CHANGED (fixing a packing lie, as §8 requires saying): `raw HDR RGB (pre-ACES, pre-CA) + semantic alpha; ACES on writeTexture only` (HEAD: post-ACES display RGBA read back as HDR).
