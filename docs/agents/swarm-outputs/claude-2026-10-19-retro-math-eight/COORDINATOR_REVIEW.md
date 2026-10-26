# Coordinator review — claude-2026-10-19-retro-math-eight

Self-review against §9 / §12.4 checklists (an external coordinator should re-check on a GPU).

| Shader | Card first | Ideas pointable | Keep verbatim | Not boilerplate | No shared overlay | Packing | Params | Spring/ripple | Gates |
|---|---|---|---|---|---|---|---|---|---|
| digital-glitch | ✓ | ✓ 3 | ✓ | ✓ | ✓ | ✓ | ✓ | existing only | ✓ |
| phosphor-decay | ✓ | ✓ 2 | ✓ | ✓ | ✓ | ✓ | ✓ | existing only | ✓ |
| vhs-chroma-bleed | ✓ | ✓ 2 | ✓ | ✓ | ✓ | ✓ | ✓ | none | ✓ |
| crt-tv | ✓ | ✓ 2 | ✓ | ✓ | ✓ | ✓ | ✓ | existing only | ✓ |
| poincare-tile | ✓ | ✓ 2 | ✓ | ✓ | ✓ | ✓ | ✓ | existing only | ✓ |
| anaglyph-3d | ✓ | ✓ 2 | ✓ | ✓ | ✓ | ✓ | ✓ | none | ✓ |
| complex-exponent-warp | ✓ | ✓ 2 | ✓ | ✓ | ✓ | ✓ | ✓ | none | ✓ |
| tile-twist | ✓ | ✓ 2 | ✓ | ✓ | ✓ | ✓ | ✓ | existing only | ✓ |

The three CRT/tape files (phosphor-decay, vhs-chroma-bleed, crt-tv) share a device family but no
mechanism: hyperbolic decay + glass ring, head switching + Y peaking, misconvergence + EHT
breathing. Formula names per file are in NOTES.md; no §12.2 row repeats. Pass (structural).
Visual QA pending.
