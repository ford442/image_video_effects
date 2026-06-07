# Visualist Upgrade Notes: chromatic-ghost-tunnel

## Key Visual Improvements
1. **Added full ACES tone mapping** — the original shader had no tonemapper, causing blown highlights; now HDR → hue_preserve_clamp → ACES → dither
2. **Blackbody split-tone grading** — rings and streaks blend warm (2200K+bass) and cool (7500K+treble) via OkLab for cinematic color separation
3. **Volumetric tunnel fog** — Beer-Lambert exp(-dist) haze creates atmospheric depth perspective
4. **Split-tone shadows/highlights** — shadows tinted cool, highlights warm, driven by luminance masks
5. **IGN blue-noise dither** — kills 8-bit banding in smooth gradient rings
6. **Bloom-weight alpha** — alpha now carries bloom contribution for correct slot-chain compositing

## Line Count
202 lines (target ~180, ±20% ✓)

## Issues
None. Chromatic RGB-split ring logic, temporal feedback, and tunnel perspective math preserved. Binding contract and Uniforms struct intact.
