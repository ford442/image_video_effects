# Interactivist Upgrade Notes: gen-fourier-epicycles

## Upgrades Applied
1. **Audio Envelope (`bass_env`)**: Smoothed bass in `dataTextureA.r` modulates wheel radius and scene brightness. Mids modulate rotation frequency.
2. **Mouse Gravity Well + Click Shockwave**: Entire epicycle system is gravitationally warped toward the mouse cursor. Click emits a ripple that distorts rim distances.
3. **Video Chromatic Distortion**: `readTexture` luma shifts pixel coordinates, creating chromatic optical-flow aberration.
4. **Treble Sparkle**: Additive sparkle particles bloom across the canvas on treble peaks.
5. **Enhanced Temporal Feedback**: Trail persistence now reconstructs compressed color from `dataTextureC.g/b`, preserving motion blur.
6. **Semantic Alpha**: Alpha carries `presence * depth * (0.7 + bassEnv * 0.35 + treble * 0.2)` — interaction intensity scaled by depth.

## Issues / Notes
- None. All bindings verified against 13-binding contract. Line count ~185 (target ~180).
