# 4d-projection-dream-weavers — Kimi Notes

## Changes
- Chromatic separation per noise octave: RGB channels sample at different 4D coordinate offsets.
- Temporal 4D coordinate drift: `time` advances the w-dimension slowly, creating morphing structures.
- Mouse-driven hyperplane navigation: XY controls z and w slice positions.
- Audio modulates scale (`mids`), speed (`bass`), and detail (`treble`).
- `writeDepthTexture` output for depth-aware downstream compositing.

## Wow-Factor
- True 4D exploration via mouse; users navigate a hypercube slice in real time.
- Chromatic octave splitting gives the fractal a prismatic, oil-slick quality.

## Risks
- `noise4D` tri-linear interpolation is 16 hash evaluations per call; 3 octaves × 3 channels = 144 hashes per pixel.
- May benefit from reduced octaves on low-end GPUs; consider a `detail` parameter LOD gate.
