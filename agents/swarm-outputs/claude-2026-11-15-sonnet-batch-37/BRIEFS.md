# BRIEFS — sonnet/batch-37 (cloud / glass / ribbon / jelly / kaleido ten)

Written by the coordinator BEFORE any WGSL edit (docs/SHADER_UPGRADE_BATCH.md §2, §9, §12.7). Base: origin/main 7f6ce638 + 8577b989 (header-only prelude migration of rainbow-cloud + gen-solar-wind-ribbons; no `Upgraded:` bump). **HEAD for every comparison = 8577b989.**

Selection rule: the ten smallest un-claimed shaders by line count (287 / 147 / 145×3 / 144×2 / 143×3). It is **not** a theme batch, so the usual dedupe risk (one overlay stamped across the batch) is handled by giving every file ideas in its own vocabulary and capping every §12.2 row at one file (see Row budget).

First-pass vs second-pass (grep `Ideas:` at HEAD): `gen-ethereal-cyber-aurora-mantis-shrine` (no `Upgraded:`/`Ideas:` — a Jules landing), `rainbow-cloud` (Upgraded 2026-05-31 with **no** `Ideas:` line = hygiene-only history) are **first-pass**. The other eight already carry `Ideas:`; their cards ADD to the existing line and must not remove or duplicate earlier ideas.

Forks: **A** volumetric/raymarch first-pass (aurora-mantis-shrine, rainbow-cloud) · **B** photo-plane optics/heat (kaleido-scope-grokcf1, liquid-chrome-ripple, molten-glass) · **C** 2D line/lattice generative (gen-solar-wind-ribbons, gen-emergent-calligraphic-weave, hybrid-cyber-organic) · **D** cell-grid generative with history (gen-chromatic-oracle-jelly, gen-liquid-cathedral-dream).

Every claim below marked *(verify)* was read from the WGSL, not measured. Forks must confirm it with a HEAD render before acting on it and write what they found in their NOTES file; if a hypothesis is false, drop the rescue and say so.

---

## 1. gen-ethereal-cyber-aurora-mantis-shrine  — FIRST PASS (fork A)

```
SHADER: gen-ethereal-cyber-aurora-mantis-shrine
IDENTITY: a raymarched shrine — a hovering liquid-chrome mantis over an auroral-plasma lotus, a cyan
  pulsing heart with filaments, ground mist, mouse-orbit camera, click-held ripple warp.
KEEP VERBATIM: map() geometry (mantis capsules/head/arms, lotus petal-fold loop, heart + filaments, mist
  plane), material ids 1–4, the 4 saved params and their ROLES (mantis-scale RAW 0.5–2, lotus-complexity
  RAW 1–5, mist-density, core-pulse-intensity), mouse orbit camera, held-click warp, chrome/auroral/cyan
  colour identities, the under-relaxed 100-step marcher, the palette() hue clock on the lotus.
MECHANISM INTERROGATION (§12.1):
  t2 physics: a chrome body mirrors its surroundings; HEAD's chrome = spec + fresnel only, and the sky is a
     faint grey noise — the shrine is called "aurora" yet there is no aurora in the frame.
  t3 promoted intermediate: `rd` and the reflected ray `reflect(rd,n)` are computed/computable per hit and
     thrown away; `res.y`-mist density already accumulates along the ray.
  t6 history: none (HEAD writes no A). The ONLY C read is a bug (below).
RESCUES (hypotheses — verify at HEAD):
  R1 `audio_sample = textureLoad(dataTextureC,(0,0)).x` is used as "audio" in two places but nothing ever
     writes A, so it is a dead constant 0 → heart/filament pulse never follows sound. Use `plasmaBuffer[0].x`.
  R2 no `dataTextureA` store, alpha hard `1.0`, no ACES (gamma `pow(0.4545)` only) → ACES on display, A = the
     display RGBA, alpha semantic (coverage: hit surfaces 1, sky/mist < 1).
  R3 `uv=(fragCoord-0.5res)/res.y` has +y DOWN while the camera `u_cam` is world-up → the picture may be
     upside-down (mantis "hovers above" the lotus but may render below it). Render HEAD first; fix only if
     confirmed, and say so in the NOTES (it changes the composition).
  R4 camera orbit `rot(-mouse_uv.y*1.5)` can lift `ro.y` above the mist plane (`mist_d = 2 - p.y`) → camera inside
     the mist SDF (flat/white frame?). Test with mouse at the top edge; clamp pitch only if it breaks.
  R5 `mp = q / m_scale` — saved min is 0.5 so no div-by-zero, but guard anyway.
ADD (3, optional 4th):
  1. Aurora curtain sky — fold the ray direction into hanging curtains (angular bands × altitude falloff ×
     slow warp) added to the existing `bg_noise` nebula for rays that miss; coloured with the file's own
     `palette()` hue clock so it reads as the same aurora as the lotus. (native: the name promises it)
  2. Chrome environment reflection — the mantis (mat 2) samples the SAME sky function at `reflect(rd,n)`, so the
     chrome visibly carries the curtains; lotus fresnel rim picks it up weakly. (energy/physics, same noun)
  3. Heartbeat ring along the filaments — a pulse train expanding from the heart through the emissive filaments,
     amplitude = core-pulse-intensity × (1 + bass), replacing the dead C(0,0) read. (native)
  4. (optional) step-count AO (§12.2E, E2 snippet) on mantis/lotus hits — only if frame cost stays ≤ 1.3×.
FORBID on this file: new creatures/geometry, scanline/glitch costume, springs, a second camera, changing the
  mantis/lotus silhouettes.
A PACKING: ACES display RGBA (HEAD stored nothing; C is never read for history).
```

