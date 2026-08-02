# Batch 28: infinite-video-feedback

- Lines: 118 → 174 (+56).
- Implemented the advertised mouse-centered zoom/rotation: the formerly depth-weighted Rotation slider now drives aspect-correct recursive rotation while a fixed 0.5 depth weight preserves its old default.
- Added a sprung feedback center, alternating click portal kicks, sector FFT voices, safe alpha division, one depth sample, meaningful feedback retention, and a raw 2.0 state clamp.
- `dataTextureC` remains previous history and `dataTextureA` remains raw bounded feedback; no display tonemap was inserted into state.
- Focused Naga/bind-group/extraBuffer gate: pass.
