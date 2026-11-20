# BRIEFS — fork E (sonnet/batch-47): hyb-chromatic-circuit, gen-rgb-diffraction

Both files are **second pass** (existing `Ideas:` are KEEP VERBATIM). HEAD = `origin/main` 62680da7 (both already `#include "_prelude.wgsl"`, so the worktree file == HEAD before my edit). Written before any WGSL edit.

HEAD runs (SwiftShader, `agents/mr.mjs`): both render, 0 NaN, no blank/saturated frame. HEAD defects found by reading:

| file | defect | rescue |
|---|---|---|
| hyb-chromatic-circuit | `imgEdge = sqrt(pow(luma - lumaR, 2.0) + pow(luma - lumaU, 2.0))` — `pow` with a negative base (luma differences are signed). Undefined in WGSL; NaN on any driver that lowers it to `exp2(y·log2 x)`; SwiftShader happens to fold it so the VM shows 0 NaN. | explicit squares (bit-identical where `pow` was defined) |
| gen-rgb-diffraction | `exp(-pow((talbotPhase - 0.5) * 8.0, 2.0))` and `exp(-pow((axisRad - rm) * 24.0, 2.0))` — negative base half the time. Worse here: a NaN in `color` goes through `dataTextureA` and the 3 % feedback mix, so one bad pixel would stay forever. | explicit squares |

Not defects, left alone and flagged in NOTES: circuit hex grid is `uv * gridScale` with no aspect correction (cells stretch ×1.78 on 16:9; look is saved-preset identity). Diffraction fringe spatial frequency is `freq·λ` (red tightest) — physically inverted (fringe frequency ∝ 1/λ) but it is the saved look of all six existing ideas; changing it would move 100 % of pixels.

---

## hyb-chromatic-circuit

```
SHADER: hyb-chromatic-circuit
IDENTITY: a hex-lattice "opal circuit" laid over the photo — gated copper-coloured traces between hex centres, a travelling packet and a pulse glow, chromatic aberration along the cell gradient.
KEEP VERBATIM: nearestHexCenter lattice; the six unit spokes centre→centre+n_k; selfGate*neighborGate gating (hash12 > 0.35); traceMask/pulseGlow/packet formulas; chroma R/B shift along hexUV-center; hue = fract(rnd*0.2 + t*0.08 + pulse*0.15); effectMix blend; params grid_scale/trace_width/chroma_spread/effect_mix and their mapping; plasmaBuffer[0] bass (packet gain) / treble (packet speed); A = ACES display RGBA (C is not read).
ADD (2 native ideas):
  1. Via pads with annular ring + drill — a real PCB junction is a through-hole via: copper annulus around a drilled hole, bigger where more traces land on it. Every live node (hex centre with >=1 gated trace) gets one; pad radius scales with the node degree already known from g0..g5; the drill punches through the layer so the photo shows through, darkened. The pad flares when a packet launches from it (packetHead≈0).
  2. Copper-ridge bevel under solder mask — each trace is a raised copper ridge under translucent mask, so its two edges catch light differently. The cross-section normal comes from the SDF vector (pixel - closest point on the segment) the file already computes; a fixed upper-left light gives a lit side, a shaded side and a short specular on the lit shoulder.
FORBID: Cauchy / lens dispersion (fork A's), springs, ripples, IQ palette, any new param, a second tear/scan system, replacing the hue scheme.
A PACKING: ACES display RGBA (unchanged; the shader never reads C).
```

**§12.1 interrogation**
- Tactic 1 (kernel): traces are `1 - smoothstep(0, w, dist)` — a flat cosine-ish line profile with no cross-section. Next-better approximation of "a copper track": a profile with a surface (ridge) → idea 2.
- Tactic 2 (physics one step further): the effect models a PCB. First-order side effects the real board shows that this lacks: vias/pads at junctions (the six spokes just end in a blob today), mask-over-copper relief → ideas 1 and 2.
- Tactic 3 (promote an intermediate): `g0..g5` (neighbour gates) and `s_k.x/.y` (distance, h) are computed and thrown away after the max. Gate count = node degree → pad size; the SDF offset vector → ridge normal. Nothing new is sampled.
- Tactic 6 (history): C is not read and A is a display output; adding history would be a new mechanism → not used.

**§12.4 formula admission.** §12.2 has no PCB row. Both ideas are admitted via the §12.1 tests rather than a table row (COMMON explicitly claims PCB-native rows for this file): *same-noun* — via / annular ring / solder mask / copper ridge are all board vocabulary; *deletion* — delete either and it is exactly the HEAD circuit, delete the traces and neither idea is the effect; *expert* — a PCB designer recognises a via pad with a drill and mask relief. Nearest §12.2 kin: idea 2 = analytic SDF normal / rim highlight (§12.2E curvature, ULTRA analytic normals); idea 1 = soft SDF discs on existing node geometry. Both consume quantities the file already has (local hex coords, gates, dist/h, packetHead).

