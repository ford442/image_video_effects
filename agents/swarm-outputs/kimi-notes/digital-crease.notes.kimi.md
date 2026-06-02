# digital-crease — Kimi Batch E Notes

## Changes Made
- Added temporal paper-fold persistence: `dataTextureC` stores previous fold state
- Added depth-curve distortion: depth scales fold amplitude
- Added chromatic folding: R/B channels sample from different crease depths
- Added bass-driven fold amplitude modulation
- Added crease glow: bass adds warm light along fold edges
- Shadow/highlight computation on crease boundary

## Wow Factor
- Paper folds now have memory — creases persist and deepen over time
- Chromatic separation makes folds look like prism edges

## Risks
- Temporal persistence may cause fold state to saturate to white over time
- `dataTextureC` read requires renderer ping-pong support
