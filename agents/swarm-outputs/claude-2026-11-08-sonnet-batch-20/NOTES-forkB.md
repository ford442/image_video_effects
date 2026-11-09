# sonnet/batch-20 — Fork B notes

Shaders: gen-quantum-superposition, gen-quantum-resonance-lattice, gen-acid-lissajous. All three were second/third-pass (HEAD `Ideas:` lines kept).
Cards + mechanism interrogation: `BRIEFS-forkB.md` (written before WGSL; amendments at the bottom).
No git operations were run by this fork. Edited: the three `.wgsl` files only. JSON untouched (descriptions stay true; `params` byte-exact).
`reports/*` got dirtied by the gate/audit runs — restore with `git checkout reports/`.

Renders: minirender 192px · 24 frames · t_end 2.0 · JSON-default sliders · mouse (0.5,0.5) up · audio (0.3,0.2,0.1) ("default"),
and mouse (0.3,0.7) up · audio (0.8,0.6,0.4) ("loud"). PNGs are 3-panel `rgb | over-white | alpha`, in `forkB/`:
`<id>_{before,after}_{default,loud}.png`.

| shader | case | meanL before→after | stdL | meanA | NaN | Tint verr |
|---|---|---|---|---|---|---|
| gen-quantum-superposition | default | 0.665 → 0.668 | 0.138 → 0.137 | 0.764 → 0.763 | 0 | null |
| | loud | 0.683 → 0.687 | 0.122 → 0.126 | 0.810 → 0.815 | 0 | null |
| gen-quantum-resonance-lattice | default | 0.115 → 0.173 | 0.171 → 0.189 | 0.249 → 0.300 | 0 | null |
| | loud | 0.232 → 0.306 | 0.226 → 0.230 | 0.343 → 0.407 | 0 | null |
| gen-acid-lissajous | default | 0.086 → 0.279 | 0.157 → 0.253 | 0.114 → 0.311 | 0 | null |
| | loud | 0.356 → 0.583 | 0.182 → 0.214 | 0.406 → 0.565 | 0 | null |

Gates: `wgsl_precommit_gate.py --files` 3/3 (naga OK, bindgroup compatible, no pasted headers); `audit_dead_sliders.py --files` scanned 3, 0 new dead;
`audit_extrabuffer.py` 0 new violations. Header: `Upgraded:` appended `, 2026-11-08`, `Ideas:` extended, `A packing:` unchanged on all three.

