# Changelog — gen-bioluminescent-chrono-plasma-astro-owl (b31, interactivist)

**Lines:** 260 → 350 (+90, at the top of the +60..+90 mandate).

## Bug fixes
- **Uniforms struct:** already canonical in `public/shaders` (`config, zoom_config, zoom_params, ripples`) — verified field-by-field against §0 and kept byte-exact. No remap needed.
- **Non-canonical audio read:** `plasmaBuffer[1].x` ("mid_highs") replaced with the canonical `plasmaBuffer[0].z` (treble) for the eye glow.
- **Stale-read rotation bug** in the gravity warp (`q.x` updated then re-read to compute `q.z`) — fixed with temporaries.
- **Missing outputs:** shader previously wrote only `writeTexture`. Now writes `writeTexture`, `writeDepthTexture` (real raymarch depth, `1 - t/MAX_DIST`; miss → passthrough of `readDepthTexture`), and `dataTextureA` every frame. Hardcoded `alpha=1.0` replaced with luma-based semantic alpha.
- Removed the in-map mouse translation hack (scene no longer teleports with the cursor); replaced by a true orbit camera.

## Added (role mandate: reactive geometry)
- **Mouse-orbit camera** built from `u.zoom_config.yz` (used directly, no re-normalize/flip; y=0 top → negative pitch) plus a slow auto-orbit drift; `rotY*rotX` on both ray origin and direction.
- **Click ripples** (`u.ripples`, loop guarded with `min(u32(u.config.y), 50u)`) feed a `rippleField` that dents the plumage SDF and twists the gravity well and wing fold.
- **Real audio:** `plasmaBuffer[0].xyz` (bass/mids/treble) + engine FFT bins from `extraBuffer[5..132]` (read-only, `arrayLength`-guarded): bass breathes body scale + gravity pulse + flap amplitude; mids swirl the nebula and set tessellation fold count; treble facets the eyes.
- **3D geometry complexity:** FFT wing band (bins 12/20/28 avg) drives a helical symmetry-fold twist of the wing SDF (`rot2D(fold * x)`), turning flat wings into a feather helix.
- **2D geometry complexity:** kaleidoscopic hex-fold chrono-tessellation lattice layered into the nebula background, cell shimmer driven by the high FFT band (bins 80/96/112).

## Slider wiring (all 4 live)
- p0 Wing Plasma Distortion → feather fBm domain-warp amplitude (existing, kept).
- p1 Core Gravity Intensity → gravity-well space bend (existing, kept).
- p2 Nebula Particle Density → nebula accumulation + tessellation brightness.
- p3 Temporal Echo Fade → real temporal feedback mix from `dataTextureC` (previously only dimmed the nebula).

## Perf estimate
~100 raymarch steps/px worst case × map() (fbm 4 octaves in wing warp) + 6-tap normal + 5-step nebula loop + ≤50 guarded ripple iterations (typically 0). Roughly 30–40% heavier than the old build; comfortably 60 fps at 1080p on a mid GPU.

## Gate
`wgsl_precommit_gate.py` — **PASS** (naga OK, bindgroup compatible, 0 extraBuffer violations).

## Rating prediction
7.5–8.5 / 10 — the owl now feels alive: orbitable, clickable, and visibly dancing to the spectrum rather than just the bass scalar.
