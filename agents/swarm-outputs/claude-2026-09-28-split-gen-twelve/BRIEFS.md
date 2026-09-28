# Split-Gen Twelve — Idea Cards (2026-09-28)

Written before any WGSL edit. Every idea was grepped against the 670 catalog `Ideas:` lines.
"HEAD fixes" are floor (make it work) and are not counted as ideas.

## Generative

### 1. kimi_flock_symphony (generative; 256 boids simulated in A row 0, HSL splats, Reinhard)
- IDENTITY: an audio-driven boid flock drawn as soft coloured glows.
- HEAD fixes: `noise()` returns 0..1 so `noise_force` is a constant +x/+y bias (flock drifts down-right) — centre it.
  Tighten `stateInvalid` so a previous shader's row 0 is not accepted as state if cheap. Reinhard → ACES on display.
- KEEP VERBATIM: row-0 state packing (pos, vel), boid rules, splat shape, 4 param roles (trail_length, glow_radius, color_shift, density).
- ADD:
  1. *Real trails:* A rows ≥1 hold the decaying display colour, read back through exact C, so `trail_length` becomes
     the trail decay (default must look close to HEAD brightness, then leave history).
  2. *Orchestra sections:* boid index quartiles are sections — bass section large/slow/warm, treble section small/darting/cool,
     mids in between; each section's glow size and speed follow its own `plasmaBuffer[0]` band.
  3. *Tutti swell:* bass widens the separation radius so the whole flock breathes outward on hits.
- FORBID: predator, leader, comet tails (taken: boids, murmuration-phantom, rainbow-firefly-dance).
- A PACKING: row 0 = boid state (unchanged); rows ≥1 = pre-tonemap trail RGB + coverage alpha.

### 2. gen-showcase-nebula-core (generative; domain-warped fBm nebula, radial Balmer palette, bass rings, treble sparkles, ACES)
- IDENTITY: a glowing warped-gas nebula around a bright core.
- HEAD fixes: mouse reads `zoom_config.xy` (time, mouseX) and `.z` as "held" — use `.yz` + `.w`. Audio straight from
  `plasmaBuffer[0]` (the extraBuffer spring-damper scales it to ~8%). JSON `workgroup_size` [8,8,1] → [16,16,1].
  Resolve `params` vs `updatedParams` default mismatch only in `updatedParams`.
