# Coordinator review — flow-lattice ten (2026-11-15)

Reviewed against `BRIEFS.md` and the diff. Cloud VM has no GPU. Pass/fail is structural.

Formula use this batch:

| §12.2 row | Files |
|---|---|
| Fresnel–Schlick (§12.2F) | `sphere-projection` only |
| Fold-count material (§12.2E) | `gen-aetheric-tachyon-lattice` only |

No other row is used. No row is on two files.

| Shader | Card before diff | Ideas pointable | Keep verbatim | Overlay | Packing | Params | Springs | Verdict |
|---|---|---|---|---|---|---|---|---|
| quantum-field-visualizer | yes | envelope at `enveloped`; wake at `wakeUv` | slits, barrier, collapse, photo mix | no | ACES display, C matches | exact | none added | pass |
| pixel-wind-chimes | yes | `hardware`; `smearAmt` | strips, Z-sort, hinge | no | ACES display | exact | none | pass |
| interactive-pcb-traces | yes | `fillet`; `n1`/`n2` | Manhattan net, packet, injections | no | ACES display | exact | none added | pass |
| hypnotic-spiral | yes | `lead`; `streakUv` | log/Archimedean, tangent ride, clicks | no | ACES display | exact | none | pass |
| cellular-automata-3d | yes | `state.y`; `state.z`; `edge` | 4–6 / 5–7, march, existing spring | no | ACES display | exact | existing only | pass |
| gen-aetheric-tachyon-lattice | yes | `folds`; `junction` | folds, three tubes, tachyon sine, held warp | no | ACES display, C unread | exact (3) | none | pass |
| ion-stream | yes | `pinch`; `packetWidth` and `fieldB * 1.35` | curl, charge split, cyclotron, wake | no | ACES display | exact | none | pass |
| sphere-projection | yes | `fres`; `spec` | sphere hit, Lambert, graticule, slick | no | ACES display | exact | none | pass |
| gen-hypnotic-vortex-tunnel | yes | `hoop`; `flight` streak | contra-spin, seams, shear, disk | no | ACES display | x-meta four, all read, none added | none | pass |
| psychedelic-noise-flow | yes | `along`; `wakeUv` | noise warp, filament, vortex, clicks | no | ACES display | exact | none | pass |

- [x] Idea Cards exist and were written before the WGSL
- [x] Each numbered idea is pointable in the WGSL
- [x] KEEP VERBATIM still holds
- [x] Diff is not mostly header / ACES / spring boilerplate. ACES is new only where the file stored linear or gamma colour (`ion-stream`, `sphere-projection`, `psychedelic-noise-flow`, `gen-aetheric-tachyon-lattice`)
- [x] No shared spring, ripple stamp, or palette across the ten
- [x] A packing matches how C is read
- [x] Saved `params` unchanged
- [x] Springs only where `cellular-automata-3d` already had one
- [x] Naga 10/10, precommit gate 10/10, extraBuffer clean, dead sliders clean (9 definitions with a `params` array; `gen-hypnotic-vortex-tunnel` has none and was not given one)
- [x] Mechanism interrogation is in `BRIEFS.md`
- [x] Formula names are in `NOTES.md` and on the `Ideas:` lines
- [x] No §12.2 row on more than one file
- [x] Each formula uses a quantity the file already computed
- [x] No `fwidth` / `dpdx`. New `pow` bases are `1 - ndv` and `max(dot, 0)`. Packet and shock radii are squared, not `pow` on a signed base

Gates after the cards: Naga 10/10, precommit 10/10, extraBuffer clean, dead sliders clean, `verify:shaders:fix` 11/11, catalog regen, `npm run build` succeeded. Full Vitest: 1782 passed, 40 failed on timeouts, 1 skipped. A quiet re-run of those 18 files passed (195 tests, 1 skipped). `physarum_agents.py` and `sph_fluid.py` were not re-run. Ledger recorded for these ten ids.
