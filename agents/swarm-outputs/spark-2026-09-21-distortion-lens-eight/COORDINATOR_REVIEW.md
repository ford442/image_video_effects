# Coordinator review — distortion lens eight

| Shader | Card before diff | Ideas pointable | Keep holds | Not boilerplate | No shared overlay | A matches C | Params exact | Springs/ripples native | Gates | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| gravity-well | ✅ | 2/2 | ✅ | ✅ | ✅ | ✅ (C unread) | ✅ | none added | ✅ | PASS |
| black-hole | ✅ | 2/2 | ✅ | ✅ | ✅ (image ring ≠ gravity-well's light ring) | ✅ | ✅ | none added | ✅ | PASS |
| heat-haze-gpt52 | ✅ | 3/3 | ✅ | ✅ | ✅ | ✅ | ✅ | none added | ✅ | PASS |
| zoom-burst | ✅ | 2/2 | ✅ | ✅ | ✅ (≠ interactive-zoom-blur's cards) | ✅ | ✅ | none added | ✅ | PASS |
| interactive-zoom-blur | ✅ | 2/2 | ✅ | ✅ | ✅ | ✅ (exact C now) | ✅ | none added | ✅ | PASS |
| infinite-zoom-lens | ✅ | 3/3 | ✅ | ✅ | ✅ | ✅ | ✅ | none added | ✅ | PASS, eyeball first |
| bubble-lens | ✅ (corrected) | 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | none added | ✅ | PASS |
| refraction-tunnel | ✅ (corrected ×3) | 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | none added | ✅ | PASS |

18 ideas, none repeated across files.

**Gates:** precommit 8/8 (naga + bindgroup) · audit:extrabuffer PASS · audit:dead-sliders PASS
(8 defs scanned, 0 new) · generate_shader_lists (no list changes; no JSON edits) · verify:catalog-counts
PASS · verify:wgsl-include green · `SKIP_WASM_BUILD=1 npm run build` OK · Jest 712 pass / 6 fail.
The failures are the four known WASM-bridge suites plus `slotLimits.contract.test.ts`, which is untracked
work from a concurrent session and fails the same way (`Cannot find module './bridge/api.js'`). None
are shader-related.

## Real-GPU visual QA — not done (no Vulkan ICD). Check these first:
1. **infinite-zoom-lens:** nesting inside the lens is the largest look change. Check that seams read as
   frames and the fall rate at Zoom Strength 0.45 is calm.
2. **black-hole:** the pre-existing `final_color * a` premultiply darkens the frame. Decide whether it's a bug.
3. **heat-haze-gpt52:** the ground line is fixed at y = 0.78. Check it on portrait photos, where a
   mirage across the subject's chest may look wrong.
4. **gravity-well:** the halo arc should sit behind the near disk. Check it's not a full ring at
   Lensing Order 1.
5. **refraction-tunnel:** hoop density near the vanishing point, and the wall-mirror seam at 0.8R.
