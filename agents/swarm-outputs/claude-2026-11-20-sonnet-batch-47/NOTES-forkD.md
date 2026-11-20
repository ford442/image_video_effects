# NOTES — fork D (sonnet/batch-47): chronos-brush, voronoi-zoom-turbulence

Both second pass. Cards in BRIEFS-forkD.md (written before any WGSL edit). Scratch + renders:
`/tmp/claude-0/-root-image-video-effects/0cb7fcb4-a909-48c6-8c65-36fcc249f77c/scratchpad/D/` (head/ = origin/main copies, out/ = PNGs + .raw).
VM is SwiftShader: structural + CPU-render proof only, **no real-GPU visual QA claimed**.

## chronos-brush  (public/shaders/chronos-brush.wgsl, 37+/27− vs origin/main incl. the coordinator's prelude swap)

- **ADD 1 — wet-edge pooling (§12.2C "Wet-edge accumulation")**: `-∇²a` (5-point stencil at ±rimStep, rimStep = 0.16·radius·res.y clamped 2..12 so it tracks the brush's edge softness) on the paint-freshness field C.a; pooled rim gets saturation ×(1+0.7p) and value ×(1−0.38p). Gated by `smoothstep(0.08,0.45,a)` so it dries away with the stroke. `// ── Idea 3` in the WGSL.
- **ADD 2 — dwell pressure (§12.2C "Dwell pressure")**: `pressure = held · smoothstep(0.2,0.9, C.a at the cursor texel)`; radius ×(1+0.6·pressure), freshness deposit +0.1·pressure·brushMask, wet-edge gain 5.0→7.5. Speed-thinning falls out (fast sweep over fresh canvas ⇒ low pressure). `// ── Idea 4`. Uses `zoom_config.w`, which HEAD declared as "available, not needed".
- **KEEP VERBATIM (checked in diff)**: all 4 params/roles; bass_env brush size; wobble history UV; thaw drip (Idea 2); shutter (Idea 1); hue/HSV tint; depthOpacity; click-stamp blooms; decay formula; exact `textureLoad` on C; paint/erase.
- **A packing**: `dataTextureA` UNCHANGED (raw feedback RGBA, a = freshness, never tonemapped). `writeTexture` = same RGB + wet-edge rim (display-only, so nothing accumulates). Header `A packing:` line says so.
- **Rescues**: none. **Flags, not touched** (open decisions for the coordinator):
  1. Output has been history-only (black outside strokes) since 2026-05-30 (`a0f01da8` → `2cc45d36`); the original composited frozen paint over the live feed. Treated as the file's current identity; restoring the live composite would change 100% of default pixels.
  2. `alpha += bass*0.05` per frame (HEAD) pins freshness near 1 everywhere under loud bass (steady state ≈ 2·bass with decay 0.975). Consequence for the new idea: under loud bass a *held* brush reads pressure≈1 and blooms to 1.6× even without dwelling; wet-edge also flattens (field becomes uniform).
- **Diff vs HEAD (256², SRC=img, synthetic dark source)**: unheld drag (pointer path, down=0) 1.6–2.8 % of pixels (rim only; painted area identical); held drag 17.4 % (bloom + rim); held stationary 50 frames: painted area 2145 → 3824 px (1.78×); down=0 stationary: 2145 → 2145 (identical area). 0 NaN in paint, erase (mode=1), max params + loud audio + ripples, all-zero params.
- **Timing (384², held drag, interleaved, min-of-drained-frames)**: median per-round 1.25×, min-of-mins 1.24× (7 rounds, load avg ≈ 4–5). An earlier 5-round run at load avg ≈ 30 (other forks) read 1.02–2.9× and is not meaningful. New cost = 5 extra `textureLoad`s (4 rim + 1 cursor).
- **Gates**: precommit 1/1, naga-wasm 1/1, dead-slider audit 0 new (all 4 sliders read: brushSize, freezeDecay, timeDistort, eraseMode), audit_extrabuffer PASS (file uses no extraBuffer).

## voronoi-zoom-turbulence  (public/shaders/voronoi-zoom-turbulence.wgsl, 48+/5− vs origin/main)

- **ADD 1 — exact bisector wall distance → chamfer bevel (tactic 1, Worley border distance)**: the loop now also keeps the 2nd/3rd nearest site vectors (branchless shift cascade, no array); wall distance = min over the bisectors vs site 2 and site 3 `dot(0.5(a+b), normalize(b−a))`, plus the wall normal. Bevel: `bevelAmt = (1−smoothstep(0,0.16,wallDist))²`; sample UV += `wallN·bevelAmt·0.2` (cell units, convex-lens compression at the wall) and `hdr *= 1+0.34·bevelAmt·dot(wallN, L)`, L = up-left key light. F2−F1 neon rim untouched and still additive on top. `// ── Idea 3` in the WGSL.
- **ADD 2 — turbulent lattice warp (§12.2E "additive domain twist" spirit)**: lattice coord `lat = uvScaled + 0.22(1+0.4·mids)·(sin(0.9y+0.35x+T), sin(0.77x−0.41y−0.8T))`, T = time·(0.16 + speed·0.12) (existing Turbulence-Speed role); cell lookup uses `lat`, the image sample is built from the un-warped `uvScaled` + zoom shift, so only cell geometry curves/breathes. `// ── Idea 4`.
- **KEEP VERBATIM**: 4 params/roles; animated sites; F1/F2 loop results (same `minDist/second/minPoint/cellId`); closed-form zoom about the site; clamp; shear conveyor; neon rim (Idea 1); centroid inflation (Idea 2); ripple fronts; IQ palette mix; exact-C hist mix; ACES; agitation alpha; the spring block.
- **A packing**: ACES display RGBA, agitation in alpha — UNCHANGED (C read as display-history colour).
- **Rescues**: none. **Flag, not touched**: the extraBuffer[133..138] spring is inert in the app (those slots are zeroed per frame ⇒ `spring == mouse`; it only "works" in the persistent-buffer test harness). Cleanup candidate, same as nlm/prismatic in batch 46.
- **Diff vs HEAD (384², defaults, audio .3/.2/.1)**: 70.7 % of pixels change by >0.02, 32 % by >0.1 — inherent: the warp moves every wall, so every cell boundary and the content inside shifts. Look is the same tiling (cells, zoom pulses, neon rim) with curved walls and lit bevels. 0 NaN at defaults, held pointer + ripples + loud audio + mouseInfl=−1 + density 5, zoom/speed = 0 (static).
- **Timing (384², interleaved)**: first full version (9-slot array + second pass) read ≈1.5–1.7× (dynamic indexing is expensive on SwiftShader) → replaced by the cascade. Final: median 1.11× (6 rounds, load ≈ 5) and 1.35× (7 rounds, load 5–7); min-of-mins 1.26–1.27×. Decomposition: warp alone ≈ 1.0–1.1×, bevel alone ≈ 1.1–1.3×. Within the ≈1.3× cap but at the upper end.
- **Known limits**: bevel considers the 2nd/3rd nearest sites inside the 3×3 window only (not a 5×5 border pass); a 4th-nearest wall could be missed in rare configurations far from any bevel-band pixel — no visible kinks at vertices in the 256–384² renders.
- **Gates**: precommit 1/1, naga-wasm 1/1, dead-slider audit 0 new (cell_density, turbulence_speed, zoom_intensity, mouse_influence all read), audit_extrabuffer PASS (only the pre-existing 133..138).

## JSON
- chronos-brush.json: description sentence appended (wet-edge + dwell), `"held-drag"` added to features (pointer-held pressure is now real); `params` and `x-meta.upgrade.params` untouched.
- voronoi-zoom-turbulence.json: description sentence appended (bevel + warp); features/params untouched.

## Formula names for the coordinator's COORDINATOR_REVIEW
- chronos-brush: Wet-edge accumulation (§12.2C); Dwell pressure (§12.2C).
- voronoi-zoom-turbulence: exact Worley border distance (§12.1 tactic 1 — no §12.2E row exists for Voronoi); additive domain twist (§12.2E, as a lattice warp).
- No row shared between the two files; none overlaps the other forks' claimed rows (no Cauchy/Brown–Conrady/Airy/orbit-trap/TAA used).

## Not verified
Real-GPU look and pointer feel (held transitions, dwell ramp timing in a real browser), rim visibility on a real photo (synthetic source is dark after the brush tint), per-frame cost on a real GPU.
