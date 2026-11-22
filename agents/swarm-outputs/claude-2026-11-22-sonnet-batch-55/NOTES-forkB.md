# NOTES — fork B (knitted-fabric, lenticular-holographic-shift)

Cards, checklist verdicts and mechanism interrogation: `BRIEFS-forkB.md` (written before any WGSL). HEAD copies + renders: `/tmp/claude-0/-root-image-video-effects/741dbe8f-87a6-4dc9-8039-cfc9fd9fdfde/scratchpad/b/`. Files touched: `public/shaders/knitted-fabric.wgsl`, `public/shaders/lenticular-holographic-shift.wgsl`, and the `description` string only in `shader_definitions/interactive-mouse/knitted-fabric.json` and `shader_definitions/image/lenticular-holographic-shift.json`. `params`, `features`, `x-meta` untouched. Nothing committed.

## knitted-fabric  (153 → 177 lines, 2nd+ pass)

- **ADD 1 — round-yarn tube shading + Fresnel–Schlick fibre sheen (§12.2F, B-owned).** `// ── Idea 1` block after `plyShade`: tube cross-section from the already-computed `across` / `yarnWidth`; half-Lambert from an upper-left key; Schlick sheen `0.04+0.96·(1−n.z)^5` tinted by `baseColor`. Applied at the `plyShade` line and after the shimmer line.
- **ADD 2 — loop-over-loop cast shadow (no §12.2 row).** `// ── Idea 2` block: the existing loop arc re-evaluated at a light-shifted, period-wrapped `local`; `(1 − topYarn)` keeps it off the loop itself; amount `0.12 + 0.28·TextureDepth` (the slider already means "how deep the fabric reads").
- **KEEP VERBATIM:** 4 param roles; pull/pluck warp; stitch lattice and purl offsets; strain-thinned yarn; two-ply twist; heather/flecks; band shimmer; lint; ACES `aces(max(c,0)·0.8)`; alpha; depth; every A/B store.
- **A packing:** unchanged — ACES display RGBA; B = (yarnMask, max(pull,clickRidge), shimmer, alpha) documented masks, kept. B is write-only (binding 8) so nothing could read it; kept because the header documents it and it is a secondary output.
- **Rescues:** none needed. Checklist: ACES yes, `plasmaBuffer[0].xyz` yes, no extraBuffer, no `config.y` misuse. **No `dataTextureC` load added** (see BRIEFS: no native idea fits the display-RGBA A packing).
- **Diff vs HEAD (256 px, defaults, SRC=img, 40 f, t 4 s):** 23.5 % of pixels differ > 8/255, mean abs 4.1/255; meanL 0.296 → 0.303, stdL 0.161 → 0.166, meanA 0.472 → 0.472 (unchanged). Pull and click renders (512 px) show no artefacts; no NaN at default, pull, click, or all sliders 0/1.
- **Timing (SwiftShader, 256 px, interleaved):** ratio of mins 1.01 — box load 17–19 from the other forks, so medians were unreadable; adds ~15 ALU ops/pixel, no taps.
- **Gates:** precommit 1/1, naga-wasm 1/1, dead-sliders pass (hand grep: x/y/z/w each read once), extraBuffer audit pass.

## lenticular-holographic-shift  (174 → 190 lines, 2nd+ pass)

- **RESCUE — dead view spring.** HEAD wrote `extraBuffer[133]/[134]` at gid(0,0) and read them back in every invocation; the host zeroes `[133..255]` each frame (also the harness, `mr.mjs:141`), so `viewPos` was 0 for every pixel except a same-dispatch race with a ≤ 0.026 nudge. **Verified:** HEAD mouse x 0.1 / 0.5 / 0.9 renders are visually identical (only the race jitters the strip phase) while the intended swing is ±0.64 `viewAngle` ≈ 0.9 strip; after the fix the 0.1 and 0.9 renders differ in 88 % of pixels with opposite holo hue and chromatic-fringe direction. Now stateless `viewPos = mouse.x`; the smoothing is gone (nothing to smooth without state) and the spring/extraBuffer code is removed.
  **Default look changes loudly:** at mouse 0.5 HEAD's baked `viewAngle ≈ −0.8` is gone (view ≈ idle drift only) → **77 % of pixels differ > 8/255 vs HEAD at defaults** (mean abs 14.8/255 before the lens-gain trim; meanL 0.486 → 0.486, meanA 0.768 → 0.769). Most of that is the rescue (strip phase / chromatic offset), the rest the two ideas.
- **ADD 4 — cylinder-lens magnification (no §12.2 row).** `lensDisp = (−lensX · 0.22 · clamp(shiftAmt,0,1) / freq, 0)` added to the R/G/B and parallax samples: each lenticule pulls its sample toward its own centre, snapping back at the seam → vertical magnified slivers (zero at Shift 0). `lensX = strip·2−1` hoisted up from the specular block (which still uses it).
- **ADD 5 — adjacent-view crosstalk ghost (no §12.2 row).** One extra `readTexture` tap displaced toward the nearer seam by `(0.15 + 0.45·sceneDepth)/freq`, mixed at `0.5·smoothstep(0.45,1,|lensX|)·clamp(shiftAmt,0,1)`; reuses `sceneDepth`. Reads as a soft double edge at lenticule seams.
- **KEEP VERBATIM:** 4 param roles; `strip`/`band`; R/G/B view offsets; depth parallax (Idea 1 of 11-10); moiré + holo cycling; click flash rings; ridge specular; vignette; grain; ACES; alpha; depth; A = display RGBA; B = (strip, moire, viewAngle, semantic alpha) — B kept (write-only mask quad, documented).
- **A packing:** unchanged (display RGBA; chained slots read C as colour). **No `dataTextureC` load added** (stateless filter; see BRIEFS).
- **Header:** the old Ideas lived inside the 2026-11-10 `Upgraded:` prose, so `upgrade-worker`'s `^// Ideas:` check could not see them; added a proper `Upgraded: 2026-11-22` block, an `Ideas:` line carrying every prior + new idea, and an `A packing:` line. Prior `Upgraded:` lines kept.
- **Timing:** swapped-order run NEW min 17.1 vs HEAD 15.9 (1.08×, p25 1.04×); first run ratio of mins 0.55 was load noise (HEAD 62 ms under load 19). One extra tap + ~20 ALU ops. Coordinator to re-time on a quiet box.
- **Gates:** precommit 1/1, naga-wasm 1/1, dead-sliders pass (x/y/z/w each read once), extraBuffer audit pass (no extraBuffer use remains). No NaN at default, mouse sweep, audio 0.9, all-sliders-max, and Shift/Color/Beat 0 with Frequency min.

## Open calls for the user
1. Lenticular default picture changes (rescue): mouse at rest no longer shows the old baked −0.8 view offset; the print now only "rocks" when the pointer moves. If a resting colour shift is wanted, raise the idle sway (`sin(time·0.3)·0.1`) — not done, it would be a new idea.
2. The spring's smoothing is lost on lenticular (needs state we don't have); a hard-edged view response is the honest stateless form.
3. No C read on either file by design; if the user wants one, the native candidates are yarn viscoelastic recovery (knitted) and view latching (lenticular), both needing a non-colour state texel, i.e. an A repack.
4. Real-GPU visual QA is external (SwiftShader only here).
