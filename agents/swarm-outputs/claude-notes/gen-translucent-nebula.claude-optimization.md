# gen-translucent-nebula — Claude 3E Polish (E1) (2026-06-07)

## Bottlenecks Identified
- Fixed 8-layer volumetric ray accumulation runs at full cost across the entire frame, including peripheral pixels where less density detail is perceptible.
- Chromatic aberration strength was driven by raw `bass` (the shader already computed a smoothed `smoothBass` via `bass_env` for pulsing, but didn't reuse it for the CA split — strobe-prone).
- `nebulaColor`'s hue-rotation used a 6-branch if/else cascade for HSV→RGB conversion.
- Header `Features:` was missing `chromatic-aberration` despite the shader computing CA and the JSON declaring it (drift).

## Optimizations Applied
- **Distance-based layer LOD**: `layers = i32(mix(8.0, 5.0, smoothstep(0.25, 0.6, distFromCenter)))` — volumetric march relaxes from 8 samples at screen center to 5 toward the edges (`zStep` derives from the same value), cutting ~3 density/color evaluations per peripheral pixel.
- **Branchless hue-to-RGB**: replaced the 6-way if/else chain with `hueToRGB(hue)`, the standard `clamp(abs(h6-k)-j, 0, 1)` triplet formula — same output, no divergent branches.
- **bass_env reuse**: chromatic-aberration strength now reads `smoothBass` (already computed for the pulse) instead of raw `bass`, removing a second independent audio-reactive path and matching the F1 "smoothed envelope, not raw strobe" mandate.
- Synced header `Features:` to include `chromatic-aberration` and the new `distance-lod` tag (also added to JSON `features`).

## Visual / Transcendence Notes
- Edge layer reduction is masked by the existing front-to-back alpha falloff and star-field overlay — center (where the eye focuses) keeps full 8-layer density resolution.
- CA now pulses in sync with the nebula's bass-driven expansion rather than flickering on raw transients — reads as more "breathing," less "glitchy."

## Remaining Risks
- LOD threshold (`smoothstep(0.25, 0.6, ...)`) is conservative; could push toward 4 layers at the extreme edge if profiling shows headroom.

## JSON Changes
- Added `distance-lod` to `features` (header already listed `chromatic-aberration`/`distance-lod` post-fix; JSON gains `distance-lod`).
