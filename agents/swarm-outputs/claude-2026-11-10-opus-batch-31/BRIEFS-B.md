# opus/batch-31 — fork B Idea Cards (written before any WGSL idea edit)

```
SHADER: directional-blur-wipe   (second pass; HEAD Ideas: wipe-front ramp; shutter-weighted comet kernel; long-exposure highlight streaks)
IDENTITY: a straight wipe line through the cursor splits a clean photo from a directional, chromatic motion-blurred copy
KEEP VERBATIM: split_pos/angle/strength/samples roles; pointer-anchored line + angle lean; ramp, comet shutter, highlight streak weights; treble chroma taps; click flashes; depth scatter
ADD:
  1. luma-keyed wipe front — the seam is displaced along its normal by local image brightness (a classic luma wipe), so the boundary bends around highlights instead of being a ruler line
  2. stroboscopic multi-exposure — the comet kernel gets periodic shutter pulses so smeared highlights show discrete ghost copies (strobe photography), mids pump the pulse depth
  3. exposure persistence — the blurred side blends with exact C history (display RGBA), so moving the pointer leaves a decaying long-exposure trail on the blur side only
FORBID: springs (HEAD's dead spring was removed on purpose), ripple shockwaves beyond HEAD's click flash, IQ palettes
A PACKING: ACES display RGBA (unchanged; C now read back as display history)
```

```
SHADER: kimi-ripple-touch   (first pass)
IDENTITY: touch/click-driven dispersive water ripples refracting the photo with per-channel group-velocity chroma
KEEP VERBATIM: packet_source gravity-capillary packets, kLocal/vg/vp dispersion, RGB group-velocity offsets, phase colour ramp, all 4 param roles (x→kLocal, y→k0, z→sigma, w→amp)
ADD:
  1. caustic focusing — the surface Laplacian focuses light: convex crests brighten, troughs darken the refracted photo like sunlit pool caustics
  2. sun glint — specular highlight from the surface normal (grad of h) against a fixed low sun; treble sharpens the glint lobe
  3. crest foam memory — A.b (written but never read at HEAD) becomes a foam field: steep crests deposit white foam that decays over ~1 s and is advected nowhere (stays where the wave broke)
FORBID: replacing the solver, springs, IQ palettes, generic neon rings
A PACKING: raw sim state — r = h*0.5+0.5, g = v*0.5+0.5, b = crest foam (was vg/2.5, never read), a = phase (unchanged)
RESCUES planned: sim never propagated (lap and sources scaled by 1/3600 → h≈0.004, picture ≈ passthrough); bassWave age = time*0.15 dies after ~60 s; loop ignores config.y ripple count (empty slots at (0,0) emit during the first seconds)
```

```
SHADER: vaporwave-horizon   (first pass)
IDENTITY: the photo squashed into a sunset sky above a mouse-set horizon, over a scrolling perspective neon grid floor with purple fog
KEEP VERBATIM: horizon = mouse y, curve = mouse x * warp; perspective z = 1/dy grid mapping; Beer-Lambert sky haze + floor fog; all 4 param roles
ADD:
  1. striped retro sun — a glowing yellow→pink disc sitting on the horizon with horizontal cut bands that thicken toward its base and scroll down with grid speed
  2. two-tone neon line bloom — grid lines get a distance-filtered core plus soft glow halo (cyan longitudes, magenta latitudes) instead of a hard step() mask
  3. mirror floor reflects the *displayed* sky (incl. sun) — the reflection uses the same sky function, so the sun drops a glitter column onto the floor
FORBID: raymarched mountains/SDF scenes, springs, ripples, glitch overlays
A PACKING: ACES display RGBA (HEAD wrote no A at all)
RESCUES planned: no dataTextureA write; no ACES despite upgraded-rgba tag; hardcoded alpha 0.95/0.8; bass multiplied grid speed inside time*speed (phase jumps at large t); reflection sampled raw image rows, not the squashed sky shown above
```
