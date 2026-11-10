# sonnet/batch-35 — COORDINATOR_REVIEW (self-review against SHADER_UPGRADE_BATCH §9 / §12.7)

Reviewer note: this review was written by the same agent that wrote the batch. It checks the diff against the cards; it is not an independent review and does not replace GPU QA.

| id | Card before diff | Ideas pointable (`// ── Idea n`) | KEEP holds | Boilerplate < 70 % | No shared overlay | Packing truthful | Params exact | Springs/ripples native | Naga+extraBuffer+dead-slider | Result |
|---|---|---|---|---|---|---|---|---|---|---|
| fiber-optic-weave | ✓ | ✓ 1,2 | ✓ | ✓ | ✓ | ✓ | ✓ | none added | ✓ | PASS |
| biomimetic-scales | ✓ | ✓ 1,2 | ✓ (+ unit fix reported) | ✓ | ✓ | ✓ | ✓ | none added | ✓ | PASS — **needs GPU look** (rescue changes output) |
| breathing-kaleidoscope-morph | ✓ | ✓ 1,2 | ✓ | ✓ | ✓ | ✓ | ✓ | none added | ✓ | PASS |
| gen-magnetic-liquid-glyphs | ✓ | ✓ 1,2 | ✓ (wheel moved verbatim) | ✓ | ✓ | ✓ (pre-spike d kept) | ✓ | none added | ✓ | PASS — perf check on mobile |
| mouse-wormhole-lens | ✓ | ✓ 3,4 (+shipped 1,2) | ✓ | ✓ | ✓ | ✓ | ✓ | none added | ✓ | PASS |
| gen-cymatic-void-glass-geode | ✓ | ✓ 1,2 | ✓ | ✓ | ✓ | ✓ | ✓ | none added | ✓ | PASS — AO tuning may be needed |
| gen-mushroom-mandala-garden | ✓ | ✓ 5,6 (+shipped 1–4) | ✓ | ✓ | ✓ | ✓ | ✓ | none added | ✓ | PASS |
| optical-illusion-spin | ✓ | ✓ 1,2 | ✓ | ✓ | ✓ | ✓ | ✓ | none added | ✓ | PASS |
| glass-wipes | ✓ | ✓ 1,2 | ✓ | ✓ | ✓ | ✓ raw A | ✓ | none added | ✓ | PASS |
| steampunk-gear-lens | ✓ | ✓ 1,2 | ✓ | ✓ | ✓ | ✓ | ✓ | none added | ✓ | PASS |

## §12.7 additions
- [x] `BRIEFS.md` carries the mechanism interrogation (T-numbers) per file.
- [x] Formula rows named: Cauchy (fiber), Step-count AO (cymatic), thin-lens inversion (glass-wipes), Brown–Conrady (steampunk). Each on exactly one file.
- [x] Every formula consumes a quantity the file already had (`pluck` bends, `dist`/`layerDepth`, `mirroredAngle`/`topHat`, the glyph SDF, `spiral` rate, `disp`/`map`, `gillPhase`/`myceliumPhase`, `alt`/`radius`, `drop`/`cell`/`sweepT`, `r`/`gear_r`). No new state, binding, solver or spring.
- [x] No `fwidth`/`dpdx`; no unguarded `pow` base; ACES inputs clamped where touched.

## Honest weak spots
- Idea 2 of `breathing-kaleidoscope-morph` and idea 4 of `mouse-wormhole-lens` are quieter than the others; both are additive and gated by existing quantities.
- `gen-mushroom-mandala-garden` was already at the four-idea ceiling from 2026-10-10; this is a deliberate second pass of two.
- The contact shadow (biomimetic) and residue line (glass-wipes) amplitudes are untuned guesses.
