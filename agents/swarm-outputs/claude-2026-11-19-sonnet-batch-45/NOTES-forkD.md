# NOTES fork D — galaxy-sim (galaxy.wgsl), lenia (both FIRST pass)

## galaxy-sim  (public/shaders/galaxy.wgsl, shader_definitions/artistic/galaxy-sim.json)
SHADER: galaxy-sim
IDENTITY: audio-reactive spiral galaxy — bass-breathing rotating arms, blue core / golden arms, diffraction-spike stars, central eye, silence reverses the flow
KEEP VERBATIM: 4 params + mappings; spiral phase (bassRot / armTwist / cos(spiralAngle*arms)); breathing; core/arm density mix; palette; 4-point diffraction spikes; treble twinkle; eye; vignette; ACES; presence alpha; depth composite; mouse parallax
ADD (the `Ideas:` line):
  1. arm dust lanes — Beer–Lambert extinction (§12.2F): lane at 0.6 of the arm half-width on the inner (larger-phase) edge, zero in the nucleus, fading outward; multiplies the disc glow by exp(-lane·(0.9,1.7,2.7)) (blue eaten most → dark, reddened). Findable: `// ── Idea 1`, `lane`, `dustTrans`. Alpha keeps the undusted glow's alpha (`litLuma`) so the lane is an opaque absorber, not a hole.
  2. arm-born stellar population + HII knots — star density (`starThresh`) and star tint (`popTemp`) follow `armMask`; blue-white in arms, yellow-orange elsewhere (65% blend over the HEAD random temperature); sparse pink HII knots (`knot`) on the arms. Findable: `// ── Idea 2`, `armMask`, `popTemp`, `knot`.
COST TRIM (the first cut measured ~1.4–1.9× in separate-process runs, but those were load noise — see Timing; the cuts below were still worth it): shared `radialFall = exp(-1.5·breathRadius)` (HEAD computed it inline in armDensity) feeds the lane and `armMask = armCore·sqrt(radialFall)`; acos → sqrt(2·spread) and cos(0.3w) → 1−0.09·spread (≤0.03 rad off); one exp for the dust (G, B transmittance are powers of R); knot cells use the sin-free PCG `hashCell33` copied verbatim from `_std_hash.wgsl` with a polynomial falloff (no exp, no sin); star core / knot use dot() not length(); the lane's alpha floor uses raw-luma thresholds (0.055..0.14 ≙ ACES luma 0.05..0.2) instead of a second ACES. HEAD's `hash3` star hash is kept (same star positions as HEAD frozen at t=0).
FORBID honoured: no spring/ripple/IQ palette/new param; spiral layout untouched.
A PACKING: unchanged — (density, armDensity, starBright, alpha), ACES on writeTexture RGB only; B untouched; depth unchanged.
RESCUES (HEAD defects):
  - arm seam: `arms` was fractional (default 3.6) inside `cos(spiralAngle*arms)` over an atan2 angle → hard seam on the ±π branch cut. Now `floor(mix(2,6,p)+0.5)`: default 3.6 → 4 arms (the picture HEAD showed), slider now steps 2..6.
  - strobing stars: `hash3(vec3(cell, time*0.01))` — time inside `sin(dot)*43758` re-rolled the whole star field every frame (0 px overlap at Δt=0.02 s at HEAD; 25/25 now). Time removed; treble twinkle is the scintillation.
  - square star cores (a full 1/50-unit square per star → ~10 px blocks at 1080p) → round core (`starCoreF`).
Params/features/x-meta byte-equal to HEAD (JSON: description sentence appended only).

