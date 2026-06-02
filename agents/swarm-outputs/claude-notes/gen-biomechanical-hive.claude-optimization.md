# gen-biomechanical-hive — Claude Optimization Notes
**Date**: 2026-05-31 (batch 2) | **Effort**: Medium-High | **Category**: generative

## Bottlenecks Identified

1. **No tone mapping at all** — Color was written raw to the texture after fog mixing. The glowing core material computes `baseColor = mixColor * (1.0 + pulse)` where pulse ∈ [0,1], plus `fbm(p*5.0) * 0.2` — easily exceeding 1.0. Without any tone-map, these emissive cores clipped to flat white/primary colors, losing all internal detail.

2. **plasmaBuffer declared but never read** — No audio reactivity. The hive's pulsing cores and hue-shifting biomass are natural audio targets.

3. **Header missing Complexity/Created/By/upgraded-rgba.**

## Optimizations Applied

| Change | Expected Impact |
|--------|----------------|
| **ACES filmic tone mapping (was none)** | Glowing chitin cores keep internal color detail instead of clipping |
| Bass → core pulse + bass×0.4 | Cores throb on the beat |
| Mid → hueShift + mid×0.1 | Biomass color breathes with the melody |
| IGN dither | No banding in near-black hive fog |
| Standard Hybrid Header | AGENTS.md compliant |

## Visual/Transcendence Notes
Adding tone mapping to a shader that had none is a bigger visual change than swapping Reinhard for ACES. Previously the biomechanical cores were harsh, posterized blobs of pure color (the `* (1.0 + pulse)` pushed them well past 1.0 and they just clamped). Now ACES rolls those highlights off smoothly — you can actually see the `fbm` texture detail and the color gradient within each glowing core. The cores read as living, internally-lit organs rather than flat emissive decals.

The bass-driven pulse syncs the entire hive's heartbeat to the music, while the mid-range hue breathing makes the biomass slowly shift color in response to the melody — an unsettling, organic responsiveness that suits the biomechanical horror aesthetic.

## Remaining Risks
- 128-step raymarch with `t += d` (full step) retained — the hex-prism/organic SDF is well-conditioned so no relaxation needed. If perf is tight, the same adaptive `select()` relaxation from celestial-forge/art-deco could apply, but it wasn't necessary here.
- `pulse = ... + bass * 0.4` can exceed 1.0 during loud bass, pushing `baseColor = mixColor * (1.0 + pulse)` higher — but ACES now handles this gracefully (it's the whole point of adding it). No clamp needed.
- The hueShift `+ mid * 0.1` could nudge hueShift past its 0..1 staged thresholds (0.3, 0.6) during loud mids, briefly snapping the color stage. Subtle; monitor on mid-heavy tracks.

## JSON Updates Suggested
```json
{
  "features": ["chitinous-shell", "organic-transparency", "core-bioluminescence", "audio-reactive", "ACES"],
  "tags": ["biomechanical", "hive", "organic", "chitin", "audio-reactive", "generative"]
}
```
