# Batch 60 — elastic-surface + electric-contours

Branch: `upgrade/batch-60-heat-echo-elastic`  
Date: 2026-08-23  
Tracker: #527–528

## Files changed

- `public/shaders/elastic-surface.wgsl`
- `shader_definitions/distortion/elastic-surface.json`
- `public/shaders/electric-contours.wgsl`
- `shader_definitions/visual-effects/electric-contours.json`
- `swarm-outputs/codex-2026-08-23-b60/notes-surface-electric.md`

## elastic-surface (#527) — critical C-load fix

**Confirmed:** every prior `textureSampleLevel(dataTextureC, …)` path is gone.
Self + N/S/E/W neighbors now use bounded `textureLoad(dataTextureC, clamp(pixel ± offset), 0)` with `maxCoord = res - 1`. Depth self and displaced depth use `textureLoad(readDepthTexture, …)` for state consistency.

### Packing
- **A:** `RG = displacement`, `BA = velocity` — raw sim state, **never tonemapped**
- **Display (`writeTexture`):** ACES on RGB only; semantic alpha from stretch/velocity
- **B:** unused
- **extraBuffer:** no writes

### Upgrade highlights
- Early `gid` bounds check; workgroup `16×16×1`; click loop `min(u32(u.config.y), 50u)`
- Audio: `plasmaBuffer[0].xyz` + bins 1/4/8 for ambient / ripple frequency / lateral drive
- Held punch stronger (`zoom_config.w > 0.5` → deeper inward impulse + radius bass swell)
- Thin-film iridescence from stretch + Laplacian energy; caustic runners along normals
- Source `params` ids/defaults/ranges preserved; `updatedParams` aligned

## electric-contours (#528)

### A packing choice (documented)
**Diagnostics in A, ACES on display only** (not display duplicate).

| Channel | Meaning |
|---------|---------|
| R | scaled potential |
| G | field magnitude |
| B | edge + spark + sparkle |
| A | dielectric / corona energy |

Display `writeTexture` receives ACES-tonemapped RGB + semantic alpha. A stores raw field diagnostics (un-tonemapped).

### Upgrade highlights
- Cap click spark charges from ripples (`min(…, 50u)`); each ripple is a decaying Coulomb charge
- Held boosts mouse charge (~1.15 + bass); hover keeps a weak probe charge
- Corona bloom packets along E-field direction; treble sparkle grain
- FFT band arcs from bins 2/5/7 angular modulation
- Depth via `textureLoad(readDepthTexture, coord, 0)`
- Source `params` exact; `updatedParams` aligned; B unused; no extraBuffer writes

## Validation notes

- Structural: local wgsl gate / naga on these two files
- Visual QA: requires a real GPU (Cloud VM has no adapter)
