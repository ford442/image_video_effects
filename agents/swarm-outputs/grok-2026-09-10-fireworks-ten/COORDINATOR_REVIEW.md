# Coordinator review — fireworks shell taxonomy ten

Batch: leftover named fireworks shells (Idea Cards still missing after Aug-23 plumbing). Idea Cards written in `BRIEFS.md` before WGSL.

| File | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not boilerplate | No overlay stamp | A packing honest | params exact | Springs native | Naga + audits |
|---|---|---|---|---|---|---|---|---|---|
| gen-fireworks-chrysanthemum | yes | pistil; lat/ringR3 | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-dahlia-burst | yes | imb; rib1/rib2 | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-crossette | yes | parent/fork; X flash | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-crackle-palm | yes | hostPos crackle; leaflets | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-willow-cascade | yes | hangT; burstLean | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-horse-tail | yes | pinch+parallel; sparkOut | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-kamuro-gold | yes | tw; hang plateau | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-ring-shell | yes | tilt; onHalo | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-strobe-shell | yes | per-spark phase; pow 10 | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-roman-candle | yes | muzzle; seq starCol | yes | yes | yes | display RGBA | yes | none | pass |

**Verdict: 10/10 pass.** Real-GPU visual QA remains external (Cloud VM has no adapter).

Gates: Naga 10/10, extraBuffer 0 new `[0..132]`, dead sliders 0, catalog 1,362, SKIP_WASM_BUILD=1 build green. Jest 652 pass / 6 fail = pre-existing WASM `bridge/api.js`.
