# Batch: kaleidoscope / voronoi eight — Idea Cards

Written before any WGSL edit, per `docs/SHADER_UPGRADE_BATCH.md` §2.

All eight files predate the ACES/bounds-guard/audio-wiring conventions used
elsewhere in the catalog. Each card lists a **defect fix** (plumbing floor,
not an upgrade) separately from the **native ideas** (the actual upgrade).

---

```
SHADER: astral-kaleidoscope
IDENTITY: mirrored polar kaleidoscope — chroma-split fold, HSL rainbow drift, light-trail feedback echo
KEEP VERBATIM: segments/rotation_speed/spiral_strength/trail_persistence param roles and their existing remap constants; polar mirror-fold math; HSL hue-drift grading; feedback trail buffer/blend; existing ripple-ring + spectral glow tail
DEFECT FIX (floor, not an idea): struct declares `zoom_params` before `zoom_config` — the OPPOSITE of the engine's canonical layout (config, zoom_config, zoom_params, ripples). This silently fed the 4 real sliders raw time/mouse data and fed mouse_uv/mouse_down into what the code called hueShift/aberration/centerOsc/pulsePower. Reordered the struct fields to canonical order and rewired reads so segments/rotSpeed/spiralStr/trails once again read the real UI sliders. Added the missing bounds guard (`gid.x/y >= dims` return) — absent entirely. Added ACES tonemap on final output (unclamped chroma-split + spectral glow could exceed 1.0).
ADD (2 native ideas):
  1. Pointer-anchored fold center — now that mouse_uv/mouse_down are correctly wired, a held pointer pulls the kaleidoscope center toward the cursor (blending out of the ambient time-orbit); release lets the orbit resume. Native because the fold center is the one coordinate this effect already animates.
  2. Mirror-seam glint — a treble/bass specular streak lights exactly at the fold seams (a≈0, a≈segmentAngle·0.5) so audio reacts to the kaleidoscope's own symmetry lines, not just the outer glow ring it already had.
FORBID on this file: extraBuffer springs, IQ palette replacing the existing HSL grading, liquid solver motifs
A PACKING: display RGBA light-trail history in dataTextureA (unchanged — dataTextureC is already read as color)
```

```
SHADER: astral-kaleidoscope-gemini
IDENTITY: astral-kaleidoscope skeleton + organic noise-warped fold and noise-shimmer trails
KEEP VERBATIM: segments/rotation_speed/spiral_strength/trails param roles; noise-warp fold perturbation; independent per-channel chroma wobble; shimmer-noise feedback trail
DEFECT FIX: same struct field-order bug as the base file (fixed the same way); added the missing bounds guard; added ACES tonemap; `plasmaBuffer` was bound but never read anywhere — genuinely silent despite the binding.
ADD (2 native ideas):
  1. Audio-reactive warp swell — bass widens `warpPower`, treble speeds the warp's noise-scroll, so the file's own "organic" field breathes with the track instead of sitting inert.
  2. Pointer warp epicenter — a held pointer becomes a second, stronger warp origin (using the now-correct mouse_uv/mouse_down) that pulls the noise field toward the cursor. Distinct mechanism from grokcf1's rotation-based tie-in below — this one lives in the warp field, not the spin.
FORBID: springs, generic IQ overlay, replacing the HSL grading, copying grokcf1's rotation idea verbatim
A PACKING: unchanged (display RGBA feedback)
```

```
SHADER: astral-kaleidoscope-grokcf1
IDENTITY: same warp-kaleidoscope skeleton as gemini, given its own voice via rotation/spiral instead of the warp channel
KEEP VERBATIM: segments/rotation_speed/spiral_strength/trails param roles; noise-warp fold perturbation; chroma wobble; shimmer trail
DEFECT FIX: same struct field-order bug, bounds guard, ACES tonemap, dead plasmaBuffer binding as gemini.
ADD (2 native ideas):
  1. Audio-reactive spin — bass/mids modulate `rotSpeed` and `spiralStr` directly (the rotation/spiral engine, not the warp channel gemini used), so beats visibly torque the mirror rather than just rippling the noise field.
  2. Held-pointer spiral grab — holding the pointer smoothly biases spiral direction/rate toward the cursor's angle from center, a "grab and twist" native mouse interaction distinct from gemini's warp-epicenter pull.
FORBID: springs, generic IQ overlay, reusing gemini's warp-epicenter idea
A PACKING: unchanged (display RGBA feedback)
```

```
SHADER: voronoi
IDENTITY: canonical Worley-cell tessellation — mouse/ripple-perturbed lattice, audio-scaled ridge glow, plasmaBuffer palette lookup
KEEP VERBATIM: cell_density/jitter/ridge_strength/palette_shift param roles; Worley F1/F2 search; mouse-pull + ripple-swirl lattice perturbation; palette-from-plasmaBuffer lookup; ridge/cellMask/edgeAA compositing
DEFECT FIX (floor): no ACES tonemap on final color (ridge glow + palette additions can exceed 1.0) — added.
ADD (2 native ideas):
  1. Tectonic drift — a slow, low-frequency time-based warp added to the sampling lattice position before the Worley search, so cells continuously migrate rather than sitting on a static grid. Independent of mouse/ripple input, always present.
  2. Treble ridge sparkle — a bursty specular glint riding the cell ridges, gated by the treble band's instantaneous value (not just the existing static `ridgeStrength * treble` scale), giving boundary lines an audio-reactive sparkle rather than flat brightening.
FORBID: extraBuffer springs, liquid solver, replacing the plasmaBuffer palette with an IQ cosine palette
A PACKING: unchanged — display RGBA in dataTextureA (matches existing C read as color)
```

