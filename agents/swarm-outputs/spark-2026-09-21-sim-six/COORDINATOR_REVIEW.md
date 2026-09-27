# Coordinator review — stateful-simulation six

| Shader | Card first | Ideas pointable | Keep holds | Not boilerplate | Distinct | A matches C | Params exact | Gates | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| boids | ✅ | 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | PASS |
| ion-stream | ✅ | 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | PASS |
| sim-ink-diffusion-rgba | ✅ (idea 1 corrected, evidence) | 2/2 | ✅ state rule untouched | ✅ | ✅ | ✅ | ✅ | ✅ | PASS |
| steamy-glass | ✅ (tuning corrected, evidence) | 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | PASS |
| sim-fluid-feedback-coupled | ✅ | 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | PASS |
| photonic-caustics | ✅ | 2/2 | ✅ | ✅ | ✅ | ✅ (fixed) | ✅ | ✅ | PASS, eyeball first |

12 ideas, none repeated, no springs, ripples, palettes or audio-dependent ideas.

**Gates:** precommit 6/6 · audit:extrabuffer PASS · audit:dead-sliders PASS (6 scanned, 0 new) ·
generate_shader_lists (simulation.json +3 tags) · verify:catalog-counts PASS · verify:wgsl-include green ·
`SKIP_WASM_BUILD=1 npm run build` OK · Jest 712 pass / 6 fail: the known `./bridge/api.js` suites
(4 pre-existing + the untracked slotLimits test from a concurrent session). Nothing shader-related.

**CPU-verified dynamics:** steamy-glass rivulets (onset, density, extremes). Rejected in simulation before
WGSL: the state-based ink coffee ring. The simulations also removed lenia and multi-turing from the batch.

## Real-GPU checks, in priority order
1. **photonic-caustics:** the packing fix changes brightness (less washed out). Check caustic lines at
   depth edges aren't harsh.
2. **steamy-glass:** wait ~10 s at default fog for the first drips; check the bead highlight scale.
3. **boids:** blind spot should string the flock into lines; hold on it to see the split.
4. **sim-fluid:** at Fade Rate 0 (long-lived dye), check the sinking dye doesn't just pool at the bottom.