## 2. rainbow-cloud  — FIRST PASS (fork A)

```
SHADER: rainbow-cloud
IDENTITY: an iridescent nacreous cloud veil laid over the photo — 10-slice 3D-fbm volume, warm god rays,
  rainbow cosine-palette colouring, bass turbulence, mouse scatter, depth-aware haze, ACES.
KEEP VERBATIM: fbm3d volume and the 10 orthographic march slices, `density = max(d-0.35,0)*2.5`,
  transmittance/scatter accumulation, the iridColor cos palette clocked by density/t/time/mids, bass
  turbulence, mouseScatter, depthFactor + atmFog, ACES(×1.1), alpha formula, the 4-field A pack
  (cloudDensity, iridescence, depthFactor, alpha — nothing reads C; keep it and say so), 4 params
  (cloud_scale, drift_speed, density, iridescence).
MECHANISM INTERROGATION:
  t2 physics: cloud scattering is forward-peaked toward the sun. HEAD's `cosTheta = dot(rd, lightDir)` uses the
     CONSTANT orthographic `rd=(0,0,1)`, so `miePhase` is one constant for the whole frame (verify) — the
     "mie-scattering" tag does nothing spatially.
  t3 promoted intermediate: `density` and `lightAtten = exp(-density*3)` exist per slice, but `lightAtten` is
     purely local — there is no step toward the sun, so no self-shadowing: cores are as bright as edges.
  t6 history: none.
ADD (3):
  1. Henyey–Greenstein forward lobe with a per-pixel view angle (§12.2F) — derive a view direction FOR THE PHASE
     ONLY from uv (sampling stays orthographic, so the HEAD look/parallax is unchanged), place the sun at the
     projection of `lightDir`; the lobe lights cloud edges toward the sun, mixed over HEAD's constant phase.
  2. Beer–Powder self-shadow tap — one extra (cheaper, 2-octave) density tap toward `lightDir` per slice;
     powder term `1-exp(-2·density)` gives dark thin edges away from the sun / bright silver-lined edges
     toward it. Keep total cost ≤ 1.3× (halve the shadow-tap octaves or skip alternate slices before touching
     the 10-slice count).
  3. Corona irisation — hue offset by angular distance to the sun (coloured fringes in concentric bands around
     the sun, strongest in thin cloud) riding the existing `iridescence` slider. (native: nacreous colour is
     diffraction near the sun)
FORBID: perspective sampling/parallax, springs, click shockwaves, new params, changing 0.35 threshold / ACES ×1.1.
A PACKING: unchanged 4-field param pack (nothing reads it; documented as such). ACES on writeTexture.
```

