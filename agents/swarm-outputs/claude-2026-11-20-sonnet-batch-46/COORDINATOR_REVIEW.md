# COORDINATOR_REVIEW — sonnet/batch-46 (gravitational / flow / dispersion ten)

Reviewed against `docs/SHADER_UPGRADE_BATCH.md` §9 + §12.7. Worktree `/root/iv-sonnet-batch-46`, from origin/main 673d780a.

**What the coordinator verified directly:** Idea Cards/BRIEFS exist for all five forks; every numbered idea is findable from a `// ── Idea n` comment in the WGSL (grep); saved `params` byte-exact vs `origin/main` for all 10 JSONs (script diff of the `params` array); `Upgraded:` / `Ideas:` / `A packing:` header lines present and correct; per-file gates re-run (precommit 10/10, naga-wasm 10/10, dead sliders 0 new, extraBuffer 0 new); `verify:shaders:fix` 11/11; Vitest 212 files / 1944 pass / 1 skipped; `npm run build` ok.

**Taken from the fork reports, not re-measured:** SwiftShader renders, pixel-diff percentages, timing ratios, NaN sweeps, the CPU-side checks (e.g. cosmic-flow twinkle phase, raptor cross-correlation). No real-GPU visual QA exists for any file.

## Per file

| id | pass | ideas (formula row) | A packing | verdict |
|---|---|---|---|---|
| gravitational-lensing-nlm | 1st | Buades-form NLM weights (NLM kernel deepening); disk g-factor (redshift); photon ring from closest approach | ACES display RGBA | PASS — see flag 1 |
| distortion-gravitational-prismatic | 1st | 7-band energy-normalised Cauchy (§12.2F Cauchy); spectral Einstein ring | ACES display RGBA | PASS — see flag 2 |
| distortion_gravitational_lens | 1st | critical-curve magnification (§12.2F); Doppler-beamed disk (§12.2F blackbody) | display RGBA | PASS — see flag 3 |
| kinetic-dispersion | 1st (Ideas) | Schmitt shatter latch (§12.2B); block-boundary seam (§12.2B) | display RGB + A.a = −latch | PASS — see flag 4 |
| ethereal-swirl-coupled | 1st | two-way swirl↔fluid coupling; dye-gradient refraction (§12.2F Snell); curl-tinted hue (§12.2D) | A = (vel.xy, display-luma history, dye); (0,0)=mouse | PASS with cost flag 5 |
| hybrid-chromatic-liquid | 1st | slope-driven dispersion (§12.2F Snell direction); normal Fresnel + glint (§12.2F) | display RGBA copy | **PASS — USER DECISION, flag 6** |
| conv-structure-tensor-flow | 2nd | coherence-adaptive LIC length; curved streamlines (both §12.2A structure tensor) | ACES display RGBA | PASS — see flag 7 |
| optical-flow-tracer | 2nd | Gaussian LK window (§12.1 t1); temporal flow carry through C (§12.1 t6) | raw flow field, read back raw from C | PASS — see flag 8 |
| cosmic-flow | 1st | dust lanes with reddening (§12.2F Beer–Lambert); Airy point-spread stars (§12.2F Airy) | HDR RGB + semantic alpha; stars not stored in A | PASS |
| gen-raptor-mini-flow | 1st | streamlined body along heading (§12.2A structure tensor); pursuit wake (§12.2F soft inverse-square) | ACES display RGBA | PASS — see flag 9 |

## §12.7 checklist

- [x] BRIEFS show mechanism interrogation (forks A–E).
- [x] Every formula named by §12.2 row in NOTES and the `Ideas:` line.
- [x] No §12.2 row on more than two files. Snell: ethereal-swirl-coupled + hybrid-chromatic-liquid (2, different quantities: dye-density gradient vs surface slope; no second shared row). Structure-tensor: conv-structure-tensor-flow + gen-raptor-mini-flow (2, different second ideas). Everything else appears on one file.
- [x] Each formula consumes a quantity the file already had; no new solver, binding or spring added by this batch.
- [x] No `fwidth`/`dpdx` in any file. Two files (nlm, prismatic) still carry a HEAD spring in `extraBuffer[133..138]`, untouched — see flag 10.
- [x] No overlay shared across the batch: no file got a spring, ripple or IQ palette from this batch.

## Flags — decisions or follow-ups for the user

