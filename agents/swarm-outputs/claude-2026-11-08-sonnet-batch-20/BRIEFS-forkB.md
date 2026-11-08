# sonnet/batch-20 — Fork B briefs (written BEFORE any WGSL edit)

Fork B shaders (all second/third pass — HEAD `Ideas:` lines are kept, not re-added):
gen-quantum-superposition, gen-quantum-resonance-lattice, gen-acid-lissajous.
Baselines: minirender 192px/24 frames/t_end 2.0, JSON defaults, audio (0.3,0.2,0.1), mouse (0.5,0.5,up).
Baseline stats (meanL / stdL / meanA): superposition 0.665/0.138/0.764 · lattice 0.115/0.171/0.249 · acid 0.086/0.157/0.115.
Prelude: superposition is migrated (99d40279). The other two already include `_prelude.wgsl`.

## What the baselines actually show (read before the cards)

* **superposition** — `quantumGaussian` returns a Gaussian with a *spatially constant* phase. Twenty such packets
  summed coherently give smooth blobs: the "interference cross-term" has no spatial structure to interfere with, so the
  pastel mass has no fringes at all. A real moving packet carries a plane-wave factor.
* **acid-lissajous** — each strand is measured as distance to the *nearest of 96 curve samples*. A curve of
  freqX≈5 is ~20 units long, so the sample spacing (~0.2) is 20× the glow width (0.0085): the strands render as rows of
  separate beads rather than the "neon tubes" the header promises.
* **lattice** — dark voids between nodes; halo/bands exist only on the hit surface. Floor bugs spotted while reading:
  `pow((r-0.58)*8.5, 2.0)` has a negative base at essentially every hit (r < 0.58) → NaN on strict GPUs (SwiftShader
  special-cases y==2, so minirender cannot show it); the gravity-well mouse y is mirrored (uv.y is top-down, `my=(0.5-mouse.y)*20`
  puts the well on the opposite side).

---

## SHADER: gen-quantum-superposition
IDENTITY (one sentence): 1–7 wave packets on Lissajous orbits, each with five phase-offset ghost copies, summed
  coherently into soft pastel probability clouds with a phase-hued interference term, a mouse observer that collapses/Zeno-freezes
  the field, and a detector screen whose hits build up in A.a.
KEEP VERBATIM: 4 params (particle_count→numParticles, decoherence→σ/ghostSpread + coherence slider, wave_speed,
  wavefunction_opacity); Lissajous orbits + hash seeds; 5 ghosts at 2π/5 spacing; ghostPh constants; collapse/Zeno/ripple holes;
  Heisenberg fog; two-path `fringeColor`; vacuum fbm; cross-term `(|Σψ|²−Σ|ψ|²)` phase-hued + dark cancellation with the
  `coherence` factor; detector hits (exact C load, A.a accumulator, 0.994 fade); ACES(col·1.1); A = (display rgb, hits).
MECHANISM INTERROGATION (§12.1):
  * tactic 1 (deepen kernel): `quantumGaussian` is a *stationary* packet. The better approximation of the same operator is a
    moving packet: Gaussian × e^{ik·(r−c)}.
  * tactic 2 (physics one step further): a moving packet's first-order side effects are (a) a carrier wave set by its momentum,
    (b) width change with a quadratic phase (expansion-flow phase = ṡ/s · r²). Both are what a textbook "wave packet" animation shows.
  * tactic 3 (promote an intermediate): the orbit velocity d/dt `lissajousPos` is analytic from the `a, b, δ, scl` the loop
    already computes and is thrown away — it is exactly the packet group velocity, hence k = m·v.
  * tactic 6 (history): the hit accumulator in A.a already owns C — untouched.
ADD (2 native ideas):
  1. de Broglie carrier wave — ψ_g ← ψ_g · e^{i k·(p − c)}, k = K0 · d(lissajousPos)/dghostT. Overlapping packets with different
     momenta now produce real straight/curved interference fringes in the existing cross-term; today it is smooth.
  2. Breathing packets with expansion-flow chirp — width scale s(t)=1+0.3 sin(Ωt+φ_ig); amplitude ∝ 1/s (2-D norm conserved);
     quadratic phase ∝ (ṡ/s)·d²/σ² (the Madelung/Hubble-flow phase of a changing-width Gaussian). Gives curved ring fringes around
     packet cores, and packets that visibly inhale/exhale instead of sitting at constant σ.
FORBID on this file: springs, new params, IQ palette, a second ripple system, any change to the detector packing, any new
  detector/overlay costume, extra ghosts.
A PACKING: unchanged — rgb = ACES display, a = detector hit accumulator read back from C.
FORMULAE: none of the §12.2 rows (tactic-derived physics). Check: signed cross term already goes through `max/clamp` before ACES.

## SHADER: gen-quantum-resonance-lattice
IDENTITY (one sentence): a camera flying down a raymarched lattice of octahedral nodes, chromatically dispersed by
  per-channel marches, with bass-breathing nodes, travelling wave displacement, nodal sheets and band-split halos.
KEEP VERBATIM: 4 params (spacing, amplitude, travel speed, chaos); octahedron SDF + domain repetition + wave/audio/dislocation/
  chaos-rotation/mouse-well in `map`; 3-channel ray-offset dispersion; resonanceHalo bands; nodalSheets; probInterference;
  fog; ACES(col·(1.05+0.15 bass)); A = display RGBA; depth from the undispersed march.