## 3. gen-emergent-calligraphic-weave  — 2nd+ pass (fork C)

```
SHADER: gen-emergent-calligraphic-weave
IDENTITY: up to ten sine-flow calligraphic ink strokes woven over/under one another on dark paper, with
  chromatic bloom, HDR history and click ink rings.
KEEP VERBATIM: lane/phase/curve construction, nib width from derivative, ALL earlier ideas (over/under weave
  occlusion, dry-brush starvation, ink pooling, over-strand cast shadow), hairline halos, palette/hueMoment,
  click ink rings, HDR history mix 0.05+audio.x*0.07, ACES on writeTexture only, A = raw HDR display RGBA,
  4 params (strokeDensity, flowSpeed, inkWidth, chromaticBloom).
MECHANISM INTERROGATION:
  t5 device artefact: ink on paper — pigment gathers at the wet edge (coffee-ring) and wicks into paper fibres;
     HEAD has neither (the strokes are clean Gaussians on a flat hash-noise paper).
  t3 promoted: `d` (distance to centre-line) and `nib` per stroke are already computed.
  t7 direction: paper fibres run in their own direction, independent of the stroke direction.
ADD (2):
  1. Wet-edge pigment ring (§12.2C wet-edge accumulation) — pigment density peaks at |d|≈nib and thins in the
     middle of a wet stroke; must read differently from the existing hairline (outside, 1.8·nib) and the lane-turn
     pool.
  2. Paper-fibre wicking (§12.2C paper granulation) — anisotropic fibre noise (stretched ~12:1 along a fixed
     fibre direction) lets ink feather into the paper along fibres just outside the stroke and granulates pigment
     inside it.
RESCUE (verify): the over/under test is a hard `weaveZ[j] > weaveZ[i]`, so crossings flip with an aliased seam;
  soften with a smoothstep over Δz (a quality fix, not an idea).
FORBID: new stroke types, new palette, springs, flicker, new params.
A PACKING: raw HDR display RGBA (unchanged).
```

## 4. kaleido-scope-grokcf1  — 2nd pass (fork B)

```
SHADER: kaleido-scope-grokcf1
IDENTITY: the photo seen through a mirror-chamber kaleidoscope — N-fold mirrored wedges around a spring-
  followed pointer, prism R/B split, oil-slick tint, seam/grout/conveyor/ripple overlays, history trail.
KEEP VERBATIM: fold/spin math, inner counter-rotating wedge and seamBeat (earlier ideas 1–2), sample_uv /
  prism_shift / reflect add, grout/conveyor/packets/iris, the A texel (0,0) state scheme (env in r, spring in
  gb, vel in a) exactly as HEAD, trail decay 0.88, 4 params (segments, speed/Rotation, zoom, offset/Ring Offset).
MECHANISM INTERROGATION:
  t8 energy accounting: every mirror bounce loses light (aluminium ≈ 90 % per reflection, slightly blue-
     cast). HEAD shows every wedge at full brightness regardless of its reflection order.
  t3 promoted intermediate: `floor(angle/segment_angle)` (the wedge index = reflection order) is computed inside
     the fold and discarded.
  t2 physics: a kaleidoscope is viewed through an eyepiece lens — real barrel distortion and a hard field stop.
ADD (2):
  1. Mirror-bounce attenuation + cool cast — order = min(k, n−k) of the wedge index on the integer segment count;
     `0.9^order` (+ slight (0.92,0.97,1.0)^order cast); must be symmetric across the ±π branch cut. (native)
  2. Eyepiece barrel — Brown–Conrady `r' = r(1 + k1 r²)` on the radial coordinate of the object sample (§12.2B),
     k1 a literal (do not steal a slider role), soft field-stop darkening at the extreme corners. If it is
     < a few % of pixels at default sliders, strengthen within identity or replace per COMMON rule 15.
