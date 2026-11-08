# sonnet/batch-20 — coordinator review

Independent review: REVIEW.md (10 findings). Every finding is either fixed or disclosed below.
Renders: agents/minirender.mjs on SwiftShader, JSON-default sliders passed explicitly. **Real-GPU visual QA is external.**

## Pass / fail per card
| shader | cards | verdict | notes |
|---|---|---|---|
| topological-acoustic-knots | 3 (polarizer brushes, Michel–Lévy tint, Kibble–Zurek quench) | PASS | rescue: black at any audio ≥ 0.1 at HEAD; quench noise rewritten smooth after REVIEW #1; 192/384/576 px look the same |
| acoustic-string-theory | 3 (sympathetic resonance, pitch glide, nodal pins) | PASS | ideas 1–2 are click-only (ablation diff 10.4 / 9.0); pins idle-visible; `fract(time)` + `sq()` after REVIEW #2/#6 |
| gen-string-theory | 2 (Melde envelope, fretting finger) | PASS | `params` added (behaviour change, disclosed); `tFac` removed (REVIEW #4) |
| gen-audio-spirograph | 3 (gear + pen arm, no-slip teeth, ink pooling) | PASS | mechanism faint at defaults, clear at Trail Length 0.05; teeth capped at ~4 px pitch |
| gen-grokcf-interference | 2 (sand, modal strike) | PASS | 4 floor rescues (FFT bins, dead click gate, overlay gain, aspect) |
| gen-void-harmonic-cymatic-resonator | 2 (radial breathing, schlieren) | PASS | 180° camera flip fix + 3 exposure constants (look change, disclosed) |
| gen-stellar-acoustic-resonance-manifold | 3 (limb darkening, Dopplergram, stochastic excitation) | PASS-WITH-NITS | Doppler boosted after REVIEW #8; still the subtlest idea |
| gen-quantum-superposition | 2 (de Broglie carrier, breathing packets) + compositing | PASS | |
| gen-quantum-resonance-lattice | 2 (probability cloud, lattice phonon) | PASS | `pow(neg,2.0)` → `x*x`, mouse-y un-mirrored, camera off the node column (REVIEW #10) |
| gen-acid-lissajous | 2 (continuous tube, phosphor comet) | PASS-WITH-NITS | `SAMPLES` 64 (REVIEW #3); spring still dead in extraBuffer (pre-existing, untouched) |

## Formulas (§12.2)
No §12.2 row is used in any file. All ideas are tactic-derived (physics mechanisms: nematic Q-tensor, crossed polarizers, Michel–Lévy retardance, 8-point plaquette winding, sympathetic resonance, Melde envelope, spirograph kinematics, de Broglie carrier, Dopplergram, etc.), so the ≤2-files-per-formula rule is not engaged.

## Gates run after the last edit
- `wgsl_precommit_gate.py --files` on all 10: naga OK, bindgroup compatible, 0 extraBuffer violations, 0 pasted headers.
- `audit_dead_sliders.py` (10 files): 0 dead, 0 errors. `audit_extrabuffer.py`: 0 out-of-range writes. `audit_audio_mappings.py`: 24/24. `audit_config_y_misuse.py`: none of the ten files listed; every `u.config.y` read in the ten is a ripple count.
- minirender: `nan: 0`, `verr: null` for every file at the final renders (coord/, forkA/, forkB/).

## Known open items
- Real-GPU look and cost (SwiftShader only here). rgba16float tier behaviour is covered by the `fract(time)` fix but not run.
- gen-string-theory default sliders change from 0.5×4 to (0.5, 0.6, 0.85, 0.5) because `params` now exist.
- Resonator default look: rotated 180° and exposure constants changed.
- Stellar Dopplergram and limb darkening are subtle by design.
