# emergent-calligraphic-weave — Kimi Notes

## Changes
- Chromatic ink gradients: stroke color shifts from warm to cool along stroke length.
- Audio-driven field chaos: `bass` increases turbulence in orientation field, `mids` boosts coherence.
- Depth-scaled stroke density: reads `readDepthTexture` to thin strokes in distant regions.
- Temporal accumulation via `dataTextureC` advection and `dataTextureA` persistence.
- Mouse orients local field toward cursor when active.

## Wow-Factor
- Calligraphic glyphs self-organize from pure noise; the orientation field feels alive.
- Depth-scaled density creates a parallax calligraphy effect — foreground strokes are bold, background delicate.

## Risks
- Stroke advection requires two texture fetches (current + upstream); total fetches can grow with long strokes.
- Field coherence vs chaos balance is sensitive; may need parameter retuning after audio reactivity changes.