RESCUES (verify): (a) iris ripple ring uses `distance(uv, rp.xy)` (not aspect-corrected → elliptical ring);
  (b) JSON carries `upgraded-rgba` but the WGSL has NO ACES — tone-map ONLY the added emissive terms
  (seam/slick/grout/conveyor/packets/iris) so the photo base keeps its levels; (c) fixed `dt = 0.016` spring
  (leave unless trivial — there is no free A channel for a time stamp).
FORBID: new overlays (sparkles, neon edges), changing the A-state layout, new params.
A PACKING: display RGBA + state texel at (0,0) (unchanged).
```

## 5. liquid-chrome-ripple  — 2nd pass (fork B)

```
SHADER: liquid-chrome-ripple
IDENTITY: the photo refracted through a rippling liquid-chrome sheet — pointer-centred rings + three plane
  waves, click ripples, Schlick fresnel, key/fill speculars, thin-film environment, caustic, crest beads +
  trough meniscus, advected afterimage.
KEEP VERBATIM: waveHeight composition and constants, click-ripple loop, normal/refraction/dispersion,
  Schlick, specKey/Fill, caustic + thinFilm, crest/trough (earlier ideas), advected history persistence,
  4 params (flow, distort, metal, freq), A = HDR display history, ACES on writeTexture only.
MECHANISM INTERROGATION:
  t2 physics: capillary-gravity ripples are dispersive (ω² = gk + σk³/ρ): short waves outrun long ones, so rings
     spread into trains. HEAD uses ONE phase speed `3.5+flow*5` for every ring.
  t3 promoted: `reflect(-viewDir, normal)` is never computed; `environment` is a constant mix of dark blue and
     thinFilm, independent of the normal — yet "what the chrome mirrors" is the whole look of liquid chrome.
