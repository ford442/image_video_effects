# Split-Gen Eight II — Idea Cards (2026-09-28)

Written before any WGSL edit. Every idea was grepped against the 662 catalog `Ideas:` lines.


### Generative
**1. gen-cybernetic-plasma-orchid-nexus** (raymarched plasma sphere+torus core, glow halo, cosine palette)
- **HEAD fixes (floor):**
  - Swap the petal box axes so the polar-repeated petals actually protrude past the core. They are currently buried inside it.
  - Flip `uv.y`.
  - Aspect-correct the mouse mapping.
  - Add `plasmaBuffer[0]` audio in place of `extraBuffer[0]`.
  - Write A and depth; ACES; semantic alpha (glow coverage).
- **Ideas:**
  1. *Zygomorphic labellum:* the lowest petal breaks the polar repeat. It is widened and cupped into an orchid lip, with a plasma nectar-well glow at its throat.
  2. *Column with pollinia:* a short central column with two glowing pollinia beads at its tip that pulse with bass.
- **KEEP:** core SDF, torus spin, glow accumulation, palette, all 4 param roles. `bloom_spread` stays the CA gain, made visible.

**2. gen-hyperdimensional-plasma-loom** (twisted xy-repeated cells of counter-rotating helical tubes, Fresnel iridescence, plasma glow)
- **HEAD fixes:**
  - The "trail" blends 85% of `readTexture` (the source image), not history. Replace it with an exact `textureLoad(dataTextureC)` trail at a documented weight.
  - `mid` from `extraBuffer[133]` (always 0) → `plasmaBuffer[0].y`.
  - Guard against false hits at step exhaustion.
  - Push the camera out of the tubes.
  - Gate the always-on cursor pull on hold.
  - The dead strand-3 cross weave is either made reachable or removed. No over-under: that idea is taken.
- **Ideas:**
  1. *Moving hyperplane slice:* each strand's radius is its cross-section of a 4D hypertube cut by a w-plane (unused `hash41` gives a per-cell w offset). Strands swell, pinch and vanish in a diagonal wave across the lattice.
  2. *Counter-propagating current packets:* emissive packets run in opposite directions along the two helices and flash where they cross.
- **FORBID:** heddles, shuttle, over-under, thread-memory ghost (all taken).

**3. gen-cybernetic-aether-moth-chrysalis** (raymarched spindle chrysalis; Voronoi-perforated dark shell over a glowing fibrous core)
- **HEAD fixes:**
  - Flip y.
  - Scale the spindle so it isn't clipped (±5.9 vs a view of ±4).
  - Shade the m==3 fibre hits.
  - Give the fibre glow a non-zero silence floor.
- **Ideas:**
  1. *Eclosion seam:* a dorsal split line down the shell, blended with the unused `smin`. It gapes with bass and with a held mouse, spilling core light.
  2. *Cremaster and silk girdle:* a silk thread hanging the chrysalis from the frame top, plus a girdle loop around its waist. The whole body sways as a pendulum.
  3. *Defensive wriggle:* each click (age = `time - ripple.z`) kicks a decaying twist impulse through the body.
- **FORBID:** chamber ribs, armour segments, wing venation or sheen (all taken).

**4. gen-neon-plasma-chrono-bloom** (raymarch through warped simplex-noise sheets, neon cosine palette, threshold bloom)
- **HEAD fixes:**
  - Flip y.
  - Fix the mouse projection scale and sign.
  - Audio from `extraBuffer[133]` (dead) → `plasmaBuffer[0]`.
  - Write depth and A; ACES instead of Reinhard+gamma; semantic alpha.
- **Ideas:**
  1. *Radial time lag:* the field's time coordinate trails with radius (`t - r*k`), so structure is born at the centre and flows outward like an opening bloom.
  2. *Sheet-intersection filaments:* a second, phase-offset sheet field. Where both are near zero, hot filament lines ignite.
