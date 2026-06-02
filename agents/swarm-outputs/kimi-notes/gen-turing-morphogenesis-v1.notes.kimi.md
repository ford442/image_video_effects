# gen-turing-morphogenesis — Kimi Notes

## Changes
- Deterministic activator-inhibitor reaction-diffusion using layered value noise.
- Three pattern regimes (spots, stripes, labyrinth) selected by feed/kill difference thresholding.
- Chromatic aberration via per-channel activator-inhibitor evaluation at offset UVs.
- Temporal persistence via `dataTextureC` blend with bass-modulated decay.
- Mouse deposits activator seed as Gaussian blob.
- Depth scales pattern resolution and modulates overall alpha.
- Organic palette: cream, ochre, umber, sage, rust with HDR bloom on high-curvature boundaries.
- ACES tone mapping on final color.

## Wow-Factor
- Patterns morph between spots, stripes, and labyrinth as bass modulates feed/kill.
- Organic color palette feels like biological tissue under a microscope.
- Temporal persistence makes growth feel alive and continuous.

## Risks
- `activatorInhibitor` does 4 noise samples per channel × 3 channels = 12 vnoise calls per pixel.
- Could be heavy on low-end GPUs; consider reducing octaves if needed.
- Chromatic aberration offset is small but adds 2 extra noise evaluations.
