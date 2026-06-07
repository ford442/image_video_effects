# Interactivist Upgrade Notes: gen-metaball-soft-body

## Upgrades Applied
1. **Audio Envelope (`bass_env`)**: Raw bass replaced with attack/release-smoothed envelope stored in `dataTextureA.r`, read back from `dataTextureC.r`. Eliminates strobe artifacts; drives ball radius and overall brightness.
2. **Mouse Gravity Well + Click Shockwave**: Ball centers are attracted toward mouse cursor with inverse-square falloff. Mouse click emits an expanding sinusoidal shockwave that ripples the surface mask.
3. **Video Optical Flow**: Samples `readTexture` and warps pixel coordinates by luma-derived flow vectors, creating subtle video-reactive distortion.
4. **Treble Sparkle**: High-frequency sparkle particles bloom on the metaball surface driven by treble hits.
5. **Temporal Trails**: Previous frame color (from `dataTextureC.g/b`) is blended into current output for organic motion trails.
6. **Semantic Alpha**: Alpha now encodes `surfaceMask + mouseDown + trebleSpark` interaction intensity.

## Issues / Notes
- None. All bindings verified against 13-binding contract. Line count ~175 (target ~170).
