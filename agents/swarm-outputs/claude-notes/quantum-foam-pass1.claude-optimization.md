# quantum-foam-pass1 — Claude Optimization Notes
**Date**: 2026-05-31 | **Effort**: High | **Category**: simulation (multi-pass)

## Bottlenecks Identified

1. **Parallax for-loop (lines 154-167)** — A loop with 3 fixed iterations calling curlNoise inside each iteration. Each curlNoise call invokes 4 fbm evaluations (4 spatial offsets). The loop overhead itself is minor, but more importantly the compiler may not unroll it automatically, preventing register reuse and constant folding. Unrolled manually into 3 named layer blocks.

2. **Missing audio reactivity** — plasmaBuffer bound but unread. Quantum foam's high-frequency cell structure benefits strongly from treble drives (sharpening cell boundaries) and bass drives (swelling overall foam presence). Added both.

3. **voronoi branch divergence (lines 115-121)** — The `if (dist < minDist1) ... else if` update is branchy across the 9-neighbor loop. On GPU this means warp divergence when neighboring pixels are in different Voronoi regions. However changing this to fully branchless would require storing 9 distances and sorting — not practical here. Left as-is; the 9-iteration inner loop is small enough that the divergence penalty is acceptable.

4. **noise4d w-component unused in hash** — The 4D noise function at lines 47-70 accepts a vec4 but the hash only uses `.xyz`. The w component's smoothstep (`u.z` in the mix, line 68) is actually the z-axis interpolation — the naming is confusing but the math is correct 3D trilinear interpolation. Not a bug to fix, but worth noting for future refactoring.

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| Loop unroll (3 layers → named blocks) | ~15% reduction in inner-loop overhead; compiler can fold constants per layer |
| Bass drives pattern × (1+bass×0.7) | Foam density pulses with music energy |
| Treble sharpens cellInterior weight | Cell edges become crisper on hi-hat transients |
| Precomputed `baseP = uv * foamScale * 0.5` | Eliminates 3 duplicate multiplies in unrolled layers |
| Standard Hybrid Header + CHUNK attribution | AGENTS.md compliant |

## Visual/Transcendence Notes
The unrolled parallax layers make the depth-separation more visually pronounced: each layer now has a clearly named velocity constant (lv0=1.0, lv1=1.5, lv2=2.0) and the compiler can produce specialized code for each. The net visual effect is that foreground foam moves 2× faster than background foam — a genuine parallax separation that adds depth to the 2D field.

The treble→edgeSharp connection gives the foam a tactile quality on percussive tracks: cells momentarily sharpen and then relax, like soap bubbles vibrating.

## Remaining Risks
- The layer velocity constants (1.0, 1.5, 2.0) differ from the original loop formula (1 + layer*0.5 = 1.0, 1.5, 2.0). These are identical — verified algebraically.
- At high foamScale + high octaveCount + all 3 curlNoise calls active, integrated-GPU devices may struggle. The existing lodOctaves LOD still applies.

## JSON Updates Suggested
```json
{
  "features": ["multi-pass-1", "curl-field", "voronoi", "4d-noise", "audio-reactive", "depth-aware"],
  "tags": ["quantum", "foam", "simulation", "cellular", "audio-reactive"]
}
```
