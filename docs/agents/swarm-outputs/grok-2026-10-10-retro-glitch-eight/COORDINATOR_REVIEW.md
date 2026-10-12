# Coordinator review — retro-glitch eight (2026-10-10)

| Shader | Card before diff | Ideas pointable | Keep verbatim | No shared overlay | Packing matches C | Params exact | Naga |
|---|---|---|---|---|---|---|---|
| data-moshing | yes | macroblockMV, residualSpark | yes | yes | raw offset | yes | pass |
| data-moshing-diffusion | yes | tangentDiffusion, packetWake | yes | yes | raw offset; C.rgb mix removed | yes | pass |
| digital-decay | yes | blockTear, stuckRow | yes | yes | display RGBA | yes | pass |
| digital-waves | yes | standingNodes, crestScan | yes | yes | raw diagnostic, C unread | yes | pass |
| pixel-rain | yes | glyphTail, columnBlank | yes | yes | display RGBA | yes | pass |
| rgb-glitch-trail | yes | channelLag, persistenceComet | yes | yes | raw intensity | yes | pass |
| spectral-glitch-sort | yes | sortWalk, chromaSort | yes | yes | display RGBA | yes | pass |
| datamosh-brush | yes | dcHold, mosquitoRing | yes | yes | display RGBA | yes | pass |

Pass on all eight. Real-GPU visual QA was not run.
