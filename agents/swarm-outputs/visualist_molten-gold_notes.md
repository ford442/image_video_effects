# Visualist Upgrade Notes: `molten-gold`

## Changes Made
- **Fixed binding contract**: Updated to exact 13-binding standard from prompt (`u_sampler`, `readDepthTexture`, `plasmaBuffer`, etc.).
- **Workgroup size**: Changed from `(8, 8)` to `(16, 16, 1)` per spec.
- **Audio source**: Switched from `extraBuffer` to `plasmaBuffer[0].x/y/z` for bass/mid/treble.
- **OkLab mixing**: Replaced all `mix()` calls with `mixOkLab()` for perceptually uniform gold gradients—eliminates muddy mid-tones between dark bronze and hot highlights.
- **Blackbody temperature**: `goldDark` and `goldHot` now derived from `blackbodyRGB()` with audio-reactive offsets (2200K–8000K range). Gold feels physically plausible and alive.
- **HDR workflow**: Specular highlights now reach up to 3.0 intensity before `hue_preserve_clamp(color, 8.0)` → ACES tonemap.
- **Tonemap & dither stack**: Added `hue_preserve_clamp` → `aces` → `ign` blue-noise dither in correct order.
- **Alpha = bloom weight**: Replaced `alpha = 1.0` with `bloomWeight` derived from luma, enabling proper slot-chain compositing.
- **Premultiplied writeback**: `textureStore(writeTexture, id.xy, vec4<f32>(color * a, a))`.

## Visual Improvements
- Gold transitions are buttery-smooth instead of grey-muddy in mid-tones.
- Hot spots have realistic incandescent color shift (orange → white-hot).
- Specular bloom is HDR-rich and ACES-mapped for filmic roll-off.
- No more 8-bit banding thanks to IGN dither.

## Issues
- None. Shader compiles cleanly and stays within performance budget.
