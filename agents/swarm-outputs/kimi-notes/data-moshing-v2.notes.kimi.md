# data-moshing v2 — Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Structure tensor optical flow estimation via central differences (`gx`, `gy`). Eigenvector extraction gives motion direction (`flowDir`). Motion-compensated smearing replaces simple block offsets.
- **Visualist**: MPEG macro-blocking artifacts (`blockEdge` + `macroBlock`). DCT ringing simulation (`sin(ringUV * pi * 8)`). Chroma subsampling error (YCbCr conversion with offset UV sampling). VHS head-switching bands (`bandNoise` at 8 horizontal bands).
- **Interactivist**: Bass triggers I-frame corruption events (`corruptionEvent = step(0.65, bass * corruption)`). Mouse scrubs temporal buffer (`mouse.x - 0.5` drives horizontal offset). Depth controls compression quality / decay rate.
- **Optimizer**: 4-tap structure tensor (reuses center sample). Temporal offset stored in `dataTextureA` for next frame. Boundary clamp on all texture samples.

## Alpha Semantic
`alpha = clamp(corruptionConfidence * edgeStrength + color.a * 0.2, 0.0, 1.0)`
- `corruptionConfidence`: length of motion offset + bass-triggered event
- `edgeStrength`: MPEG macro-block edge detection

## Lines
151 lines (upgraded from ~90)

## Bindings
Canonical 13-binding header, exact `Uniforms` struct, `@workgroup_size(16, 16, 1)`.

## Chunks Used
- `hash12` (corruption block randomization)
- `hash22` (jump vector generation)

## Params
1. Smear Strength (`zoom_params.x`) — optical flow amplification
2. Block Size (`zoom_params.y`) — macro-block dimensions
3. Corruption (`zoom_params.z`) — bass-triggered event sensitivity
4. Quantize (`zoom_params.w`) — bit-crush levels
