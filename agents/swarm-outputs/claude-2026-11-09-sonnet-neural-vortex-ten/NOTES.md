# NOTES — sonnet/neural-vortex-ten (pointer-led fields & feedback, 10 shaders)

Cards: `BRIEFS.md` (committed in `b765c43e`, before any idea edit; three implementation-time amendments are appended to it).
Harness: SwiftShader WebGPU single-dispatch render harness (scratchpad; rgba8 source photo, r32float depth with a near blob,
A→C copy through an rgba16float round-trip each frame like a 16-bit tier, `extraBuffer` re-uploaded every frame like the
engine, scripted pointer path / hold / three clicks / audio). **Structural and PNG evidence only — no real-GPU visual QA is
claimed.** Sweep: 10 shaders × {default, stress 1,1,1,1, zero 0,0,0,0 + silent, 640×384, flat depth + still pointer,
400-frame run} × HEAD/new = 120 renders, **0 NaN / 0 Inf in `writeTexture` and in A**, 0 harness/validation errors.

Plumbing (own commit `ece93c36`, no `Upgraded:` bump): 7 files migrated to `#include "_prelude.wgsl"` with
`scripts/migrate_to_prelude.py --naga` (V1–V5 green).

| § | id | Ideas added (grep `Idea n`) | floor / rescue | meanL default / stress, HEAD → new |
|---|---|---|---|---|
| 1 | neural-nexus | 1 axon fibres + action-potential packets · 2 spike-rate afterglow | – | .5122→.5152 / .4869→.4946 |
| 2 | conv-reaction-convolution | 1 isotropic 9-pt Laplacian of the stored chemicals · 2 luma-painted Pearson regime | – | .3597→.3736 / .4415→.4572 |
| 3 | fluid-grid-rgba-fluid | 1 tangential stirring · 2 vorticity confinement · 3 vorticity-spun tiles | exact manual bilinear for C (equivalence proven: both ideas zeroed ⇒ HEAD to 4 digits, identical A extrema); semantic grid-line alpha | .4278→.4260 / .4503→.4492 |
| 4 | gen-chromatic-vortex | 4 depth-sheared twist · 5 azimuthal comet trails | exact bilinear C helper | .4803→.4780 / .6197→.6116 |
| 5 | mouse-neural-dreamscape | 1 impulse packets on synapses · 2 Hebbian trace | filtering read of C → exact `textureLoad` | .2780→.2882 / .3917→.4557 |
| 6 | spectral-distortion | 1 Cauchy-ordered dispersion · 2 per-channel spectral lag | – | .4316→.4315 / .4341→.4345 |
| 7 | scan-slice | 1 slit-scan stretch · 2 per-channel slit aperture | – | .4258→.4276 / .3906→.3924 |
| 8 | chroma-vortex | 1 counter-rotating third vortex · 2 rotation-phase hue | `mix` weight clamped (3 vortices could push it past 1) | .2992→.2988 / .3076→.3078 |
| 9 | neural-resonance | 1 streamline-aligned persistence · 2 eddy-core synapse glow | filtering read of C → exact manual bilinear | .5500→.5502 / .6378→.6337 |
| 10 | phosphor-magnifier | 3 vertical beam-spot growth · 4 held-pointer magnet bends the raster | – | .2989→.3149 / .1898→.1898 |

Formula rows used (§12.2): Isotropic 9-point Laplacian (D) — conv-reaction · Vorticity confinement (D) — fluid-grid · Cauchy
dispersion (F) — spectral-distortion. Each on exactly one file. Everything else is the file's own vocabulary.

`x-meta.upgrade.params` added (additively, `params` byte-exact) to the four definitions that lacked it: fluid-grid-rgba-fluid,
gen-chromatic-vortex, mouse-neural-dreamscape, chroma-vortex. No `features` / `upgraded-rgba` / `audio-reactive` tag was
added anywhere (no ACES or audio claim changed).

---
## 1. neural-nexus
**Kept verbatim:** 4 params and roles; per-neuron FFT voice; signalPhase / pulse / dendrite / aura; click bursts; mousePulse; the sampleUV warp; all four light colours; the (dead) HEAD spring; A = raw (totalActivity, sparks, mousePulse, alpha).
**A packing:** raw sim state; A.g (sparks) is now also read back as C.g — same quantity, never tone-mapped.
**Ideas:** 1 — `segmentDist` to neurons i+1 and i+3, `exp(−d·260)` fibre, packet `exp(−((s−pp)·9)²)` with ends faded, brightness gated by the source neuron's own `max(pulse,0)`; rate rides Signal Speed (`time·(0.22+speed·0.18)`, no `time × audio`). 2 — `sparks = max(sparks, C.g·keep)`, `keep = mix(0.985, 0.90, Decay/2.5)`.
**Visible in render:** thin cyan fibres radiating between neurons with bright packets; A.g max 0.618→0.787 at the same frame.

