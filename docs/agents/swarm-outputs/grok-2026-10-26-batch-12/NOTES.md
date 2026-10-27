# Upgrade Notes — Grok (`cursor/batch-12`, 2026-10-26)

Twelve ripple, ink, gravity, and particle shaders. Idea cards are in `BRIEFS.md` (written first). Each file keeps its previous mechanism and gains two ideas. Saved `params` are byte-exact.

Eleven pasted headers were migrated with `migrate_to_prelude.py` (`mouse-ink-bleed`, `cyber-ripples`, `velocity-field-paint`, `echo-ripple`, `sim-decay-system`, `liquid-touch`, `gravity-well`, `interactive-pixel-wind`, `sim-heat-haze-field`, `black-hole`, `mouse-paint-splatter`). `pixel-explode` already included the prelude. That swap is not the upgrade.

`gravity-well` display is now ACES. Stored lensing fields are not. The header already claimed `upgraded-rgba`. `black-hole` had the same tag without a tone map; the display write is ACES and the horizon stays black because ACES of zero is zero.

`cyber-ripples` no longer reads `plasmaBuffer[band+1]`. `echo-ripple` no longer reads `plasmaBuffer[1..4]`. Both shimmers are a phase of `plasmaBuffer[0].z`. Those are dead-bin fixes, not ideas.

Real-GPU visual QA was not run. This VM has no hardware GPU.

Gates: Naga 12/12, extraBuffer clean, dead sliders clean (full scan, 0 new), `generate_shader_lists.js`. Vitest 169 files: 1431 passed on the full run, 4 `RendererManager` failures that passed on an immediate re-run of that file (44/44). `SKIP_WASM_BUILD=1 npm run build` succeeded.

## Per shader

### mouse-ink-bleed
- Kept: domain warp, cursor well, click shock, fibre wick, tide line. A stays `(trail rgb, wetness)`.
- Added: paper tooth punches the wet deposit, scaled by Turbulence; a held pointer fills wetness inside the spread radius.
- Formula: paper granulation (§12.2C); dwell pressure (§12.2C).

### cyber-ripples
- Kept: quantized radius, FBM warp, SDF rings, audio palette, click shocks, bass envelope in A.a.
- Added: the sine is floored into six brightness steps; chromatic offset snaps to the block cell when Block Size is on.
- Formula: none.

### velocity-field-paint
- Kept: semi-Lagrangian self-advection, stored-curl confinement, LIC streaks. A stays raw `(vel, omega, speed)`.
- Added: one MacCormack correction clamped to the 4-neighbour range; confinement drops and chromatic shear widens where strain beats `|curl|`.
- Formula: MacCormack advection (§12.2D).

### echo-ripple
- Kept: `echoWave`, held bowl, thin-film and bioluminescent harmonics, exact C advection. A stays `[mixed RGB, bass envelope]`.
- Added: echo `i` travels at `speed / (1 + 0.28 i)`; opposing echoes desaturate, a single echo does not.
- Formula: none.

### pixel-explode
- Kept: neighbour search, wobble, tumble, drop shadow, bevel, click detonations. A stays ACES display RGBA.
- Added: airborne tiles lengthen along the throw; the corner facing the throw is missing once the blast is strong.
- Formula: none.

### sim-decay-system
- Kept: neighbour decay count, five-stage mix, filiform veins, oxide bloom, mouse protection. A stays `(decay, material, corrosion, protection)`.
- Added: on an edge, tangent neighbours count more than cross-edge neighbours; rare mid-material cells nucleate pits off the edge.
- Formula: none.

### liquid-touch
- Kept: 13-point stencil, curvature pressure, biharmonic, Marangoni, coalescence, microfoam. A stays `(phi, velocity, temperature, merge)`. B stays the diagnostic write.
- Added: temperature adds to vertical velocity; a steep, slow contact line damps velocity.
- Formula: Boussinesq buoyancy (§12.2D), vertical only.

### gravity-well
- Kept: deflection, redshift, tilted disk, Doppler, Kepler streaks, far-side halo. A stays lensing fields.
- Added: disk dims inside `3 rs` with a bright lip on that orbit; red and blue sample a larger and smaller deflection, scaled by Lensing Order.
- Formula: none. ACES on the display write only.

### interactive-pixel-wind
- Kept: wind from the cursor, luma weight, upwind shadow, trails, chromatic split. A stays premultiplied ACES display RGBA.
- Added: the existing gust field gates the mean wind; a ridge perpendicular to the wind offsets and tints the picture.
- Formula: none.

### sim-heat-haze-field
- Kept: 3×3 diffuse, upward plume, schlieren along `∇T`. A stays `(temp, grad, displacement mag)`.
- Added: hot ground folds the sample across the hot layer, scaled by Distortion; a signed knife-edge brightens one side of `∇T` and darkens the other.
- Formula: none.

### black-hole
- Kept: chromatic pinch, frame drag, photon-ring mirror, accretion turbulence and infall. A stays `(dist, radius, horizonMask, alpha)`.
- Added: a thin bright ring at `1.5 ×` the horizon; the old mild redshift mix is a real loss of green and blue plus a dimming, scaled by Intensity.
- Formula: none. ACES on the display write only.

### mouse-paint-splatter
- Kept: speed-grown radius, cast-off satellites, click splashes, craquelure, `(0,0)` mouse stash. A stays `paint.rgb + wetness`.
- Added: the flick is an ellipse (long axis keeps the speed growth, short axis stays near the size slider); pigment darkens where neighbours are wetter.
- Formula: wet-edge accumulation (§12.2C), boundary form. Only this file.
