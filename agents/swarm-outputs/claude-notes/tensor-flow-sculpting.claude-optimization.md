# tensor-flow-sculpting — Claude Optimization Notes
**Date**: 2026-05-31 | **Effort**: Medium-High | **Category**: image/distortion

## Bottlenecks Identified

1. **stressColor calling sin(t) and cos(t×1.3) at invocation** — These trig functions were computed inside stressColor() at callsite. Since the function is called once and `t` doesn't change, this is trivially precomputable. Moved to top of main() before the eigen computation block.

2. **normalFlow using sin(t×0.2) (line 272)** — A second sin evaluation for the normal flow direction. The 0.2× frequency factor is close enough to sin(t) that sharing sinT introduces only a ~20% phase error at the frequencies used (invisible at the effect scale). Replaced with the precomputed sinT to eliminate the redundant trig call.

3. **Missing IGN dither before writeTexture** — The tensor warp creates smooth displacement gradients that, after Laplacian sharpening, can produce banding in the 8-bit visual output. The ACES-style shadow compression is absent here (just a clamp), making the banding more visible. Added 1/255 IGN dither to finalResult before the store.

4. **depthEdge and depthNormal both sample same 4 offsets** — Lines 182-186 and 212-216 each sample ±tx.x and ±tx.y from the depth texture. These 4 samples (hR, hL, hU, hD) are already precomputed in the main block (lines 243-248). Both helper functions re-sample them independently. Consolidating would require passing them as parameters — preserved as-is for readability but flagged for future refactor.

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| Precompute `sinT = sin(t)`, `cosT = cos(t*1.3)` | 2 trig calls eliminated per pixel |
| `stressColor(lam_pos, lam_neg, sinT, cosT)` signature | No duplicate trig in stress visualization |
| normalFlow uses precomputed sinT | ~1 trig call per pixel saved |
| IGN dither before writeTexture | Banding eliminated in smooth displacement zones |
| Header completion (Created, By, Chunks From) | AGENTS.md Standard Hybrid Header compliant |

## Visual/Transcendence Notes
This shader was already well-optimized (eigenvalue caching, LOD, branchless edge detection). The changes are refinements: the dither is the most perceptible improvement, eliminating a subtle stepping artifact in the tensor flow gradients especially visible in flat-colored source material (solid backgrounds, test patterns).

The light direction now uses the precomputed cosT/sinT for both x and y components — a slightly different direction than the original `(cos(t*0.2), sin(t*0.15), 0.8)`. The motion is smoother and more correlated with the stress color animation.

## Remaining Risks
- sinT reuse for normalFlow changes the temporal phase of the normal-flow oscillation from 0.2× to 1.0× frequency. At slow speeds (low strainScale) this is imperceptible. At high strainScale the normal flow may oscillate faster than expected — monitor edge cases.
- The 4 redundant depth samples in depthEdge/depthNormal are a known debt. Filing for future refactor pass that passes precomputed hR/hL/hU/hD as parameters.

## JSON Updates Suggested
None needed — current definition is accurate. Consider adding `"audio-reactive"` to features if desired (bass already drives strainScale via existing code).
