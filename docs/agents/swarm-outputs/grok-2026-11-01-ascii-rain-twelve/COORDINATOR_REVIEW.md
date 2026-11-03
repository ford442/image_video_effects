# Coordinator review — ASCII / glyph / digital-rain twelve

Reviewed against `docs/agents/swarm-outputs/grok-2026-11-01-ascii-rain-twelve/BRIEFS.md`. Cards were written before the WGSL edits.

Formula check: no §12.2 row is used. The batch does not share a white-hot leader, a cell gutter, or a new spring.

| Shader | Card before diff | Ideas pointable | Keep holds | Not boilerplate | No shared overlay | Packing matches C | Params exact | Spring only if native | Naga / extraBuffer / sliders | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| ascii-decode | yes | falling head, gutter, decode rim | 7 glyphs, mask, strength | yes | its own | display RGBA; C is display green hold | yes | no spring | pass | pass |
| ascii-flow | yes | flow lean, upstream streak | ramp, wake, vortex | yes | its own | display RGBA | yes | existing pointer, no new spring | pass | pass |
| ascii-glyph | yes | stroke weight, lens bezel | cross/dot, smear, scanline, spring | yes | its own | display RGBA | yes | existing spring, now (0,0) writer | pass | pass |
| gen-cyber-terminal | yes | barrel scanlines, corner misconvergence | segment font, leader, gaps, HDR A | yes | its own | raw HDR in A, ACES on write | yes | no spring | pass | pass |
| matrix-curtain | yes | tail stem, curtain hem | gol hash, scan/ghost, C.r from above | yes | its own | raw fields, ACES on write | yes | no spring | pass | pass |
| pixel-rain | yes | head core, sheet stagger | three sheets, tail, blank, spring | yes | its own | display RGBA | yes | existing spring | pass | pass |
| spectral-rain | yes | streak core, column slant | FFT trail, splash, R/G/B split | yes | its own | display RGBA, C unread | yes | existing spring, now (0,0) writer | pass | pass |
| cyber-rain | yes | beaded drop, wiper lip | blur, EMP, wet trail, envelope in A.a | yes | its own | pre-ACES trail + envelope | yes | existing wiper spring | pass | pass |
| cyber-rain-interactive | yes | head flicker, far-sheet grey | ROM, fp128, packet, no spring | yes | its own | display RGBA | yes | stays spring-free | pass | pass |
| retro-gameboy | yes | slow rise, unlit well | four greens, round dots, ghost | yes | its own | display RGBA | yes | no spring | pass | pass |
| flip-matrix | yes | hinge pin, gutter shadow | mirror, cam notch, projection | yes | its own | display RGBA | yes | no spring | pass | pass |
| bayer-dither-interactive | yes | error coring, tile seam | 8×8, IGN, channel rotation | yes | its own | display RGBA, C unread | yes | no spring | pass | pass |

12/12 pass. Real-GPU visual QA is external.