---

## gen-rgb-diffraction

```
SHADER: gen-rgb-diffraction
IDENTITY: a six-fold, kaleidoscopic diffraction-grating starburst — rotated multi-slit cosine fringes per R/G/B wavelength, a bright zero-order spot, ACES, exact-C feedback.
KEEP VERBATIM: applySymmetry(6); hexMask; slitIntensity with freq·λ and per-channel phase offsets; SLITS=6 loop incl. blaze-angle phase ramp from the pointer; norm/brightness; single-slit sinc² envelope (freq*0.10); shimmer hue; Talbot bands; zero-order exp(-r*40)*2.5 spot; vignette; ACES; mix(color, prev.rgb*0.9, 0.03+bass*0.01) with exact textureLoad C; params evolution_speed / fringe_frequency / chromatic_spread / brightness and mapping; audio bands (bass chroma offset R, mids G, treble B / lobes).
ADD (2 native ideas):
  1. Chromatic Airy rings around the zero-order spot — a circular aperture's central spot is an Airy pattern; the rings' radii scale with λ, so R rings sit outside G outside B. Uses the file's own λ ratios (lambdaR:lambdaG:lambdaB) scaled by the chromatic_spread slider's existing role; the central lobe is left to the HEAD spot (rings start at the first dark ring). Shown at amplitude (|2J1(x)/x|, a compressive display response). REVISED after the first render: an additive-only ring (~0.2) was invisible inside the busy fringe field, so the idea has two halves — dark rings dim each channel's fringes at its own radius (aperture envelope, multiplicative, fades with radius) and the bright rings are added at the zero-order spot (scaled by the brightness/exposure slider).
  2. Order-dependent spectral dispersion of the existing grating lobes — the grating equation mλ = d·sinθ puts the m-th order of each wavelength at radius ∝ mλ, so R/G/B lobes split by an amount that grows with m and neighbouring orders overlap. HEAD's four tinted lobes are the reference-wavelength (green) order and are kept verbatim (same rm, rolloff, tint, weight); R and B lobes at rm·λR/λG and rm·λB/λG are added as the order's red outer and blue inner satellite. REVISED: multiplying the HEAD tint per channel made the split depend on the cycling tint hue (min tint channel 0.35) and nearly invisible, so the satellites are a separate additive term (R,0,B)·(0.30 + 0.30·treble).
FORBID: replacing the multi-slit fringes with N-slit sinc/sin ratio (changes 100 % of pixels), changing the freq·λ fringe convention, springs/ripples, IQ palette, new params, hexagonal Airy spikes (would rewrite the zero-order idea).
A PACKING: ACES display RGBA (unchanged; C read as colour history, exact load).
```

**§12.1 interrogation**
- Tactic 1 (kernel): zero-order is `exp(-r*40)` — a Gaussian stand-in for a diffraction spot; its next-better approximation is the Airy amplitude (2J1(x)/x). Lobes are Gaussians at `m·r0` (monochrome tint); next-better is a per-wavelength radius.
- Tactic 2 (physics one step further): a circular-aperture spot has rings; a grating's orders are dispersive (angle ∝ mλ), their width grows with m and orders overlap. HEAD shows neither.
- Tactic 3 (promote an intermediate): `lambdaR/G/B` and `chromAb` are computed but only used as fringe-frequency multipliers; their *ratios* give the per-channel ring/lobe radii. `rm` is computed per order and thrown away after one hue tint.
- Tactic 6 (history): C is colour history with a 3 % mix; no extra continuity needed, left alone.

**§12.4 formula admission.** Both rows are in the Lighting/optical table of §12.2F: idea 1 = **Airy disc** `(2·J1(x)/x)²` (first zero 3.8317, A&S 9.4.4/9.4.6 for J1 — the doc's 4-term series is only good to x≈3 and the `crystalline-veins` blend is off by up to 7.8e-3 at the zeros; A&S verified in numpy to 3.5e-8 up to x=16); idea 2 = grating-equation dispersion (per-wavelength Cauchy-free radius, claimed row: diffraction-grating). Family match: this *is* a diffraction shader. Operates on existing quantities: λ ratios, `axisRad`, `rm`. Deletion: delete either → HEAD picture; keep only either → still a diffraction starburst (additive, not replacing; the zero-order Gaussian and mono lobes remain).
