# Interactivist Upgrade Notes: gen-coral-reef-colony

## Upgrades Applied
1. **Audio Envelope (`bass_env`)**: Smoothed bass pulse stored in `dataTextureA.r` drives nutrient availability and bloom intensity instead of raw bass.
2. **Mouse Gravity Well + Click Shockwave**: Mouse position exerts a gravity vector that warps the polyp grid. Mouse click spawns an expanding shockwave burst (`abs(sin(...))`) injected into coral density.
3. **Video Luma-Keyed Spawn**: Bright regions of `readTexture` (luma > 0.6) seed additional coral growth and distort caustic coordinates.
4. **Treble Sparkle**: Stochastic sparkle particles appear on polyp tips driven by treble amplitude.
5. **Temporal Accumulation**: Previous frame color mixed with current frame for organic growth trails; `mouseDown` increases blend rate.
6. **Depth Fog**: Scene depth from `readDepthTexture` drives exponential fog for slot-2/3 compositing.
7. **Semantic Alpha**: Alpha encodes `coralDensity * biolum * depthAtten * interaction`, where interaction sums mouse pull, click wave, sparkle, and video spawn.

## Issues / Notes
- None. All bindings verified against 13-binding contract. Line count ~185 (target ~180).
