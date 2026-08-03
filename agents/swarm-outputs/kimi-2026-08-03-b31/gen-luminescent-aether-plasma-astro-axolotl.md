# Changelog — gen-luminescent-aether-plasma-astro-axolotl (b31, interactivist)

**Lines:** 207 → 296 (+89, within the +60..+90 mandate).

## Bug fixes
- **Uniforms struct:** already canonical in `public/shaders` — verified byte-exact against §0 (`config, zoom_config, zoom_params, ripples`), no remap needed.
- **Mouse y-flip removed:** the old map() built `mouse_world` with `mouse.y * -4.0 + 2.0` (a flip the contract forbids) and teleported the scene toward the cursor. Deleted; replaced by a proper orbit camera that uses `u.zoom_config.yz` directly (y=0 top, no flip).
- **Illegal swizzle assignment:** the old gill loop wrote `p_f.xy = …` / `p_f.xz = …`, which naga rejects (WGSL has no swizzle assignment). Rewritten with explicit temporaries.
- **Missing outputs:** previously wrote only `writeTexture` with hardcoded `alpha=1.0` and no depth. Now writes `writeTexture`, `writeDepthTexture` (real raymarch depth `1 - d/MAX_DIST`; miss → `readDepthTexture` passthrough), and `dataTextureA` every frame, with luma-based semantic alpha. Added tonemap+gamma.

## Added (role mandate: reactive geometry)
- **Mouse-orbit camera** from `u.zoom_config.yz` (yaw/pitch + slow auto-drift), applied to ray origin and direction.
- **Click ripples** (`u.ripples`, guarded `min(u32(u.config.y), 50u)`) churn the current twist, dent the body, and ruffle the gill SDF.
- **Real audio:** `plasmaBuffer[0].xyz` + FFT bins from `extraBuffer[5..132]` (read-only, `arrayLength`-guarded): bass breathes body scale + gill expansion; mids drive swim wiggle + tessellation fold count; treble lifts gill emission; FFT gill band (bins 10/18/26) rotates each fractal gill generation; FFT air band (84/100/116) shimmers the caustics.
- **3D geometry complexity:** gill fractal extended 3 → 4 iterations with per-generation FFT fold; aether-current domain twist (Current Warp slider) corkscrews the whole SDF along the body axis.
- **2D geometry complexity:** kaleidoscopic ring-caustic tessellation layer in the background, folded by mids and shimmered by the air FFT band.

## Slider wiring (all 4 live)
- p0 Gill Expansion → gill scale/rotation (existing, bass-boosted).
- p1 Current Warp → aether-current domain twist strength of the SDF (was: flipped mouse gravity).
- p2 Nebula Density → noise background + caustic brightness (existing).
- p3 Bioluminescence → gill emission gain (existing, now driven by bass+FFT+treble).

## Perf estimate
80 raymarch steps/px × map() with a 4-iteration gill fractal + 6-tap normal + 4-octave background noise + ≤50 guarded ripple iterations (typically 0). Roughly 25% heavier than the old build; solid 60 fps at 1080p on a mid GPU.

## Gate
`wgsl_precommit_gate.py` — **PASS** (naga OK, bindgroup compatible, 0 extraBuffer violations).

## Rating prediction
7.5–8.5 / 10 — keeps the gentle abyssal soul while the gills now bloom with the spectrum and the whole creature can be orbited and poked.