## lenia  (public/shaders/lenia.wgsl, shader_definitions/artistic/lenia.json)
SHADER: lenia
IDENTITY: Lenia-inspired continuous CA — 3-ring smooth kernel, Gaussian growth, travelling growth packets, click inoculation, thresholded violet/teal display with trails
KEEP VERBATIM: 4 params + roles; kernel (PEAKS, bump); growth Gaussian; viscosity; packets; click fronts; mouse inoculation; spores; seeding; A = (field, growth, trail, 1=initialised) raw state
ADD:
  1. parameter localization of mu (Flow-Lenia) — `muZone()`: smooth noise (period ≈ 17 kernel radii, drifting over ~2 min) shifts mu by ±0.01 around the slider value; sigma stays 0.094·mu locally. Numpy gate (scripts/sim_models/lenia_rescue.py model adapted; N=112, 700 steps, uniform mu 0.122..0.185 × radius slider 0/0.5/1): alive everywhere (mean 0.02–0.24, no death/flood). A/B at N=224: uniform mu → one wall-to-wall stripe regime; zoned mu → stripe zone + sparse zones with isolated ring creatures (quadrant means 0.078–0.200 vs 0.193–0.195). Findable: `// ── Idea 1`, `muZone`, `muLocal`.
  2. kernel-reach aura + growth front — outside the body, potential U (already computed, previously never shown) as faint teal aura relative to mu; the thin ring where growth>0 brighter (where the creature will expand next). Gated by `outside` so species/growth/trail tints are unchanged inside; alpha gets a small `sense`/`front` term. Findable: `// ── Idea 2`, `sense`, `front`, `aura`.
FORBID honoured: no spring/IQ palette/new species palette/second field/extraBuffer/B/new param; kernel peaks and viscosity untouched.
A PACKING: unchanged (raw field state); only writeTexture display changed.
RESCUE: `pow((potential - mu) / sigma, 2.0)` had a possibly negative base (undefined on real GPUs; SwiftShader tolerates it) → `z*z`, identical value. Not a visual change.
Params/features/x-meta byte-equal to HEAD (JSON: description sentence appended only).

## Verification (VM, SwiftShader — no real-GPU look)
- Renders read (Read PNG): galaxy default / arms 2, 4, 6 / spread 0 & 1 / audio+mouse / SRC=img composite; lenia default 256² × 120 frames; 0 NaN everywhere.
- Gates, each file: wgsl_precommit_gate 1/1, verify-naga-wasm --files 1/1 valid, audit_dead_sliders (galaxy-sim + lenia, 2 defs scanned): 0 new, audit_extrabuffer pass.
- Diff vs HEAD at defaults: galaxy 320² t=1 s: 10.9% px >12/255 (6.9% >40: arms edge lanes, star colour/density, round cores, 4-arm default); lenia 128² 80 frames: 57.9% px >12/255 — expected for a chaotic sim whose growth window now varies per zone (trajectories diverge; the A/B in `forkD_lenia_zone_ab.png` shows the regime change, not a pixel-level edit).
- Gates, final state of both files: wgsl_precommit_gate 1/1 each, verify-naga-wasm --files 1/1 each, audit_dead_sliders 0 new (2 defs), audit_extrabuffer pass.
- TIMING (SwiftShader, `agents/mr_ab.mjs` = `forkD_mr_ab.mjs` here): one device, all variants alternated frame-by-frame with the queue drained after each, so load from sibling forks is shared; HEAD is run twice as a noise-floor control (control read 0.97–1.06). Separate-process timing was useless here (the same file read 6–16 ms across rounds at load 20–30).
  - galaxy final vs HEAD: 256² ×300 cycles twice → min 1.26/1.29, p25 1.10/1.21, paired-median 1.13/1.13; 384² ×200 cycles → min 1.32, p25 1.21, paired-median 1.26. ≈ 1.2–1.3× (cap ~1.3×). Ablation (noisy, 4 rounds) put the largest share on the dust lane (`cos`, `exp`, 2 smoothsteps, alpha floor) and ~10% on the HII knots; a candidate with the lane's `cos` replaced by a wrapped-phase parabola and the `exp` by a rational was measured no faster than the final version (1.13–1.29×), so the simpler `cos`/`exp` version stays.
  - lenia vs HEAD: 128² ×60 cycles twice → paired-median 1.02 / 0.98, min 1.00 / 0.82 (control 1.04–1.06): ≈ 1.0× (the added work is one 4-sin zone noise + a few smoothsteps against ~23² kernel taps).
- Reproducibility (this dir, `git add -f`): `forkD_lenia_model.py` (numpy port derived from scripts/sim_models/lenia_rescue.py with a mu override), `forkD_lenia_mu_sweep.py` (uniform-mu alive-band sweep), `forkD_lenia_zone_ab.py` + `.png` (uniform vs zoned A/B), `forkD_mr_ab.mjs`.
- Not done: real-GPU visual QA; upgrades:record / shader lists / verify:shaders:fix (coordinator). Not committed.
