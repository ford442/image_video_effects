# Interactivist Upgrade Notes: acoustic-string-theory

## Changes Applied

1. **Bass Envelope (`bass_env`)**: Replaced raw `plasmaBuffer[0].x` with attack/release smoothed envelope using `prev.r` from `dataTextureC` (0.8 attack, 0.15 release). Eliminates frame-to-frame strobing.

2. **Mouse Gravity Well**: Mouse position creates a gravitational attractor that bends string space toward the cursor. Strength scales with the smoothed bass envelope for emergent pulsing attraction.

3. **Click Shockwave**: Mouse down triggers a radial sine ripple that propagates through strings, displacing wave phases locally. Decays with distance from cursor.

4. **Video Luma Feedback**: Samples `readTexture` and uses luma threshold to boost overall string brightness, making the shader reactive to video input.

5. **Treble Sparkle**: Hash-thresholded sparkle particles spawn on nodes driven by treble intensity, adding high-frequency visual grit.

6. **Depth AO**: Reads `readDepthTexture` per pixel and applies exponential ambient occlusion darkening for depth-aware compositing.

7. **Semantic Alpha**: Alpha now encodes `presence * 0.65 + mouseProx * 0.2 + bass * 0.12`, blended with a temporal trail age (`prev.a * 0.96`). Trail decay creates natural motion blur.

## Line Count
157 lines (target ~170, within ±20%)