---
## gen-quantum-superposition
**Kept verbatim:** 4 params/roles; Lissajous orbits + seeds; 5 ghosts at 2π/5; `ghostPh`; collapse, Zeno, ripple holes; Heisenberg fog; two-path `fringeColor`;
vacuum fbm; `coherence = 1 − 0.85·decoherence`; phase-hued cross term + dark cancellation; detector hits (exact C load, A.a, 0.994 fade); ACES(col·1.1).
**A packing:** unchanged — rgb = ACES display, a = detector hit accumulator read from C.
**Ideas (file lines):**
* Idea 3 — de Broglie carrier: `quantumGaussian` (l.58–68) gains `e^{i k·(p−c)}`; k = 42·d(lissajousPos)/dghostT (l.173–177, analytic orbit velocity). Overlapping packets with different momenta now give real fringes (HEAD's packets had constant phase, so the cross term was smooth).
* Idea 4 — breathing packets: width scale s=1+0.3 sin(Ωt+φ) (Ω=0.9·audioModSpeed, φ per ghost), amplitude ∝ 1/s, expansion-flow chirp 3·(ṡ/s)·d²/σ² (l.178–183 + fn l.58–68).
* Idea 1 compositing change (l.246–262): V = (|Σψ|²−Σ|ψ|²)/Σ|ψ|² faded by Σ|ψ|²; constructive → `mix` toward phase colour; destructive → multiplicative darkening. Needed because the raw term clipped to flat grey bands.
**Formulae:** none from §12.2 (tactic-derived).
**Visual verdict:** fringes are clearly visible where few packets overlap (stripes on discs; coloured bands in overlaps); the central region where ~20 packets stack is still pale (hue-averaging of 4 particle colours + clip) — that wash is HEAD's, judged "soft pastel by design" and left alone. stats ≈ unchanged (0.665→0.668), so no new wash. Checked 1 particle (5 discs with fringe slivers) and 8 particles.
**ACES:** `col` is clamped [0,1] before `acesToneMap`; `max(totalProb,0.02)` guards the visibility divide; `sigma` ≥ 0.015 so `sigma*sigma` is safe.
**Could not verify:** real-GPU look; the 42 carrier gain is tuned at 192–384 px (fringe period ≈ 0.05–0.3 frame heights).

## gen-quantum-resonance-lattice
**Kept verbatim:** 4 params; octahedron SDF + domain repetition, wave/audio/dislocation/chaos rotation/mouse well in `map`; 3-channel ray-offset dispersion; `resonanceHalo`; `nodalSheets`; `probInterference`; fog; ACES(col·(1.05+0.15·bass)); depth from the undispersed march; A = display RGBA.
**A packing:** unchanged — ACES display RGBA.
**Ideas (file lines):**
* Idea 5 — node probability cloud: per-step `cloud += exp(−5d)·Δt·exp(−0.04t)` with Δt the step taken (l.183–190), closest-approach point `pNear` tinted with that node's own ambient colour (l.233–236), gain 0.28+0.35·bass. Voids get a node-centred halo; each channel's own march gives it a dispersion fringe.
* Idea 6 — lattice phonon: `phononAt` (l.36–45, simple-cubic dispersion, ω=4.708) breathes node radius ±0.12 in `map` (l.95–97) and shades crests brighter (l.225–227). **Tried and dropped:** coupled-resonator bonds (gold veil, see BRIEFS amendments).
**Floor fixes (not ideas, stated per §8):** `pow((r−0.58)·8.5, 2.0)` / `pow((r−0.74)·8.0, 2.0)` → `x*x` (l.107–110; negative base at essentially every hit ⇒ NaN on strict GPUs — minirender/SwiftShader cannot show it; look is identical there: with the cloud and (then-planned) bond gains at 0, before the phonon was added, the render matched HEAD stats exactly). Gravity-well mouse y un-mirrored (l.83; only matters while the button is held).
**Formulae:** none from §12.2.
**Visual verdict:** HEAD's black voids survive (6-time sweep t=0.3…9.1); nodes get soft coloured halos; meanL +50% at default. Near-camera grazes (t≈0.3, 2.9) get hazy because the cloud peaks when a ray skims a node for a long distance — acceptable, but this is the file's most gain-sensitive knob (0.55 was too hazy, 1.0 a wash).
**Could not verify:** that the phonon crest wave reads as *travelling* (only stills; formula cos(κ·n − ωt) is straightforward); real-GPU cost — cloud adds 1 exp + select per step per channel (3×100 steps).
**Pre-existing, untouched:** camera starts on the z-axis through the node column (can sit inside a node when wave+audio offsets cancel; HEAD baseline sweep shows this at some t, e.g. t=2.9 green slab, present in HEAD too).

## gen-acid-lissajous
**Kept verbatim:** 4 params; strand ladder (freqX/freqY), phase and hue laws; core+bloom glow; beads, waist, cusp dwell, 2:1 lobe split, pen head, beat envelope; mouse well, click burst, treble sparkle, luma spawn, C feedback with organic drift, vignette, chromatic shift, ACES.
**A packing:** unchanged — ACES display RGBA.
**Ideas (file lines):**
* Idea 7 — continuous neon tube (l.173–216): distance to the *chord* between samples with chord-interpolated foot parameter and cy, then a 12-chord refinement over ±1 chord at the best foot (removes polygon sagitta). HEAD measured distance to the nearest of 96 *vertices*; a freqX≈5 strand has ~0.2 vertex spacing vs 0.0085 glow width, so strands rendered as separate beads. `bestT`, `bestCy` (lobe sign) and the cusp-velocity read now sit at the true foot point.
* Idea 8 — phosphor comet (l.235–243): `beamAge = fract((nowT − bestT)/τ)`, brightness × mix(0.45, 1.7, exp(−beamAge·k)), k = mix(5, 1.5, feedback) so the Feedback Decay slider also sets the tail length. Applied to glow and cusp dwell, not to the origin beads. The figure shows its drawing direction; mean strand brightness −12% vs no comet.
**Formulae:** none from §12.2.
**Visual verdict:** continuous tubes, rich nest of strands; comet visible as bright runs behind each pen head (checked with feedback = 0). Big brightness change (0.086→0.279) is the beads becoming lines, not a gain change. Loud + 9 strands + held mouse is busy/pastel but not blown out (stdL 0.21).
**Could not verify:** comet direction against the live pen head across frames (stills); real-GPU cost — strand loop ALU is roughly 2× HEAD's (division + 2 dot per chord, +12 refine chords per strand; up to 9 strands). Biggest perf risk in the fork; if it matters, drop SAMPLES to 64 (the refinement covers the coarse chord).
**Pre-existing, untouched:** the file's spring (extraBuffer[133..138]) re-initialises from the raw mouse every frame (those slots are zeroed by the uploader), so `mouse` is effectively the raw mouse.