```
SHADER: voronoi-chaos
IDENTITY: agitated Voronoi mosaic — mouse-repelled cell points, spectral ridge color, click-front glow
KEEP VERBATIM: cellsScale/chaos/colorMix/dotSize (Cell Scale/Chaos Amount/Color Mix/Center Dot Size) param roles; per-cell point sinusoidal animation; mouse repulsion of cell points; spectral ridge color; center-dot rendering; click-front glow term
DEFECT FIX (floor): alpha was hardcoded to the source texture's alpha (effectively always ~1.0, no semantic coverage/edge signal) — replaced with alpha built from ridge/shatter/dot coverage. dataTextureA/C were bound but completely unused (no history at all) — now genuinely used for the idea below, documented as display RGBA history matching a new exact C read.
ADD (2 native ideas):
  1. Bass-snap shard jitter — on a bass transient, cell points get a brief discontinuous snap displacement on top of the existing continuous mouse-repulsion, proportional to `chaos`, giving a percussive "shatter beat" native to the file's own repulsion mechanism.
  2. Held-pointer trail smear — exact `dataTextureC` load blended into the mosaic while the pointer is held, giving the chaos field a short trailing ghost (a "shatter smear") rather than the previously-unused history buffer sitting dark.
FORBID: liquid solver, IQ palette replacing the existing spectral ridge color, extraBuffer springs (mouse already drives repulsion directly)
A PACKING: NEW — display RGBA history in dataTextureA/C (previously unused); documented in header
```

```
SHADER: voronoi-dynamics
IDENTITY: "bubble physics" Voronoi — centroids from hashed seeds plus mouse/ripples as extra centroids, iridescent edges, bubble highlight, depth-aware sharpness
KEEP VERBATIM: centroidCount/repulsion/attraction/edgeWidth param roles; hashed-centroid generation + gentle animation; mouse/ripple-as-centroid search; iridescent edge hue; bubble highlight; depth-aware blend with source
DEFECT FIX (floor): `repulsion` and `attraction` were computed from their sliders and then never referenced again — dead sliders on a file literally named "physics-based centroid movement." `plasmaBuffer` was bound but never read (silent despite the binding). Alpha was hardcoded to 1.0. ACES tonemap added.
ADD (2 native ideas):
  1. Repulsion/attraction now drive real behavior — repulsion pushes the mouse-centroid's local cell boundary outward (bigger "bubble" near the cursor), attraction pulls the nearest few centroids' effective sample position toward the mouse for a gooey merge look near the pointer. This is the file's own promised "physics," finally wired to its own sliders.
  2. Audio-reactive bubble pulse — bass swells `bubbleHighlight`/gradient size, mids speeds the iridescent edge-hue cycle, using the plasmaBuffer binding that was previously dead.
FORBID: full multi-pass centroid physics rewrite, liquid solver, extraBuffer persistent springs
A PACKING: unchanged — dataTextureA keeps (centroidPos, nearestDist, nearestIdx) as already documented
```

```
SHADER: voronoi-glass
IDENTITY: refractive Voronoi glass — grout borders, facet glint/runner shimmer, held-attraction, click-shatter offset
KEEP VERBATIM: density/refract/border/attract param roles; grout/normal/facet math; glint/facet runner shimmer; click-shatter offset on refraction; existing semantic alpha (luma + grout term)
DEFECT FIX (floor): no ACES tonemap (additive glint/facet terms can exceed 1.0) — added. `comparison_sampler` binding was locally renamed `compSampler` (unused either way, renamed back to the canonical name for contract consistency). `dataTextureC` was bound and written to A every frame but never read back — pure write, no feedback.
ADD (2 native ideas):
  1. Bass facet-fracture pulse — a periodic bass-triggered "cracking" pulse across the lattice, layered on top of the continuous glintRunner/facetRunner shimmer, giving the glass a percussive fracture beat instead of only continuous glint.
  2. Exact-C breath-fog trail — the now-read-back `dataTextureC` blends a short condensation-like haze onto the glass when refraction is changing quickly (fast pointer motion), using the history buffer that was previously write-only.
FORBID: liquid solver, extraBuffer springs (mouse already drives attraction directly), generic IQ palette
A PACKING: display RGBA in dataTextureA (unchanged, now also read back for the fog-trail idea — documented)
```

```
SHADER: voronoi-shatter
IDENTITY: crystalline shards flying away from the mouse — per-shard rotation/displacement, edge shading, seam glow
KEEP VERBATIM: density/force/rotation/gaps param roles; mouse-driven shard displacement + rotation; edge/seam shading; raw A packing (m_dist, influence, rotAngle/pi, alpha)
DEFECT FIX (floor): `u.ripples[]` and `u.config.y` (click count) were bound and available but completely unused — clicking did nothing on a "shatter" effect. No ACES tonemap (added).
ADD (2 native ideas):
  1. Click-impact shockwave — wires the previously-unused `u.ripples[]` into a radial impulse: shards inside an expanding, age-decaying ring get an outward displacement kick and a brief rotation snap. A click now visibly breaks more glass, which is the one interaction this effect was missing.
  2. Bass shard chatter — a subtle bass-gated micro-jitter/rotation-chatter on shard edges, independent of and additive to the continuous mouse-driven rotation, giving a percussive rattle on beat.
FORBID: liquid solver, extraBuffer springs (ripples already give free per-click timestamped decay), replacing the raw A packing with display color
A PACKING: unchanged — raw (m_dist, influence, rotAngle/pi, alpha)
```
