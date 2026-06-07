# Interactivist Upgrade Notes: coral-growth

## Changes Applied

1. **Bass Envelope (`bass_env`)**: Smoothed bass via `prev.r` from `dataTextureC` with 0.8 attack / 0.15 release. Growth speed and branch amplitude now pulse smoothly instead of strobing.

2. **Mouse Gravity Well**: The entire UV space is gravitationally bent toward the mouse cursor. Coral branches appear to grow toward the pointer, with well strength boosted by bass envelope.

3. **Click Shockwave Growth Burst**: Mouse down emits a radial shockwave that locally doubles growth speed (`shock * 2.0`), creating an emergent bloom effect around the cursor.

4. **Video Luma Spawn**: Samples `readTexture` luma; bright video regions spawn extra branch density (`lumaSpawn`), making the coral colonize bright areas of the input.

5. **Treble Tip Sparkle**: Exponential glow at branch tips driven by treble intensity, creating bioluminescent sparkles on active growth fronts.

6. **Semantic Alpha**: Alpha encodes `growth freshness * 0.4 + bass * 0.08 + mouseProx * 0.25`, mixed with temporal trail decay (`prev.a * 0.95`). Older growth fades gracefully.

## Line Count
175 lines (target ~170, within ±20%)