MECHANISM INTERROGATION:
  * tactic 3 (promote an intermediate): `d` (the SDF at every step) drives only the hit test. Rays that miss throw the
    near-miss distance away, so the lattice voids are pure black and the "halo" lives only on hit surfaces.
  * tactic 2 (physics one step further): a *lattice* of resonators has coupling between neighbours. The coupled-resonator
    normal modes obey the chain dispersion ω(κ)=2ω₀|sin(κ/2)|; the energy sits on the bonds as strain (u_{n+1}−u_n)².
    The file already says "coupled resonators splitting lines" in its halo comment but draws no coupling.
  * tactic 5 (device artifact): a phonon/lattice-wave visualisation shows bonds and pulses hopping node-to-node.
ADD (2 native ideas):
  1. Node probability cloud — integrate `exp(−k·d)·Δt` along each channel's march (soft, step-weighted, distance-faded),
     tinted by the closest-approach node's existing ambient colour. Voids get a node-centred uncertainty halo; the three
     channels' offset marches give the cloud its own dispersion fringe.
  2. Coupled-resonator bonds with chain-dispersion pulses — thin filaments along the three lattice axes through every node; each axis carries a
     travelling strain pulse sin²(½(κ_i·x_i/spacing − ω_i t)) with ω_i = 2ω₀|sin(κ_i/2)| (ω₀ breathes with mids, pulse height with bass),
     so long/short wavelengths visibly run at different speeds.
  Floor (stated, not an idea): `pow(neg, 2.0)` → `x*x`; gravity-well mouse y un-mirrored (only matters while the button is held).
FORBID on this file: springs, ripples, IQ palette, thin-film, a second march, new params, replacing the octahedra.
A PACKING: unchanged — ACES display RGBA in A.
FORMULAE: none from §12.2 (chain dispersion is tactic-derived physics).

## SHADER: gen-acid-lissajous
IDENTITY (one sentence): five (up to nine) Lissajous strands of different frequency ratios drawn as glowing acid-coloured
  neon tubes with trail feedback, a mouse gravity well, click burst, beads at the origin crossings, ratio waists, cusp dwell, lobe tints, pen heads and beat breathing.
KEEP VERBATIM: 4 params; strand frequency ladder (freqX/freqY rule), phase law, hue law; core+bloom glow; beads (Idea 1), waist (2),
  cusp dwell (3), 2:1 lobe split (4), pen head, beat envelope; gravity well, click burst, treble sparkle, luma spawn, C feedback with
  organic drift, vignette, chromatic shift, ACES, A = display RGBA.
MECHANISM INTERROGATION:
  * tactic 1 (deepen kernel): the curve is a polyline of 96 samples measured by *vertex* distance → dots. The same operator done
    properly is point-to-*chord* distance with the foot parameter interpolated along the chord.
  * tactic 3 (promote an intermediate): `bestT` is already used for dwell velocity and the lobe sign; with chord distances it becomes
    continuous. `nowT` (the pen's parameter) is computed only for the head disc.
  * tactic 5 (device artifact): an X-Y oscilloscope trace has a bright spot at the beam and a phosphor tail whose brightness decays
    with *time since the beam passed* — direction of drawing is visible. The file has the beam spot (pen head) but not the tail.
ADD (2 native ideas):
  1. Continuous neon tube — point-to-chord distance (and chord-interpolated foot parameter / cy) instead of nearest-vertex, so the
     trace is an unbroken tube, the cusp dwell and the lobe sign are evaluated at the true foot point.
  2. Phosphor comet — brightness along each strand depends on the beam's age at that point: age = fract((nowT − footT)/τ),
     factor = mix(floor, 1, exp(−age·k)); the trace is brightest just behind the pen head and fades round the loop, so the figure shows
     its drawing direction (fully lit when the audio beat envelope fires).
  (3?) only if it earns its place after rendering: P31-style afterglow — per-channel decay on the C history.
FORBID on this file: new params, a second spring, shockwave rings, replacing the strand ladder, changing feedback packing,
  extending to ≥10 strands.
A PACKING: unchanged — ACES display RGBA.
FORMULAE: none from §12.2.

## Cross-file de-dup (Fork B)
No §12.2 row used on any of the three. The shared mechanism between files is "packet/pulse travelling with a dispersion
relation", but each uses a different quantity (de Broglie k from orbit velocity; chain ω(κ); beam age along a chord), so there is no shared overlay.

---
## Amendments made after rendering (card text above is what was planned; this is what shipped)

* **gen-quantum-resonance-lattice — Idea 2 replaced.** The planned "coupled-resonator bonds" were implemented and rendered, then removed:
  thin axis-aligned cylinders integrated along the march alias against the step length (0.2–0.6) and read as a flat gold veil
  (meanL 0.89 at gain 0.9, 0.17–0.34 at gain 0.04–0.12 with still no distinct filaments). Replaced with a **lattice phonon**: a travelling
  lattice wave of phase advance κ=(1.15,0.8,1.6) per cell breathing each node's radius (±0.12) and shading crests brighter, crest speed
  from the simple-cubic dispersion ω² = 4ω₀² Σ sin²(κᵢ/2) (ω₀=2.4 → ω=4.708). Same tactic-2 physics (coupled resonators), but it acts on
  the geometry that is actually visible.
* **gen-quantum-superposition — cross-term mapping.** Idea 1's compositing had to change for Ideas 3/4 to be visible: raw
  `(|Σψ|²−Σ|ψ|²)·2.5` clipped to flat grey bands once the packets carried real phase gradients. It is now the fringe visibility
  V=(|Σψ|²−Σ|ψ|²)/Σ|ψ|² (faded by Σ|ψ|²), with constructive fringes `mix`ed toward the phase colour (instead of added white) and
  destructive ones darkening multiplicatively. The `coherence` factor (Decoherence slider) is unchanged.
* **gen-acid-lissajous** — shipped as carded (ideas 7 and 8 in the file's own numbering; the third "afterglow" idea was not added).
