# Batch notes — kaleidoscope / voronoi eight (2026-09-11)

IDs: `astral-kaleidoscope`, `astral-kaleidoscope-gemini`, `astral-kaleidoscope-grokcf1`,
`voronoi`, `voronoi-chaos`, `voronoi-dynamics`, `voronoi-glass`, `voronoi-shatter`.

Selection rule: none of these eight had ever received the ACES/bounds-guard
pass other batches carry (no `aces`/`toneMap` call in any of them before this
batch), and three shared a genuine binding-layout defect. Not a "smallest
remaining" pick — a "this whole family predates the current plumbing
convention" pick, same spirit as prior themed batches.

---

## astral-kaleidoscope

- **Kept verbatim:** segments/rotation_speed/spiral_strength/trail_persistence
  param roles and remap constants; polar mirror-fold math; HSL hue-drift
  grading; feedback trail buffer/blend; ripple-ring + spectral glow tail.
- **Defect fixed (floor, not the upgrade):** `struct Uniforms` declared
  `zoom_params` before `zoom_config` — backwards from the engine's canonical
  layout (`config, zoom_config, zoom_params, ripples`). The 4 real sliders
  were silently fed raw time/mouse bytes, and mouse_uv/mouse_down were fed
  into what the code called hueShift/aberration/centerOsc/pulsePower.
  Reordered the struct and rewired reads so the sliders are live again. Also:
  missing bounds guard (added), `__finalRGB` used a naga-reserved `__`
  prefix (renamed to `finalRGB` — this alone would have failed the gate),
  no ACES tonemap (added).
- **Ideas actually in the diff:** (1) pointer-anchored fold center — held
  pointer pulls the fold center via `mix(ambientCenter, pointerUV, pointerHeld)`;
  (2) mirror-seam glint — `seamGlint` lit at `a≈0`/`a≈segmentAngle*0.5`,
  scaled by treble/bass, added into `finalRGB`.
- **A packing:** unchanged — display RGBA light-trail history in dataTextureA.

## astral-kaleidoscope-gemini

- **Kept verbatim:** segments/rotation_speed/spiral_strength/trails param
  roles; noise-warp fold perturbation shape; per-channel chroma wobble;
  noise-shimmer feedback trail.
- **Defect fixed:** same struct-order bug (fixed the same way); missing
  bounds guard (added); no ACES (added); `plasmaBuffer` was bound and never
  read anywhere in the file — completely silent.
- **Ideas actually in the diff:** (1) audio-reactive warp swell — `warpPower`
  now `0.35 + bass*0.75`, and the ambient warp's noise-scroll speeds up with
  treble; (2) pointer warp epicenter — `pointerWarp` term (noise sampled
  around `toPointer`, gated by `pointerHeld`) added into the same `warp`
  variable that feeds `r`/`a`.
- **A packing:** unchanged — display RGBA feedback trail.

## astral-kaleidoscope-grokcf1

- **Kept verbatim:** same skeleton as gemini (segments/rotSpeed/spiralStr/
  trails roles; warp-noise fold perturbation left untouched — this file's
  ideas live in rotation/spiral, not the warp channel; chroma wobble;
  shimmer trail).
- **Defect fixed:** same struct-order bug, bounds guard, ACES, dead
  `plasmaBuffer` binding as gemini.
- **Ideas actually in the diff:** (1) audio-reactive spin — `rotSpeed`
  scaled by `(1+bass*0.8)`, `spiralStr` scaled by `(1+mids*0.5)`, so beats
  torque the mirror directly; (2) held-pointer spiral grab — `grabSpiral`
  (`sin(pointerAngle - a) * pointerHeld`) added into `a` alongside the
  existing `rotation`/`spiral` terms, deliberately a different mechanism
  from gemini's warp-epicenter pull so the two siblings read as distinct
  effects instead of clones.
- **A packing:** unchanged — display RGBA feedback trail.

## voronoi

- **Kept verbatim:** cell_density/jitter/ridge_strength/palette_shift param
  roles; Worley F1/F2 search; mouse-pull + ripple-swirl lattice
  perturbation; palette-from-plasmaBuffer lookup; ridge/cellMask/edgeAA
  compositing.
- **Floor:** no ACES tonemap before this pass — added.
- **Ideas actually in the diff:** (1) tectonic drift — a slow
  `sin/cos(time*...)` offset added to the lattice position `p` before the
  Worley search, independent of mouse/ripple; (2) treble ridge sparkle —
  `sparkleBurst` (per-cell hash gated by a time-stepped seed and the
  instantaneous treble band) adds a bright glint riding the ridge term.
- **A packing:** unchanged — display RGBA in dataTextureA.

## voronoi-chaos

- **Kept verbatim:** Cell Scale/Chaos Amount/Color Mix/Center Dot Size
  param roles; per-cell point sinusoidal animation; mouse repulsion of cell
  points; spectral ridge color; center-dot rendering; click-front glow.
- **Floor:** alpha was hardcoded to the source texture's near-1.0 alpha —
  replaced with semantic coverage from ridge/click/dot terms. `dataTextureA`
  and `dataTextureC` were bound but completely unused — now genuinely
  written/read for the trail idea below. ACES added. Replaced the generic
  "COPY PASTE THIS HEADER" template comment with a real identity header.
