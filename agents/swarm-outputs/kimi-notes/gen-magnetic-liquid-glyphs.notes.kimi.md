# gen-magnetic-liquid-glyphs — creation notes (Batch 16, C2)

> kimi-cli timed out twice on this brief (420s, 0 bytes), so it was completed
> manually to the same creative brief on 2026-07-18.

## What was built
- SDF rune wheel: central glyph + 6 ring glyphs, each a seeded 3-stroke rune (spine + 2 angled strokes + optional dot), blended with `smin` for liquid merging, 177 lines.
- Magnetic field angle = mouse X drag + slow mids-driven drift; the whole glyph field rotates with it.
- Domain warp inversely driven by bass envelope (bass → glyphs resolve) and positively by treble envelope (treble → auroral shatter).
- Metal shading: finite-difference normal, field-aligned light, fresnel rim, bass-boosted specular.
- Treble auroral emission concentrated on the liquid edge; bass flash on rune cores.
- Transmission alpha: `mask * mix(1.0, 0.4, depth) + edge*0.3*(1-depth*0.5)` — foreground metal opaque, background transmits.
- Stack: `huePreserveClamp` → `acesToneMap` → centered IGN dither → premultiplied alpha.
- `dataTextureA` stores envelopes + signed distance for potential next-frame use.

## Validation
- `naga` OK; no banned tokens; `wgsl_precommit_gate` OK.

## JSON
- New def `shader_definitions/generative/gen-magnetic-liquid-glyphs.json` (params: Glyph Scale, Chaos, Aurora Emission, Hue Base).

## Differentiation check
- Unlike `gen-auroral-ferrofluid-monolith`: darker iron palette, transmission alpha, seeded-rune wheel instead of monolith forms.
- Unlike `gen-magnetic-ferrofluid-sculpture`: dynamic audio envelopes + glyph semantics, not static sculpture.