## 2. conv-reaction-convolution
**Kept verbatim:** 4 params; luma/edge seeding and the 0.82 C.rg persistence; image Laplacians (kept as one term); mouse/ripple feed; Pearson k line; CA on edges; ACES on finalColor; packed (A, B, final.b, activity).
**A packing:** HEAD's documented (A, B, mixed blue, activity); C.rg = chemicals.
**Ideas:** 1 — `lapChem = 0.2·edges + 0.05·corners − C.rg` from 8 clamped exact loads, `lapA = mix(lapAImg, lapChem.x, 0.55)` (and B). 2 — `feedLocal = feedBase · mix(0.80, 1.20, inputLuma)`; kill follows the same Pearson line from the local F.
**Visible in render:** chemical fronts now diffuse through C; the sky nucleates fine Turing speckle that HEAD's image-locked relaxation never produced. Stable over 500 frames (A,B stay in [0,1]).

## 3. fluid-grid-rgba-fluid
**Kept verbatim:** 4 params; semi-Lagrangian advection, diffusion, one Jacobi pressure step, radial mouse force, ripple dye; per-tile displacement; dye-tinted grid lines; A = raw (vel.xy, pressure, density).
**A packing:** raw sim state, HEAD's.
**Ideas:** 1 — `stirForce = perp(mouseDir)·falloff·0.2·held` added to the same impulse (HEAD's radial force is curl-free, so the other two ideas had nothing to act on without it — see BRIEFS A1). 2 — `curlAt` from exact loads at the centre and its 4 neighbours → `perp(normalize(∇|ω|))·clamp(ω,±40)·0.0008`, then the HEAD velocity clamp. 3 — the tile-centre curl rotates the tile's sample coordinates, `spin = clamp(ω·0.04, ±0.9)`.
**Visible in render:** tiles rotate inside eddies; after the pointer is released the flow lingers (600 frames, viscosity 0: |v| max 0.21 vs HEAD 0.10 — bounded, far below the 0.5 clamp, no runaway).
**Floor:** `loadC` reproduces the sampler's addressing exactly (equivalence run: constants zeroed ⇒ meanL .4430 = .4430, A extrema identical).

## 4. gen-chromatic-vortex
**Kept verbatim:** 4 params; spiral / warpPhase / mirror-fold / glint / breathing dispersion / hue arms; YUV rotation; ACES; A = ACES display RGBA.
**A packing:** ACES display RGBA (HEAD's).
**Ideas:** 4 — `funnel = 1 + 0.12·(depth − ½)` multiplies the swirl rate (flat depth 0.5 ⇒ HEAD exactly). First tuning at 0.6 tore the picture along depth edges (screen-sized flat polygons) — cut to 0.12 after viewing. 5 — history read at the pixel rotated back about the vortex centre by `0.09·(1+½mids)·(0.3+2/sectors)/0.55` rad (exact bilinear), persistence `0.04 + 0.02·mids + 0.45·streak·smoothstep(0.02,0.12,r)`.
**Visible in render:** arms drag curved tails; depth shears the winding rate.

## 5. mouse-neural-dreamscape
**Kept verbatim:** 4 params; grid / neuron / ripple-wave / `max(act, prev·0.95)` decay; neighbour-line geometry; palette; alpha = activation.
**A packing:** raw sim state — A = (activation, connection memory, 0, 0); both read back as exactly that.
**Ideas:** 1 — packet `exp(−((s−pp)·7)²)` on each lit wire; source = more pointer-active end (tie → fixed axis order so both cells that draw the wire agree), `s` continuous across the cell boundary, rate rides Pulse Speed, phase-seeded per wire. 2 — `lineMemory = max(min(wire glow,2), C.g·0.99)` redrawn at `0.22·mem·(1−lit)`. First tuning (0.4 / 0.992) kept the whole path blazing; cut after viewing.
**Visible in render:** thick bright packets on the lit lattice; a faint lit lattice remains along the pointer's earlier path.

## 6. spectral-distortion
**Kept verbatim:** 4 params; three noise taps; blob / click-ring warpStr; `sepR/sepB` band separation; alpha; A = display RGBA.
**A packing:** display RGBA (HEAD's); C now read back as colour, so the "temporal-persistence" tag is finally true.
**Ideas:** 1 — `cauchyScale(separation·6)` (650/550/450 nm, relative to green) multiplies the R and B *warp* amplitudes only; `sepR/sepB` untouched. 2 — `mix(rgb, C.rgb, vec3(0.14,0.26,0.40)·clamp(separation·12,0,1))`; separation 0 ⇒ no lag.
**Visible in render:** blue bends visibly more than red under heavy separation. This is the quietest card of the batch; motion trails are the place to judge it.

## 7. scan-slice
**Kept verbatim:** 4 params; slice bank + click slices and their `maxBand/bestOffset/bestIndex` competition; palette + FFT voice; edge glow; background desat/dim; peak normalise; alpha; A = display RGBA.
**A packing:** display RGBA (HEAD's).
**Ideas:** 1 — `slitX = bestCenter + (uv.x − bestCenter)·(1 − 0.45·maxBand²)`. 2 — R and B test the winning aperture at `uv.x ∓ min(abAmt·0.8, 0.35·halfWidth)`, gated by `bestLive` (an inactive slice or an expired click that wins a tie must not paint a fringe — first draft leaked there).
**Visible in render:** the content inside a slice is stretched toward its centre column; red/blue fringes straddle the slice edges.

## 8. chroma-vortex
**Kept verbatim:** 4 params; factor/power falloff; per-channel angle split; the weighted colour blend; spiral SDF mask; ACES; A = pre-ACES colour.
**A packing:** pre-ACES colour RGBA (HEAD's), not read back.
**Ideas:** 1 — `c3 = 1 − c2`, weight 0.45, circulation −1 (the whole angle triple flips sign). 2 — `rotPhase = Σ w·angleG / Σ w / TAU` added to the spectral ramp at 0.35.
**Visible in render:** a soft counter-rotating swirl appears on the far side of the frame; rainbow bands follow rotation contours.

## 9. neural-resonance
**Kept verbatim:** 4 params; curlField; mouse mask; the warp; chroma split; feedback mix; synapseTint; click rings; the clamp (no ACES in the loop); A = display RGB, B = mask quad.
**A packing:** display RGB + alpha (HEAD's, raw clamp, read back as C); B = mask quad (HEAD's).
**Ideas:** 1 — three exact-bilinear taps at `warpedUV, ± warpDisp·1.5`, weights 0.5 / 0.25 / 0.25. 2 — `eddy = smoothstep(0.8, 3.0, |curlRaw|)`; tint amplitude × `(1 + 1.1·eddy)`.
**Visible in render:** trails stretch along flow lines; cores of strong curl flare. Laminar regions are HEAD's.

## 10. phosphor-magnifier
**Kept verbatim:** 4 params; barrel + depth magnification; snapped sampling; shadowMask + bloomW; scan-line phase and degauss; per-channel persistence; ACES; alpha; A.
**A packing:** ACES display RGBA (HEAD's); C read back as the afterimage.
**Ideas:** 3 — `scanLine = mix(HEAD scan line, 1, 0.30·smoothstep(0.5, 1.0, beamLuma))` (first tuning 0.7 flattened every bright area; cut after viewing). 4 — while held, `bend = (0.5·sin(13·y − 1.3t), sin(16·x + 1.7t))·0.010·zoom·heldPressure²` added to the lens displacement (zero when not held).
**Visible in render:** held pointer ripples the raster inside the lens; bright regions lose their scan-line gaps, dark ones keep full-depth lines. Mean luma +5 % (default) on a frame that is processed edge to edge.

---
## Open items (found, not fixed — outside an idea batch)
1. **Dead spring state (4 files).** `extraBuffer` is rewritten by `writeExtraBuffer` every frame, so the `[133..138]` springs in neural-nexus, spectral-distortion, scan-slice and neural-resonance never persist; their first-frame snap fires every frame and they behave as the raw cursor. A(0,0) rescue (the `cyber-magnifier` scheme) would repair them.
2. **phosphor-magnifier grille never renders.** `shadowMask(snappedG, …)` → `local ≈ 0` → (0,1,0) everywhere; R and B are multiplied by 0, so the lens is a green-phosphor look and HEAD's own beam-blooming and the R/B sampling are invisible. The grille also aliases at default zoom (pitch ≈ 0.4 px at zoom 5.5). Looks intended, isn't; decide on QA whether to un-green it.
3. **fluid-grid pressure is inert.** A.b is 0.000 in every run: the Jacobi step reads C.b, which starts at 0 and has no source, so "pressure bulges" never appear. Left as HEAD.
4. **conv-reaction output packing.** `writeTexture.rg` = chemical A/B (finalColor.rg is discarded; only .b survives), so the screen shows a pseudo-colour of the chemicals, not the mixed image. HEAD's documented packing — kept.
5. **chroma-vortex slider range.** `Vortex Twist` is declared −1..1 but `clamp(zoom_params, 0, 1)` removes the negative half.
6. **Tag drift (pre-existing).** neural-nexus, spectral-distortion, scan-slice and neural-resonance carry `upgraded-rgba` without ACES in the WGSL.
7. **Tests.** `npm run test:ci`: 1820 passed, 1 skipped, 2 failed — `semanticIndex.test.ts` fails identically on the pre-batch commit (index has 1417 entries vs 1426 catalog entries); `WgslDraftSection.test.tsx` failed once under CPU load while the GPU sweep ran and passes in isolation on this branch and on the pre-batch commit.
8. **Real-GPU visual QA is external.** Thumbnails are marked stale by the ledger and refreshed on a GPU machine.