- KEEP VERBATIM: warp/fBm structure, Balmer radial palette, rings + sparkles, feedback mix, time_speed + plasma_density roles.
- ADD:
  1. *Chaos filaments:* the dead `domain_chaos` slider twists each successive warp octave (rotation/shear per octave),
     shredding the gas into filaments.
  2. *Warp lens:* the dead `warp_amount` slider scales the domain-warp strength (default reproduces HEAD's fixed 2.0);
     a held pointer coils the warp into a swirling gravity well.
  3. *Photoevaporation pillars:* dense dark columns pointing at the core, eroded tips with bright ionised rims facing it.
- FORBID: Strömgren/ionization shells, dust-lane reddening, lensing rings (gen_kimi_nebula, astrolabe, wormhole).
- A PACKING: display RGBA (post-ACES) mixed with C history, as HEAD.

### 3. gen-worley-cellular-noise (generative; F1/F2 Worley tissue, pink/coral/ivory, SSS boundary glow, ACES)
- IDENTITY: a living cellular tissue of soft-walled cells.
- HEAD fixes: `hash22(neighbor + time*speed*10 ...)` re-randomises feature points every frame (strobe) — take time out of
  the hash, keep the sin/cos orbit. Audio from `plasmaBuffer[0]` directly. C via exact `textureLoad`. No extraBuffer writes.
- KEEP VERBATIM: F1/F2 structure, palette, SSS glow, A packing (f1, boundary, scatter, alpha), 4 slider roles.
- ADD:
  1. *Real membrane aberration:* R and B are resampled along the F2−F1 boundary gradient (± offset), so the
     "Chromatic Aberration" slider becomes a spatial split at the walls instead of a tint swap.
  2. *Turgor pulse:* bass inflates the cells — interiors swell and brighten, walls thin.
  3. *Triple-junction vertices:* bright nodes where three cells meet (F3 ≈ F2 ≈ F1).
- FORBID: mitosis, nucleus, cytoplasm streaming (taken).
- A PACKING: HEAD's (f1, boundary, scatter, alpha) field packing; C read as fields.

### 4. gen-sentient-holographic-neuro-lace-matrix (generative; fract-repeated gyroid lattice, rescue-light)
- IDENTITY: flying through an endless teal holographic lattice of gyroid lace.
- HEAD fixes: flip y (and mouse y). Gyroid period must match the repetition cell (or drop fract) so there are no seams.
  Camera must start outside the solid (numpy clearance check). Audio from `plasmaBuffer[0]` (extraBuffer[0] dead).
  Write depth + A; ACES; semantic alpha. Mouse pull must not recede as the camera flies.
- KEEP VERBATIM: gyroid lace motif, teal/indigo palette role, scanlines, diffuse/spec/AO shading, 4 param roles.
- ADD:
  1. *Breathing lace wave:* HEAD's dead pulse term (line ~63) becomes a bass-driven thickness swell travelling down
     the flight axis — the "breathing" the JSON promises.
  2. *Bioluminescent depth fog:* the fog the header promises, tinted and lit by the step-count glow so distant lace
     dissolves into luminous haze (also kills distance moiré).
  3. *Held-mouse neuron bloom:* holding the pointer pulls the lace toward a point that travels with the camera and lights a glow node there.
- FORBID: myelin, Ranvier nodes, saltation, synapse runners, nucleation fronts (all taken).
- A PACKING: display RGBA (A written for catalog consistency; C not read unless an idea needs it).

## Non-generative

### 5. sonar-reveal (interactive-mouse; desaturated tint, colour disc at pointer, ring field, click shocks, echo)
- IDENTITY: a sonar disc revealing colour around the pointer in a dimmed world.
- HEAD fixes: C via exact `textureLoad` (not filtering sampler). Cap ripple loop `min(...,50u)` + age cutoff; shock radius
  not multiplied by live bass. Remove dead vars. Param 4 JSON label is "Color Mode" but drives echo mix — fix `updatedParams` label only.
- KEEP VERBATIM: disc reveal, desat tint, ring sets, click shocks, 4 param roles.
- ADD:
  1. *PPI sweep arm:* a rotating radar sweep arm from the pointer with a phosphor afterglow wedge trailing it in the dimmed field (JSON promises "scanning radar ring").
  2. *Contact blips:* image edges flash briefly as a ring front passes over them.
  3. *Outward-drifting echo return:* the echo is resampled from C radially inward toward the pointer, so returns drift outward instead of sitting as a static veil.
- FORBID: generic spring cursor, CRT phosphor decay copy.
- A PACKING: tone-mapped display RGBA; C read as colour.

### 6. lighthouse-reveal (interactive-mouse; rotating beam from the pointer, fbm dust, blackbody lamp, halo, fog)
- IDENTITY: a lighthouse beam sweeping across a dark image from the pointer.
- HEAD fixes: output premultiplied with ~0.12 alpha floor outside the beam — make alpha semantic without dimming the
  frame twice. Wire the dead `revealPulse` (bass). Write A.
- KEEP VERBATIM: beam geometry, dust, lamp, halo, fog, vignette, 4 param roles.
- ADD:
  1. *Fresnel lens panel flashes:* the lamp is a rotating bull's-eye lens; the beam carries panel bands, and a bright
     flash fires each time a panel faces the viewer.
  2. *Depth-occluded shaft:* near depth along the beam casts shadow streaks down the shaft.
- FORBID: arch-gated crepuscular rays (vortex-cathedral).
- A PACKING: display RGBA.

### 7. fabric-zipper (interactive-mouse; noise fabric covering the image, zipper opening above the mouse slider)
- IDENTITY: unzipping a fabric cover to reveal the image.
- HEAD fixes: Weave Frequency is nearly dead (alpha ±5%) — must drive the visible weave. The jagged tooth strip below the
  slider leaks image while closed. Remove unused vars. Write A; ACES; audio optional (none at HEAD — don't force it).
- KEEP VERBATIM: opening geometry above the slider, teeth density/jaggedness roles, spread role.
- ADD:
  1. *Twill weave:* diagonal twill ribs whose frequency is `weave_freq`, lit so the ribs read as cloth.
  2. *Rolled tape lips:* the opening's edges curl back and cast a soft contact shadow onto the revealed image.
- FORBID: slider puller, staggered L/R teeth (zipper-reveal).
- A PACKING: display RGBA.

### 8. video-echo-chamber (image; rotate/zoom feedback around the pointer, chroma streaks, click echo rings)
- IDENTITY: a video feedback tunnel spinning around the pointer.
- HEAD fixes: `local = uv - center` not aspect-corrected. Alpha accumulates to saturation.
- KEEP VERBATIM: decay, radius, echoStr, colorShift roles; feedback mix cap; click rings.
- ADD:
  1. *Motion-keyed echo:* echo strength is keyed by |current − previous| so moving content leaves trails and static content stays clean.
  2. *Depth-weighted persistence:* near objects' echoes last longer than the background's.
- A PACKING: display RGBA 0..1 (C read as colour).

### 9. mercury-temporal-mirror (image; height + smoothed-gradient state reflects the image)
- IDENTITY: a liquid-mercury surface reflecting the image, disturbed by clicks and audio.
- HEAD fixes: `pow((fract(...)-0.5)/0.14, 2.0)` is NaN for half the pixels and spreads through the Laplacian — use x*x.
  The capillary packet gaussian peaks where sin≈0 and cancels.
- KEEP VERBATIM: offset reflection, specular, audio rain, mouse/click impacts, metallic mix, 4 param roles.
- ADD:
  1. *True capillary wave:* state becomes height + velocity (2-state wave equation) so click rings propagate outward
     on their own; A packing re-documented; confirm A.w is not read back as alpha. Must be stable (check CFL/damping).
  2. *Fresnel horizon reflection:* glancing slopes reflect toward a studio/sky gradient instead of the image.
- FORBID: beading (taken widely).
- A PACKING: raw wave state (not tone-mapped); display to writeTexture.

### 10. holographic-sticker (visual-effects; HSV rainbow foil disc at the pointer, grating ripple, rim highlight)
- IDENTITY: a holographic foil sticker you move over the image.
- HEAD fixes: `plasmaBuffer[(palIdx%8)+1]` is always 0 → use `plasmaBuffer[0]` treble. Radius 0 → smoothstep(0,0) guard.
- KEEP VERBATIM: foil disc, grating ripple, rim highlight, click rainbow rings, 4 param roles.
- ADD:
  1. *Edge peel:* a held pointer lifts a curl on the sticker rim, showing the white backing and a soft shadow beneath.
  2. *Embossed guilloche security pattern:* fine guilloche rosette lines embossed in the foil, hue shifting with view angle (pointer offset).
- FORBID: glitter / micro-facet glints (liquid-mirror, kamuro, underwater_caustics).
- A PACKING: display RGBA.

### 11. luma-glass (distortion; luminance-gradient normal refraction, 7 samples, spec, Fresnel)
- IDENTITY: the photo seen through glass embossed by its own luminance.
- HEAD fixes: refraction scales with depth → zero on flat/empty depth; give it a floor. Leave the dead spring (inert).
- KEEP VERBATIM: luma→normal, 7-sample refraction, specular from pointer light, Fresnel, SSS, 4 param roles.
- ADD:
  1. *Honest Sellmeier dispersion:* the 7 samples are weighted by wavelength→RGB, normalised per channel, with a
     visible dispersion delta, so bright edges show spectral fringes (the declared mechanism is currently achromatic).
  2. *Laplacian caustic network:* brightness where the luminance surface converges light (from its Laplacian), replacing the N·L "caustic".
- FORBID: frosted etch, bevel came lines.
- A PACKING: display RGBA.

### 12. audio-reactive-pyramid (post-processing; 3-level DoG detail pyramid boosted per FFT band)
- IDENTITY: a detail enhancer whose three detail bands pump with bass/mid/treble.
- HEAD fixes: at silence all gains are 0 → effect invisible; add a small base detail gain so the default is visible.
  Keep extraBuffer[5..132] FFT bins (valid host data).
- KEEP VERBATIM: 3-level DoG, per-band gains, blend.
- ADD (quiet):
  1. *Depth-routed bands:* near pixels take the fine-band boost; far pixels take a gentle coarse softening (aerial perspective).
  2. *Per-band chroma split:* coarse-band halos lean warm, fine-band edges lean cool.
- FORBID: mouse loupe, glow, anything non-photographic.
- A PACKING: display RGBA.
