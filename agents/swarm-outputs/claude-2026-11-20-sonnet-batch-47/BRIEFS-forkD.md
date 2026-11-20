# BRIEFS — fork D (sonnet/batch-47): chronos-brush, voronoi-zoom-turbulence

Both second pass. Existing `Ideas:` are KEEP VERBATIM. HEAD = `git show origin/main:public/shaders/<id>.wgsl`
(the worktree copies already differ from origin/main only by the coordinator's header-only prelude migration of chronos-brush).

HEAD run (SwiftShader, 256², SRC=img, drag path / audio 0.3,0.2,0.1): both compile, 0 NaN, picture not blank.
- chronos-brush: tinted live paint on black (output = history only since 2026-05-30; this is the file's identity — see "open call" in NOTES), 4 sliders all live.
- voronoi-zoom-turbulence: faceted cells with neon F2−F1 rim; 4 sliders live; spring in extraBuffer[133..138] is inert in the app (zeroed per frame ⇒ `spring == mouse`), harmless — cleanup candidate, NOT touched.
HEAD defects found: none that block (see NOTES for the two flags). No rescues planned.

---------------------------------------------------------------------------------------------------

```
SHADER: chronos-brush
IDENTITY (one sentence): a pointer brush that freezes the live frame into a decaying, hue-cycling tinted paint history; old paint thaws and drips; the pointer lays down 8 Hz shutter stamps.
KEEP VERBATIM: 4 params + roles (x brush radius [audio-boosted via bass_env], y freeze decay -> history persistence, z time-edge distort = history-UV wobble, w paint/erase); hue cycle + HSV tint; depthOpacity; click-stamp blooms from ripples; Idea 1 (chronophotograph shutter: 8 Hz, bass holds it open, erase bypasses it); Idea 2 (thaw drip from `above` pixel / .a freshness / column jitter); exact textureLoad on dataTextureC; decay = 1-(1-freezeDecay)*0.25*(1-bass*0.03); alpha accumulation; A = raw feedback RGBA (never tonemapped), .a = paint freshness; no springs/extraBuffer.
ADD (2):
  1. Wet-edge pooling (§12.2C "Wet-edge accumulation"): `edge = max(-∇²a, 0)` where a = the paint-freshness field already stored in C.a. Pigment pools at the inner rim of every fresh stroke — the rim darkens and saturates (display-side only, so it never accumulates in history). Strength rides `a` itself, so as a stroke dries/decays the rim disappears on its own.
  2. Dwell pressure (§12.2C "Dwell pressure"): while the pointer is held (zoom_config.w, "available, not needed" at HEAD), the brush presses harder where it rests: pressure = held * smoothstep(C.a at the cursor). Resting on a spot blooms the radius (≤ 1.6x) and deposits a deeper freshness; sweeping fast over fresh canvas stays thin — real brush kinematics (speed-thinning falls out for free) with no new state, no spring.
FORBID on this file: new spring / extraBuffer state, IQ palette, click shockwave rings (blooms already exist), a second conveyor, tonemapping the history, replacing the black-canvas look with a live-feed composite, any param re-role.
A PACKING: dataTextureA = raw feedback RGBA (UNCHANGED: rgb = history paint, a = freshness). writeTexture = same RGB + the wet-edge rim (display only, non-accumulating). HEAD packing is consistent, so it is kept.
```

Mechanism interrogation
- Tactic 1 (kernel): the kernel is "mix history toward live under a smoothstep disc". Next-better approximation of a pigment stroke: pigment is a *thickness* field, thickness has an edge profile (pooling) — the 5-point stencil of a.
- Tactic 2 (physics one step further): wet paint pools at its boundary (coffee-ring / watercolour edge darkening); a brush pressed harder lays a wider, wetter mark.
- Tactic 3 (promote intermediate): `above` (a 1-px tap of C) and `heldColor.a` are already loaded; the Laplacian needs 4 more taps at the same texture, and the cursor texel's `a` is the pressure signal.
- Tactic 6 (history the shader owns): C is read as colour + freshness. The one extra continuity: the freshness field's *shape* (Laplacian) and *level at the cursor* (dwell) — both read exact `textureLoad`, no packing change.

Formula admission: both rows are in the §12.2C table (family: interactive/brush; file already owns the pointer). Both consume C.a (field it already stores/reads) and `zoom_config.w` (already declared). Deletion test: remove either and it is still exactly chronos-brush; keep only either and it is not (no shutter, no thaw ⇒ still a brush with a rim / still a brush that blooms, but no time-freeze behaviour). Not usable verbatim on a sharpen/VHS/liquid.

---------------------------------------------------------------------------------------------------

```
SHADER: voronoi-zoom-turbulence
IDENTITY (one sentence): a Voronoi tiling whose every cell is an independently pulsing zoom lens on the source image, with sheared cell walls, a neon F2−F1 rim, a sprung pointer that agitates/calms cells, and bass-inflated centroids.
KEEP VERBATIM: 4 params + roles (x density, y turbulence speed, z zoom intensity, w mouse influence [±]); 3x3 F1/F2 search with animated sites `0.5+0.5*sin(time*(0.45+speed*0.35)+TAU*h)`; closed-form per-cell zoom about the site; zoomFactor clamp; shear conveyor along (1-edge); neon rim `smoothstep(0.09,0,F2−F1)`; bass centroid inflation; ripple zoom fronts (pixel-space); IQ palette hue mix (it is HEAD's look); exact-C hist mix; ACES; agitation alpha; the (inert-in-app) spring block untouched.
ADD (2):
  1. Exact bisector border distance + chamfer bevel (tactic 1 "deepen the kernel": IQ's second-pass Voronoi border distance replaces nothing — F1/F2 stay for the rim — it gives a *constant-width* distance and the wall normal): near each wall the sample UV bends outward along the wall normal (convex glass-tile bevel: content compresses at the chamfer) and the facet takes a fixed key-light term (`dot(nWall, L)`), so cells read as faceted lenslets instead of flat cut-outs. No second neon line.
  2. Turbulent lattice warp (cf. §12.2E "Additive domain twist": motion through geometry, no new primitive): the lattice coordinate is bent by a slow two-octave analytic swirl-warp before the cell lookup, so the walls curve and breathe; the image is *not* warped (sample UV is built from the un-warped position + zoom shift), only the cell geometry. Evolves with the existing Turbulence-Speed role; amplitude ≤ 0.2 cell.
FORBID on this file: another rim/neon line, thin-film or hologram costume, a second conveyor, Cauchy dispersion / Airy (claimed by other forks), a new spring, a different palette, new params.
A PACKING: ACES display RGBA, agitation in alpha (UNCHANGED; hist read as colour in C).
```

Mechanism interrogation
- Tactic 1: F2−F1 approximates "distance to the wall" but its width varies with wall angle and balloons at vertices; the exact bisector distance is the next-better approximation of the same operator.
- Tactic 2: each cell is a zoom lens; a real lenslet's edge is a bevel that bends light toward the axis and catches a key light.
- Tactic 3: `minPoint` (vector to the site) is already computed — the wall normal comes from the same neighbour pass; the 9 neighbour vectors are cached from the first loop (no extra hash/sin).
- Tactic 6: C is display-history colour; unchanged, no new continuity needed (idea 2 is purely geometric, time from `time` + existing speed).

Formula admission: bevel row is tactic 1 (kernel) — Worley is not in the §12.2E table, so the one-sentence family argument: the file *is* a Voronoi kernel; IQ's exact border distance is the canonical better version of its F2−F1 wall proxy and consumes the 9 site vectors it already computes. Warp row = §12.2E additive domain twist spirit: it acts on the coordinate before the existing lookup, consuming only `uvScaled`. Deletion test both ways passes (without either: same effect; with only the warp: not a zoom-lens tiling).