ADD (2):
  1. Capillary dispersion (§12.2D deep-water dispersion) — a second ring component at ~2× wavenumber running
     faster (ω ∝ k^1.5 in the capillary regime), amplitude ~0.35 of the primary, on BOTH the pointer ring in
     waveHeight and the click-ripple loop (analytic slope in clickSlope).
  2. Studio-horizon environment — reflection vector → ground/horizon/sky split with a bright horizon band and one
     soft-box strip, deformed by the ripples; `thinFilm` stays as the tint mixed into it; weight = fresnel ×
     metalness (so metal=0 keeps HEAD's look).
FORBID: a solver, neon edges, springs, replacing waveHeight, new params.
A PACKING: unchanged (HDR display history, ACES on writeTexture).
```

## 6. gen-solar-wind-ribbons  — 2nd pass (fork C)

```
SHADER: gen-solar-wind-ribbons
IDENTITY: 3–14 streaming ribbons of magnetised plasma (Parker-lagged centre-lines, Kelvin–Helmholtz
  scalloped edges) glowing as aurora curtains.
KEEP VERBATIM: ribbonCentre (+ Parker lag), KH scallop offset, min-distance-to-polyline Gaussian mask,
  per-ribbon hue/width, fbm detail, horizontal streak, ACES on display, A = ACES display RGBA,
  4 params (ribbon_count, twist, speed, glow).
MECHANISM INTERROGATION:
  t3 promoted intermediate: the inner loop keeps only `minDist`; the ALONG-ribbon coordinate `s` of the nearest
     sample and the signed ACROSS offset are exactly what a ribbon texture needs and are thrown away.
  t7 direction: `detail = fbm(p*5)` is isotropic in screen space; plasma fine structure is field-aligned.
ADD (2):
  1. Field-aligned flux-tube striations — track `bestS` + signed side at the nearest sample and modulate the
     ribbon with thin filaments running ALONG it (noise of (bestS·~55 − t, side·~3)), layered over `detail`.
  2. Reconnection flare at ribbon crossings — pairwise mask overlap `0.5·(S² − Σm²)` (S = Σm) → a white-hot core
     where two sheets cross; additive, clamped. (native to current sheets)
FORBID: particles, ripple shockwaves, springs, changing ribbonCentre/KH math, new palette, new params.
A PACKING: ACES display RGBA (unchanged). Cost must stay ≤ 1.3× (it is 14×64×2 ribbonCentre calls/pixel already).
```

## 7. hybrid-cyber-organic  — 2nd pass (fork C)

```
SHADER: hybrid-cyber-organic
IDENTITY: a hex-cell neon circuit board that grows organically — occupied cells light their hex outline
  cyan→green with tendrils, glow and a pulse.
KEEP VERBATIM: the two-lattice nearest-centre hex trick, growth noise + photo-luma seed + exact-C persistence
  (earlier ideas), isHexLine, tendrils, palette glow, pulse, alpha, 4 params (circuit_density, growth, glow,
  chaos), A = raw occupancy r / tendrils g / glow b (a = 1.0 as HEAD), ACES on writeTexture only.
MECHANISM INTERROGATION:
  t3 promoted intermediate: `localUV` identifies which hex is nearest but `cellId = floor(p / r)` is the
     RECTANGULAR lattice cell, so the two interleaved hex lattices share ids (verify) while the true centre
     `p − localUV` is unused.
  t6 history: C already holds every hex's occupancy at every pixel → a neighbour's occupancy is one exact load
     at that neighbour's centre pixel (no new state).
ADD (2):
  1. Neighbour-driven wavefront growth — gather occupancy at the 6 neighbouring hex centres from exact C; an
     unoccupied cell catches from an occupied neighbour (spread = max(neigh)·0.9 gated by a slow per-cell hash),
     so growth crawls across the lattice from the seeds. Bounded by the 0.9^hops falloff and HEAD's decay.
  2. Solder-via pads at hex vertices — round pad where the two nearest edge distances both vanish
     (`1 − smoothstep(0, w, max(dE1, dE2))`), lit on occupied cells and brighter at junctions (more occupied
     neighbours). (native PCB node)
RESCUE (verify, then act): derive the hash/hue/pulse/growth `cellId` from the true hex centre. It changes which
  cells light — report the default-look change (meanL/stdL HEAD→new).
FORBID: vines/new motif, springs, ripples, new params, runaway fill (the lattice must still show unlit cells).
A PACKING: raw occupancy in A.r (unchanged); ACES on writeTexture only.
```

## 8. gen-chromatic-oracle-jelly  — 3rd pass (fork D)

```
SHADER: gen-chromatic-oracle-jelly
IDENTITY: a drifting grid of luminous oracle jellyfish — domed bells with a watching eye, sigil, trailing
  tentacles and frills, over HDR-ish history.
KEEP VERBATIM: every earlier idea (pulse-swim, pointer-tracking blinking eye, tentacle wake, click startle,
  audio pupil dilation, synapse sparks, bell frills), bell/eye/tentacle masks and their radii, palette, history
  mix, ACES, 4 params (swarm_density, drift_speed, tentacle_curl, oracle_chroma), A = ACES display RGBA read
  back as colour history (documented; leave).
MECHANISM INTERROGATION:
  t5 device (the animal): a zoologist names radial canals, oral arms, gonads, marginal bulbs, mesoglea
     translucency. HEAD's bell is a uniformly filled dome with no internal anatomy.
  t3 promoted: `contraction` and `swimPhase` already exist per cell — the signal that should travel through
     the nerve net.
ADD (2):
  1. Radial canals with excitation wave — 6–8 thin canals from the eye centre to the rim (angular comb), their
     brightness travelling rim-ward on each swim contraction.
  2. Oral arms — four frilled ribbons hanging below the eye along the bell axis, undulating out of phase with
     the tentacles and shortening on contraction (thicker curtains between the thin tentacles).
FORBID: new creature types, fish, springs, changing existing mask radii except to host the new anatomy.
A PACKING: ACES display RGBA (unchanged).
```

## 9. gen-liquid-cathedral-dream  — 3rd pass (fork D)

```
SHADER: gen-liquid-cathedral-dream
IDENTITY: a melting stained-glass cathedral — arches, spires, rose-tracery windows, lead cames, drips, god-ray
  shafts, dichroic hue shift, over history.
KEEP VERBATIM: arch/spire/window/rose/floorCaustic, earlier ideas (lead cames, molten drips, god-ray shafts,
  dichroic shift), palette, history mix, ACES, 4 params (spire-density, melt-speed, refraction, stained-hue),
  A = ACES display RGBA read back as melt-offset history.
MECHANISM INTERROGATION:
  t5 device: antique cathedral glass has seeds (trapped bubbles) and reamy striations; a lit nave shows Tyndall
     dust in the shafts. HEAD's panes are clean flat colour and the shafts are empty.
  t3 promoted: `shaft` / `shaftBand` are already per-pixel and say exactly where the light volume is.
ADD (2):
  1. Seeded antique glass — tiny bubbles (hash lattice, two scales) that catch the shaft light as bright
     pinpoints, plus reamy striations along the melt direction modulating pane luminance (folded into `window`).
  2. Tyndall dust motes in the shafts — sparse soft-Gaussian motes drifting upward, visible only inside
     `shaftBand` (continuous drift — no per-frame hash strobing).
FORBID: new architecture, replacing windows, springs, strobing.
A PACKING: ACES display RGBA (unchanged).
```

## 10. molten-glass  — 2nd pass (fork B)

```
SHADER: molten-glass
IDENTITY: the photo seen through glass heated under the pointer — a heat field (A.r) that convects upward,
  cools, refracts, tints orange, with Fresnel/Beer–Lambert transmission, cooling crust and a drip thread.
KEEP VERBATIM: the whole heat solver (advect / decay / mouse inject / click fronts / convectionPacket), refraction
  offsets, Fresnel + thickness + Beer–Lambert, gloss, crust + drip (earlier ideas), 4 params (heat-radius,
  viscosity, refraction, cooling-rate), A = raw heat in A.r (C.r is heat), ACES on writeTexture only.
MECHANISM INTERROGATION:
  t2 physics: hot glass EMITS (red → orange → yellow-white blackbody glow). HEAD only tints the transmitted
     photo, so a hot blob over a dark photo is dark.
  t8 energy: emission ∝ strongly super-linear in temperature (≈T⁴) — it must switch on only in the hottest part
     of the heat field.
  t3 promoted: the `crust` cooling-front mask exists; real cooling glass crazes (thermal-stress cracks) exactly
     there.
ADD (2):
  1. Incandescence (§12.2F blackbody) — emissive colour ramp from heat, smoothstep(0.3,1.0,heat)^1.5 × (0.55 +
     bass·0.2), added before ACES; distinct from `gloss` and the `drip`.
  2. Cooling craquelure — Voronoi-edge crack hairlines (≈20 cells across) inside `crust`, a thin bright edge on
     the dark line, healing where heat returns. (native)
FORBID: a new solver, ripple shockwaves beyond the existing click fronts, springs, new params.
A PACKING: raw heat in A.r (unchanged); ACES on writeTexture only. Visibility is pointer-local — measure in the
  heat region and say which.
```

---

## Row budget (de-dup across the batch; §12.4)

No §12.2 row on more than one file in this batch. Rows used: Henyey–Greenstein (rainbow-cloud) · step-count AO, optional (aurora-mantis) · paper granulation + wet-edge accumulation (calligraphic-weave) · Brown–Conrady radial (kaleido) · deep-water dispersion (liquid-chrome-ripple) · blackbody (molten-glass). Everything else is native to its own file. `weaveZ` smoothing, hex-centre id, aspect-corrected iris are rescues, not ideas.
