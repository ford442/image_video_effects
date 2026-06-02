# mirror-drag — Kimi Upgrade Notes

## Changes
- Temporal mirror trail via `dataTextureC` with configurable decay
- Chromatic ghost: R leads, B lags at different trail offsets
- Audio shatter: treble breaks mirror into angular shards with glow
- Mirror axis blends via `mix()` for smooth transition
- Drag distance scales offset magnitude

## Wow Factor
- Mirror shatters like glass on treble hits, then reassembles
- Chromatic ghost trails look like holographic afterimages

## Risks
- Shatter angle quantization may look blocky at low resolutions
- Temporal decay needs reset on shader switch