- **FORBID:**
  - Chrono echo shells, C afterimage, mouse time-dilation as a *new* idea (all taken; HEAD's existing dilation is kept).
  - Neon tube core with dark sheath (taken by neon-edge-glow).

### Non-generative
**5. crt-tv** (retro-glitch; Composer-batch overlay header = second pass)
- **HEAD fixes:**
  - Scanlines are a dead `fract(uv*res)` mask (constant 0.5). Rebuild them on integer source rows in curved space.
  - The pixel-locked grille causes black moiré under curvature.
  - Halation is double-inverse-warped.
  - Alpha 0.9 → semantic.
  - The early return skips the A write.
  - Leave the inert extraBuffer spring and add none.
- **Ideas:**
  1. *Brightness-dependent beam width:* bright rows fatten into the scanline gaps and dark rows stay thin. This lives inside the rebuilt scanline profile.
  2. *Rolling hum bar:* a soft ground-loop brightness band crawling vertically (59.94 vs 60 Hz beat). Mids deepen it.
  3. *Faceplate glass:* rounded-rect tube corners, plus a faint curved-glass glare highlight from the curvature normal.
- **FORBID:** convergence, shadow-mask moiré, degauss (crt-magnet); interlace, two-rate decay (crt-phosphor-decay).

**6. silk-flow-advection** (image; curl-noise warp of the photo; A = velocity packing)
- **HEAD fixes:**
  - C is read through the filtering `u_sampler` → exact `textureLoad`.
  - The dead `plasmaBuffer[band+1]` → `plasmaBuffer[0]` components.
  - Make the constant `-breath*0.011` y push zero-mean, so it stops edge-stretching.
- **A PACKING kept:** xy velocity, z flowEnergy, w alpha.
- **Ideas:**
  1. *Watered-silk moiré (moiré antique):* replace the isotropic noise weave with two slightly detuned thread gratings in the local velocity frame. Their beat forms the flowing watermark of real watered silk.
  2. *Held-pointer gathering:* holding the mouse bunches the fabric toward the pointer, with radial pleats (lit ridges and dark troughs).
  3. *(Optional)* A flow-aligned sheen, only if it stays distinct from gen-aurora-silk's fold-slope satin.

**7. anamorphic-caustic-flare** (visual-effects; synthetic horizontal flare band + sin-product caustic refraction, ACES)
- **HEAD fixes:**
  - Band FFT `plasmaBuffer[1..8]` (zero) → `plasmaBuffer[0]`.
  - Store pre-ACES HDR in A, or decode it, so feedback isn't tone-mapped twice.
  - Click bursts become local to the click x instead of full-width lines.
- **Ideas:**
  1. *Gradient-steered refraction:* implement the comment's promise. The offset follows the finite-difference gradient of `caustic()`, instead of the mask times a fixed direction.
  2. *Anamorphic caustic glints:* caustic peaks are smeared into short horizontal streaks, with length driven by `stretch`. This finally makes the slider "stretch" something, and fuses the two halves of the effect.
- **FORBID:** ghosts, iris, veiling glare, lens dirt, threshold highlight streak (all taken).

**8. gemstone-fractures** (distortion; Voronoi shards, each showing the image rotated, Fresnel edge, absorption alpha)
- **HEAD fixes:**
  - Rotate around the **cell centre**, not the screen centre. The current pivot sends shards off-image into repeat-sampler seams.
  - Bound the spin (oscillate instead of growing without limit).
  - Add A write, ACES, `plasmaBuffer[0]` audio.
- **Ideas:**
  1. *Rutile silk needles:* fine needle inclusions at three 60° orientations in cell-local coordinates, glinting.
  2. *Star asterism:* a six-rayed star glint per shard, from those needles. Its centre is offset by a pointer-as-light direction, so the stars glide with the mouse.
  3. *Pleochroism:* shard body tint shifts with its rotation angle. The same gem shows two hues by crystal orientation.
- **FORBID:** micro-cracks, Cauchy fire, TIR, facet Snell tilt, colour zoning (all taken).

