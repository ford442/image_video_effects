# Idea Cards — chrono pair (2026-09-13)

Claimed ids: `gen-luminescent-chrono-fluid-astrolabe`, `gen-luminescent-chrono-prism-astro-stag`.

```
SHADER: gen-luminescent-chrono-fluid-astrolabe
IDENTITY (one sentence): five nested gold liquid-metal tori spinning around a pulsing cyan holographic core, raymarched against a dark nebula.
KEEP VERBATIM: NUM_RINGS=5 torus SDF with noise3D chrono-fluid displacement and coarse/refined cull; bounding-sphere early out; slider roles Intensity (emission) / Speed (animTime) / Scale (ring radius + fluid LOD) / Mouse Influence (spring gravity well, extraBuffer[133..138]); core halo, fftPulse, click shockwaves; C display-history smoothing; ACES; near-is-one depth.
ADD (native ideas):
  1. Engraved limb graduations — each ring's local azimuth gets degree ticks (fine 10deg, major 30deg) cut into its gold as dark grooves with bright rims; treble glints the major marks. An astrolabe limb is a graduated scale.
  2. Geared outer mater — the outermost ring gets a band of rounded gear teeth in its SDF, and all rings rotate at ratios set by their radii (meshing gear train) instead of free phase offsets. Astrolabes/orreries are geared instruments.
  3. Rete star-chart plate — the background (miss pixels) becomes a stereographic plate: almucantar circles, azimuth spokes and a hashed star field rotating at sidereal rate around the core; mids twinkle stars. Nebula dust stays on top.
FORBID on this file: IQ cosine palette, oil-slick chroma, extra spring/ripple overlays (already has its own), replacing the torus rings with other geometry.
A PACKING: display RGBA (ACES tone + semantic alpha); C read back as colour history with exact textureLoad — unchanged.
```

```
SHADER: gen-luminescent-chrono-prism-astro-stag
IDENTITY (one sentence): a cyan prismatic capsule-bodied stag with mirrored antlers, fresnel-violet rim and mid-band sheen, floating in a blue volumetric void.
KEEP VERBATIM: body capsule + noise, abs-x mirrored antler capsule, smin blend, bass shockwave term scaled by Temporal Distortion; base colour / diffuse / fresnel*Fractal Intensity / mids sheen; exp(-t) haze scaled by Rift Density; far-is-one march depth (t/10).
ADD (native ideas):
  1. Recursive antler tines — three tines branch off each mirrored main beam, each forking once more (2 levels), tine length scaled by Fractal Intensity (params.z) and swaying with time. "Crystalline antlers carve fractals".
  2. Spectral prism dispersion — at the surface the view ray is refracted per channel with IOR spread driven by Prismatic Refraction (params.w, previously a DEAD slider) and treble; each channel samples the procedural aurora rift, giving rainbow fringes through the stag.
  3. Chrono-echo antler afterimage — exact textureLoad of dataTextureC a few pixels back along a slow drift, faded and hue-shifted, strength from Temporal Distortion (params.x): time-lagged ghosts of the prism silhouette.
FORBID on this file: spring cursors, click ripples, IQ palette overlay, turning the stag into a different creature/fractal.
A PACKING: display RGBA (post-ACES colour + coverage alpha); C read as colour for idea 3. (HEAD wrote display pre-tone RGBA and never read C; now consistent.)
Floor fixes: header claimed config.y "Audio" (code never used it — audio is plasmaBuffer[0].x); camera read zoom_config.yz / resolution (mouse is already 0..1, so orbit was dead) → fixed; stag offset now centred on mouse; ACES added; hit alpha no longer hardcoded 1.0; capsule dot(ba,ba) guarded.
```

---

## NOTES

### gen-luminescent-chrono-fluid-astrolabe
- Kept verbatim: 5-torus SDF + noise3D chrono-fluid + FLUID_CULL_DIST coarse/refined cull, bounding-sphere early out, spring mouse (extraBuffer[133..138]), slider roles, core halo + fftPulse, click shockwaves, C colour smoothing, ACES, near-is-one depth, alpha formula. Rotation code moved (not changed, except gear rate) into `ringFrame()`; mouse well moved into `mouseWarp()` so shading can recover ring-local coords.
- A packing: ACES display RGBA; C read as colour via exact textureLoad (unchanged).
- Idea 1 (graduations): `limbGraduation()`; applied in ring shading branch (`grad = limbGraduation(...)`). matId now 1.0+0.1*ringIndex (still < 1.5 = ring).
- Idea 2 (gear train + mater teeth): `ringFrame()` gearRatio/gearDir; `GEAR_TEETH`/`GEAR_TOOTH_H` teeth in `sceneDist()` (`isMater`).
- Idea 3 (rete plate): `retePlate()` (stereographic almucantars from PLATE_LAT, 15deg azimuth spokes, sidereal hashed stars with mids twinkle); added in the miss branch under nebula dust.
- Minor: getNormal normalize gets a 1e-6 bias (zero-length guard).
- JSON: features += mouse-driven, audio-reactive, upgraded-rgba. updatedParams untouched; original file had no trailing newline and still has none.
- Gates: naga OK; wgsl_precommit_gate PASS; audit:extrabuffer 0 new violations (reads of extraBuffer[6..9] FFT are pre-existing reads, no writes); audit_dead_sliders PASS but scanned 0 defs — both JSONs have only `updatedParams` (no `params`), so the audit skips them. Manual check: all four zoom_params read.

### gen-luminescent-chrono-prism-astro-stag
- Kept verbatim: body capsule + noise, abs-x antler main beam, smin(0.2), bass shockwave * params.x, base colour/diffuse/fresnel*params.z/mids sheen, exp(-t) haze * params.y, t/10 depth (far = 1).
- A packing: ACES display RGBA; C now read back as colour (exact textureLoad) by the chrono-echo.
- Idea 1 (tines): `sdAntlerTines()`, smin'd into `antler` in `map()`.
- Idea 2 (dispersion): `riftColor()` + per-channel `refract` loop in shading (`spread`, `disp`, `dispAmt`) — wires params.w (Prismatic Refraction), which was a dead slider at HEAD.
- Idea 3 (chrono-echo): `echoCoord`/`prev`/`ghost` block before writeTexture, screen-blended so it stays <= 1 and decays.
- Floor fixes: standard header; Uniforms comment corrected (config.y = rippleCount; code never used it as audio — audio was already plasmaBuffer[0].x); camera orbit bug fixed (HEAD did zoom_config.yz / resolution on a 0..1 uv → orbit was dead and the stag sat ~(1,1) world units off-centre, mostly off-screen); stag offset now centred on mouse; ray y flipped so antlers rise on screen; ACES added; hit alpha no longer hardcoded 1.0 (0.78..0.98 by fresnel transmission, void = haze+echo); sdCapsule division guarded; treble read.
- JSON: unchanged (features already true now; updatedParams untouched).
- Gates: naga OK; wgsl_precommit_gate PASS; dead-slider audit skips (no `params` key), manual: x/y/z/w all read.
- Concern: framing change (centering + y flip) is a deliberate bug fix but visibly differs from HEAD; needs real-GPU look.
