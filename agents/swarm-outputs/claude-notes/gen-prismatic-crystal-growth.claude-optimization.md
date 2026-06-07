# gen-prismatic-crystal-growth — Claude 3E Polish (E2) (2026-06-07)

## Bottlenecks Identified
- 120-step raymarch with a fixed `0.7×` stride conservatively over-samples empty space toward the horizon (camera orbits at distance 6, far plane at 30).
- `crystalCaustics` (refract + 3 sin evaluations) ran unconditionally on every crystal hit, including thin edges (`thickness` near 0) where `causticStrength * thickness` makes the contribution imperceptible.
- Crystal hue used a 6-branch if/else cascade for HSV→RGB, each branch adding a constant floor offset (0.2–0.3) to the "off" channels.
- Chromatic aberration strength used raw `bass` even though the shader already smooths it via `bass_env` into `smoothBass` for growth-rate driving.

## Optimizations Applied
- **Distance-based ray-step LOD**: `stepLOD = mix(0.7, 1.0, smoothstep(0.0, 20.0, t))` — stride relaxes from 0.7× near the camera (where lattice silhouette detail matters) to 1.0× past `t=20`, trimming iterations in the empty-space-heavy outer two-thirds of the march.
- **Caustics early-exit**: gated `crystalCaustics` behind `if (causticStrength * thickness > 0.04)`, skipping the refract/sin chain on thin edges where the contribution would be invisible under the existing alpha falloff.
- **Branchless hue-to-RGB**: replaced the 6-way if/else chain with `max(hueToRGB(hue), vec3(0.2))` — same vibrant-with-floor look (the original's per-branch 0.2/0.3 offsets collapse to a single 0.2 floor, visually equivalent at this saturation), zero divergent branches.
- **bass_env reuse**: chromatic-aberration strength now reads `smoothBass` instead of raw `bass`.
- Synced header `Features:` with JSON (`chromatic-aberration`, `raymarched`, `distance-lod`).

## Visual / Transcendence Notes
- LOD relaxation is invisible in practice — the temporal blend (`mix(color, prevColor, 0.08)`) and background gradient absorb any residual under-stepping at the horizon.
- Caustic gating only skips work on near-transparent edges; thick crystal cores (where caustics read clearly) are unaffected.

## Remaining Risks
- If users crank `causticStrength` toward 1.0, the `0.04` gate threshold corresponds to `thickness > 0.04`, which is nearly always true — the early-exit mostly helps at low/mid caustic-strength settings. Could make the threshold itself a function of `causticStrength` if profiling shows it matters.

## JSON Changes
- Added `distance-lod` to `features`.
