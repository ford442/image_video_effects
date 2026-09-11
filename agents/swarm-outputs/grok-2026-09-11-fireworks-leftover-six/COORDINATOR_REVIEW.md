# Coordinator review — fireworks leftover atmospheric six

Batch: the six atmospheric / conductor / spread fireworks skipped by yesterday’s named-shell ten. Idea Cards written in `BRIEFS.md` before WGSL.

| File | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not boilerplate | No overlay stamp | A packing honest | params exact | Springs native | Naga + audits |
|---|---|---|---|---|---|---|---|---|---|
| gen-fireworks-fan-shell | yes | palmette; eyeGate | yes (Batch 37 physics kept) | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-comet-trail | yes | ionTail; coma softGlow | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-smoke-bloom | yes | puffCenter buoyancy; flashLit | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-wind-ripple | yes | altitudeShear; leeward | yes | yes | yes | display RGBA | yes | none (click ripples kept) | pass |
| gen-fireworks-nocturne | yes | muzzle; droopHabit | yes | yes | yes | display RGBA | yes | none | pass |
| gen-fireworks-audio-symphony | yes | idle/onset mix; starTint | yes | yes | yes | display RGBA; [133] envelope | yes | none | pass |

**Verdict: 6/6 pass.** Real-GPU visual QA remains external (Cloud VM has no adapter).

Gates: Naga 6/6, extraBuffer 0 new `[0..132]`, dead sliders 0, catalog 1,363, SKIP_WASM_BUILD=1 build green. Jest 652 pass / 6 fail = pre-existing WASM `bridge/api.js`.
