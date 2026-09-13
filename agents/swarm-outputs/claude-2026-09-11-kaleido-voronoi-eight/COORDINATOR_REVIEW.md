# Coordinator review — kaleidoscope / voronoi eight (2026-09-11)

Checklist per `docs/SHADER_UPGRADE_BATCH.md` §9.

| ID | Card before diff | Ideas pointable in WGSL | KEEP VERBATIM holds | Diff not ≥70% boilerplate | No shared overlay w/ batch-mate | A packing matches C read | Saved params unchanged | Springs/ripples native only | Naga+extraBuffer+dead-sliders |
|---|---|---|---|---|---|---|---|---|---|
| astral-kaleidoscope | ✅ | ✅ pointer-center mix; seamGlint | ✅ | ✅ | ✅ | ✅ (display RGBA, unchanged) | ✅ (segments/rotation_speed/spiral_strength/trail_persistence byte-exact) | N/A (no springs/ripples added; existing ripple loop untouched) | ✅ |
| astral-kaleidoscope-gemini | ✅ | ✅ warpPower audio term; pointerWarp term | ✅ | ✅ | ✅ (distinct from grokcf1 — warp channel, not rotation) | ✅ (unchanged) | ✅ (segments/rotation_speed/spiral_strength/trails byte-exact) | N/A | ✅ |
| astral-kaleidoscope-grokcf1 | ✅ | ✅ rotSpeed/spiralStr audio scale; grabSpiral term | ✅ | ✅ | ✅ (distinct from gemini — rotation channel, not warp) | ✅ (unchanged) | ✅ (byte-exact) | N/A | ✅ |
| voronoi | ✅ | ✅ `drift` term; `sparkleBurst`/`sparkle` term | ✅ | ✅ | ✅ | ✅ (unchanged) | ✅ (cell_density/jitter/ridge_strength/palette_shift byte-exact) | N/A | ✅ |
| voronoi-chaos | ✅ | ✅ `snapGate`/`snapSeed` term; `history` blend | ✅ | ✅ | ✅ | ✅ (new — documented; A/C were unused before) | ✅ (Cell Scale/Chaos Amount/Color Mix/Center Dot Size byte-exact) | N/A (mouse drives directly, no spring added) | ✅ |
| voronoi-dynamics | ✅ | ✅ `mouseCellBoost`/`effDist`; `attraction` mix; `bubblePulse`/mids edgeHue | ✅ | ✅ | ✅ | ✅ (unchanged, raw sim state) | ✅ (centroidCount/repulsion/attraction/edgeWidth byte-exact — roles now actually live) | N/A | ✅ |
| voronoi-glass | ✅ | ✅ `crackLine`/`fractureGate`; `history`/`refractionActivity` | ✅ | ✅ | ✅ | ✅ (unchanged, now read back — documented) | ✅ (density/refract/border/attract byte-exact) | N/A (mouse drives attraction directly) | ✅ |
| voronoi-shatter | ✅ | ✅ `shockDisplace`/`shockRot`/`shockEnergy`; `chatterAngle` | ✅ | ✅ | ✅ | ✅ (unchanged, raw sim state) | ✅ (density/force/rotation/gaps byte-exact) | ✅ (ripples[] is the native, already-bound mechanism — no extraBuffer spring added) | ✅ |

## Notes on judgment calls

- **Struct field-order defect** (all three `astral-kaleidoscope*` files):
  this was a genuine binding-layout bug, not a style choice — the 2nd/3rd
  `Uniforms` fields were declared in the opposite order from the engine's
  canonical `(config, zoom_config, zoom_params, ripples)` layout, so the 4
  real UI sliders were silently reading raw time/mouse bytes and vice
  versa. Fixing it is squarely "plumbing floor," not a 5th idea — flagged
  as a defect fix in each Idea Card, consistent with how the 2026-09-11
  drag/trail batch treated temporal-echo's `config.y`-as-audio bug.
- **gemini vs. grokcf1 differentiation:** these two files were byte-identical
  except comments before this batch (confirmed via `diff`). Deliberately
  gave them non-overlapping mechanisms (gemini: warp channel + noise
  epicenter; grokcf1: rotation/spiral channel + angular grab) so the two
  variants read as distinct effects rather than the same overlay pasted
  twice — this is the one place in the batch where "avoid a shared overlay"
  took active design work rather than falling out naturally from different
  source files.
- **voronoi-chaos A/B/C packing:** HEAD never used A/C at all (pure
  boilerplate binding declarations, no read or write). Declaring "display
  RGBA history" as the packing is a new commitment, not a preserved one —
  called out explicitly in the Idea Card's A PACKING line as required when
  HEAD packing isn't already consistent.
- **voronoi-dynamics dead sliders:** `repulsion`/`attraction` were computed
  and discarded — confirmed by reading the full function body before
  writing the card (doc §2's "if you cannot fill KEEP VERBATIM... stop"
  check). The dead-sliders audit run after the edit confirms 0 remaining
  dead sliders on this file.

## Verdict

8/8 shaders: PASS. Every file has a written Idea Card predating its WGSL
diff, 2 native ideas each pointable in the code, KEEP VERBATIM intact,
saved `params` byte-exact, and green structural gates. Real-GPU visual QA
is external (no GPU in this VM) and still required before calling the
batch done end-to-end.