- **Ideas actually in the diff:** (1) bass-snap shard jitter — a per-cell
  hash gated by a bass-scaled threshold (`snapGate`) adds a discontinuous
  displacement to `point`, layered on top of the existing continuous mouse
  repulsion, scaled by `chaos`; (2) held-pointer trail smear — exact
  `textureLoad(dataTextureC, ...)` blended into the output while `held>0`.
- **A packing:** NEW — display RGBA history (previously unused); documented
  in the header.

## voronoi-dynamics

- **Kept verbatim:** centroidCount/repulsion/attraction/edgeWidth param
  roles (roles preserved — repulsion still means "push", attraction still
  means "pull", now actually wired); hashed-centroid generation + gentle
  animation; mouse/ripple-as-centroid search; iridescent edge hue; bubble
  highlight; depth-aware blend with source.
- **Floor:** `repulsion` and `attraction` were computed from their sliders
  and then never referenced again anywhere in the file — dead sliders on a
  file literally named "physics-based centroid movement." `plasmaBuffer`
  was bound and never read. Alpha was hardcoded to `1.0`. Hard `clamp`
  replaced with ACES tonemap.
- **Ideas actually in the diff:** (1) repulsion inflates the mouse-owned
  cell's bubble (`mouseCellBoost`, applied via `effDist`) and attraction
  pulls nearby non-mouse centroids' sample position toward the pointer
  (`mix(centroidPos, mouse, attraction*mouseInfluence*8.0)`) — this is the
  file's own promised "physics," finally reading its own sliders; (2)
  audio-reactive bubble pulse — bass scales `bubblePulse` (feeds
  `bubbleHighlight`/`gradient`), mids speed the iridescent edge-hue cycle.
- **A packing:** unchanged — raw (centroidPos, nearestDist, nearestIdx).

## voronoi-glass

- **Kept verbatim:** density/refract/border/attract param roles; grout/
  normal/facet math; glint/facet runner shimmer; click-shatter offset on
  refraction; existing semantic alpha (luma + grout term, kept and
  extended, not replaced).
- **Floor:** no ACES tonemap — added. `comparison_sampler` binding had been
  locally renamed `compSampler` (unused either way; renamed back to the
  canonical name). `dataTextureC` was bound and A was written every frame,
  but C was never read back — pure write, no feedback.
- **Ideas actually in the diff:** (1) bass facet-fracture pulse —
  `crackLine` (per-cell hash gated by a bass threshold, modulating a
  high-frequency sine along `m_dist`) layered on top of the continuous
  glint/facet runners; (2) exact-C breath-fog trail — `history` now read
  back and blended in proportionally to `refractionActivity`
  (bend magnitude + click shatter).
- **A packing:** unchanged — display RGBA (now also read back for the fog
  trail; documented in the header).

## voronoi-shatter

- **Kept verbatim:** Shard Density/Shatter Force/Rotation/Shard Gaps param
  roles; mouse-driven shard displacement + rotation; edge/seam shading; raw
  A packing (m_dist, influence, rotAngle/pi, alpha).
- **Floor:** `u.ripples[]` and `u.config.y` (click count) were bound and
  available but completely unused anywhere in the file — clicking did
  nothing on a "shatter" effect. No ACES — added. `time` was never declared
  in the file at all (added, needed for both ideas below).
- **Ideas actually in the diff:** (1) click-impact shockwave —
  `shockDisplace`/`shockRot`/`shockEnergy` computed from `u.ripples[]`
  (age-gated ring per ripple), folded into the existing displacement and
  rotation and into `finalColor`/`finalAlpha`; (2) bass shard chatter —
  `chatterAngle` (per-cell hash gated by a bass threshold) added into
  `rotAngle` independent of pointer proximity.
- **A packing:** unchanged — raw (m_dist, influence, rotAngle/pi, alpha).

---

## Gates

- Naga: 8/8 pass (`naga <file>` clean on every file; `astral-kaleidoscope`
  needed the `__finalRGB` → `finalRGB` rename first — a naga-reserved
  identifier prefix that predates this batch).
- `python3 scripts/wgsl_precommit_gate.py --files <8 files>`: 8/8 pass
  (naga OK, bindgroup compatible, 0 extraBuffer violations, 0 workgroup
  errors).
- `npm run audit:extrabuffer`: PASS, 0 new violations.
- `npm run audit:dead-sliders -- --files <8 ids>`: PASS, 0 new dead
  sliders (confirms voronoi-dynamics' repulsion/attraction fix actually
  reads live now).
- `node scripts/generate_shader_lists.js`: clean, no catalog/list diff for
  these 8 (no param/id changes).
- Jest (`npx react-scripts test --watchAll=false --ci`) and
  `SKIP_WASM_BUILD=1 npm run build`: run after a fresh
  `bash scripts/jules-setup.sh` install (this VM's `node_modules` was
  empty at batch start).

Real-GPU visual QA is external — this VM has no GPU adapter. Everything
above is structural (Naga, bindgroup, extraBuffer, dead sliders, catalog
lists, Jest, build), not a claim that the new ideas "look right."