1. **nlm default look.** HEAD rendered the world rolled 180° (disk overhead). Camera basis fixed and the panorama lookup compensates, so the photo is pixel-for-pixel as before; the disk now sits in the bottom half. Camera at r=20 still sits inside the disk annulus (left alone).
2. **prismatic default look.** A flat 0.6 grey gave sRGB (229,182,178) at HEAD, now (172,172,172): every saturated colour changes (HEAD pushed colours toward orange/pink). The "Einstein ring" at HEAD was a dot on the mass; it is now at θE of the file's own deflection law. The deflection is diverging (negative-mass lens), as at HEAD — the ring is a drawn feature, not a caustic.
3. **distortion_gravitational_lens.** `sourcePos` sign is opposite to the standard lens equation (diverging lens) and there is no aspect correction (elliptical on 16:9) — both kept as HEAD. `audioPulse` read `zoom_config.w` (mouse_down): click behaviour kept, real bass added.
4. **kinetic-dispersion.** The pointer spring in `extraBuffer[133..137]` was dead and every pixel read its centre from a buffer only thread (0,0) wrote; centre is now `mouseRaw`, dead spring + `velBoost` removed. "mouse-velocity" in the description is still not real (no place to keep velocity); the wake is a stateless stand-in. Shatter-latch decay is per frame (≈0.25 s half-life at 60 fps), so frame-rate dependent. `agents/mr.mjs` keeps extraBuffer between frames, so its HEAD render of this file is not what the app showed.
5. **ethereal-swirl-coupled cost: ≈1.6× HEAD, over the ~1.3× cap.** Fork C attributes it to the rescue (white-noise `fbm` → smooth value noise), not the ideas: a single hash instead drops it to ≈1.2×. Left over the cap deliberately; the default look changes a lot (grain → smooth clouds, mean luma 0.20 → 0.53, green cursor stroke gone). Vorticity confinement was tried and rejected as unstable at every useful strength (NOTES-forkC).
6. **hybrid-chromatic-liquid — needs the user's call.** HEAD's WGSL (commit `9983b1eb`, "Fix batch of 24 shaders via subagent", decompiler-style `_e7`/`p3_` code) was a halftone/ink print whose four sliders drove dot size / edge threshold / levels / ink density, while the JSON name, first description sentence and param labels ("Flow Field Scale / Liquid Distortion / RGB Split / Flow Speed") describe a flow-field RGB-split liquid. Fork C restored the JSON-defined liquid (with the `let`→`var` fix that the pre-9983b1eb version needed) and put both ideas on it: **100% of pixels change** vs HEAD. Cost ≈1.3–1.5× the restored original (≈2× HEAD, not meaningful — different algorithm). The restored highlight is unbounded, so at distortion = 1 mean luma ≈1.05 (original behaviour, left). To keep the halftone instead: revert this file and give the halftone its own id and params. The coordinator confirmed the commit history and the HEAD mismatch directly.
7. **conv-structure-tensor-flow.** Orientation hue now uses the doubled angle (π-periodic): HEAD flipped hue on rounding noise (pure vertical ramp → purple/green stripes). θ=0 is unchanged but tilted structure now spans the whole palette — a more rainbow default. The two new ideas are quiet at defaults (16.6% of pixels >2/255, 0.8% >8/255 vs the rescue-only build). Tensor is built from one shared 5×5 window (25 taps vs 108), timing 0.86× HEAD.
8. **optical-flow-tracer.** `mouse-driven` tag removed from header + JSON (file never reads the pointer). `decay` slider is nearly inert because the weights are normalised — noted, left alone. Carry was rebuilt as an LK initialisation after a plain post-blend amplified the halo ×1.5. At 3 px/frame jitter is 19% worse and at 5 px/frame HEAD already fails. Synthetic textured disc only; untested on real video and on a mid-chain shader switch.
9. **gen-raptor-mini-flow.** HEAD raptors moved *away* from the cursor (measured dx = −3 px at HEAD, +3 px after) — this reverses the travel direction of every saved look that used the cursor; picture at t=0 is the same. ACES lifts default mean luma 0.151 → 0.187 (floor, not an idea). The two `normalize` guards were not reproducible on SwiftShader.
10. **Pre-existing, not touched: nlm and prismatic each carry a HEAD `extraBuffer[133..138]` spring (11 refs both before and after).** Because the engine zeroes that range every frame the spring starts at `rawMouse` and writes `rawMouse`, so every thread reads the same value — inert dead code, not a visual defect. Candidate for a later cleanup; not an upgrade.

## Gates

precommit 10/10 · naga-wasm 10/10 · dead sliders 0 new · extraBuffer 0 new · `verify:shaders:fix` 11/11 · Vitest 1944 pass (212 files) · build ok · `upgrades:record --ids=` 10 changed, 0 new. `prelude_migration.json`: the 8 migrated ids left `pending` (`--fix` behaviour). Real-GPU visual QA: external.
