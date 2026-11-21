# NOTES — fork C (sonnet/batch-48): scanline-cyberpunk, spectrum-bleed

Cards + mechanism interrogation: `BRIEFS-forkC.md` (written before any WGSL edit; one wording change after: luma take-back 65 % → 50 %, recorded there).
Baseline = worktree file at fork start (scanline-cyberpunk and spectrum-bleed were already on `_prelude.wgsl`, so baseline == origin/main for both).
VM = SwiftShader; **no visual QA claimed** — the pictures below were looked at on the synthetic `SRC=img` source only.

## scanline-cyberpunk (first pass)

**ADD (findable via `// ── Idea n` comments)**
1. Sync-edge line hook — §12.2B *sync-pulse timing*. `rollPhase/behindBar/barHash/syncHook`, added as a third term inside the existing `fp128_sum` offset accumulator (`fp128(syncHook * glitchAmt * 0.9)`). Reuses the head-roll bar's own phase as the decay coordinate (promoted intermediate).
2. Dropout bursts — §12.2B *dropout bursts*. `lineId/dropWin/dropP/dropRow/dropX/dropPol/dropTail`; applied to `col` right after the C mix, i.e. BEFORE scanline mask / triad. Rate = existing glitch slider × (1.1 + mouseField·1.2 + clickFront·1.5); ~110 ms windows staggered per line; alpha gets `+dropTail·0.05`.

**KEEP VERBATIM (unchanged lines):** Fp128 arithmetic, 20 bands + carrier, headRoll, mouseField/held, click fronts, C mix (`prev·0.9` at `headRoll·0.15`), `gid.y%2` mask, `gid.x%3` triad, `phosphor_runner`, flicker, neon overlay, `colorGrade`, ACES, depth pass-through, all four param roles, B = (bass, mid, treble, glitchOffset).
**A packing:** display RGBA == writeTexture (unchanged). **B:** unchanged; `glitchOffset` now includes the hook (it already meant "the horizontal offset applied").
**Not used (and why):** field interlace (would strobe the HEAD static mask), Schmitt lock (needs a latch in C.a = semantic alpha → packing lie). No spring, ripple, IQ palette, or new param.
**Header:** added Category/Features/Complexity/`Upgraded: 2026-11-21`/`Ideas:`/`A packing:` (Features = audio-reactive, mouse-driven, upgraded-rgba — all true). JSON: description sentence appended only; `params` + `x-meta` untouched (diff = 1 line).

**Rescue (changes default look slightly — flagged):** `uv = gid/dims` sampled the source at the texel *corner*: the bilinear sampler returned a 2×2 box average shifted half a pixel up-left. Now `(gid + 0.5)/dims`. Rescue alone changes 44.5 % of pixels by >1/255 at defaults, only 1.1 % by >8/255 on the smooth synthetic source (it will be more visible on real photos/video with fine detail).

**Diff vs baseline (384², 6 frames, defaults 0.5/0.4/0.3/0.6, mouse .7,.4, audio .4/.3/.3):** >1/255 54.3 %, >8/255 2.4 %, meanAbs 0.0084. Ideas alone (rescue→new): 23.8 % / 1.1 %. At glitch=1, bass .6: 64.6 % / 18.8 %. Per idea (vs rescue-only): hook 23.2 % (default) / 42.4 % (max); dropout 0.7 % / 1.4 % (sparse streaks by design). **glitch slider = 0 ⇒ new is bit-identical to rescue-only** (0.0 % diff): both ideas are off at 0.
**Timing (mr_ab, 256², 40 cycles, 5 interleaved rounds, box loaded):** ratio min per round 1.14/1.10/1.26/0.91/0.92 → median 1.10; paired-median per round 1.30/1.08/1.09/1.21/0.94 → median 1.09. Under the 1.3× cap (noisy).
**Stress:** all-0, all-1 params, held pointer, 2 clicks, audio 0 / 1 / .9: NaN 0, meanA 0.98, not blank.
**Gates:** precommit 1/1, naga-wasm 1/1, dead-slider audit PASS (all four sliders live: x scanline, y phosphor, z glitch, w grade), extrabuffer audit PASS (shader does not touch extraBuffer).

## spectrum-bleed (second pass)

Existing `Ideas:` entries (wavelength-ordered bleed distance; chromatographic advance front; dry-edge rim) untouched and still in the header; `Upgraded: 2026-09-21, 2026-11-21`.

**ADD**
4. Chroma delay line — §12.2B *chroma delay line (4:2:0)*. `chromaDelay/bleedRaw/bleedYC`: the existing `spectralBleed()` is fetched at `uv − (1.6·localRadius/res.x, 0)` (same 12 taps, no extra call), then half of the luma is taken back from the crisp source (`bleedRaw + (Y_src − Y_bleed)·0.5`). Colour trails to the right of edges; wavelength-ordered radii preserved.
5. Paper-fibre wicking — §12.2C *paper granulation*. `fibre = valueNoise(pixel/(2,10))` (static, no time term) scales the per-pixel bleed radius 0.55×–1.45× and the persistence weight 0.8×–1.2×. Admitted because this shader *is* ink-on-paper chromatography (it already owns "advance front" and "dry-edge rim").
Helpers (`pcg2d, u32ToUnit, hashCell21, fade2, valueNoise`) are copied verbatim from `public/shaders/_std/` per §12 — ~30 of the 40 added code lines; the idea code itself is ~10 lines.

**KEEP VERBATIM:** all four param roles, `spectralBleed()` 0.55/1.0/1.7 ordering, hue rotation, lens + click ink, FFT voice, advance/frontGate/dry-rim math, `effectEnergy` alpha, ACES. **A packing:** ACES display RGBA (unchanged).
**Header/JSON:** `Ideas:` appended; JSON description sentence appended only (`params` untouched, diff = 1 line). `features` unchanged (no new audio/pointer claim).
**Forbidden and avoided:** Cauchy / Brown–Conrady (pixel-focus), springs/ripple overlays, IQ palette, new params.

**Rescues:** none applied. **HEAD finding (report only, not fixable here):** the spring state in `extraBuffer[133..138]` is re-zeroed every frame (`src/renderer/webgpu/audioDepth.ts` `writeExtraBuffer` uploads the whole `EXTRA_FLOATS` scratch each frame), so `initialized` is always false → `springPos == rawMouse`, `springVel == 0`, and `springVel * lens * 0.5` is a dead term; the JSON description's "Sprung" is aspirational. `docs/agents/WGSL_BUILTINS_GENERATIVE.md` still lists `[133..255]` as safe persistent state — that is stale. Same dead-spring pattern likely exists in every file that persists a spring there.

**Diff vs baseline (384², 8 frames, defaults 0.5×4, mouse .7,.4, audio .4/.3/.3; measured on the shipped 50 % build):** >1/255 57.3 %, >8/255 2.5 %, meanAbs 0.0074. At p=(.8,.5,.8,.5): 82.0 % / 8.8 %. Per idea (vs baseline): fibre-only 38.6 % / 0.7 %, delay-only 33.7 % / 2.4 % (default); 58.8 % / 2.4 % and 66.3 % / 7.2 % (hi). Visually: luma edges firmer than the soft HEAD blur, colour fringes offset rightwards, faint fibrous vertical grain — no striping.
**Timing (mr_ab, same recipe; 50 % build, same tap count as the 65 % build it was first timed on):** min ratio per round 0.83/1.12/1.14/1.03/1.02 → median 1.03; paired-median 0.86/1.00/1.06/1.02/0.86 → median 1.00.
**Stress:** all-0, all-1, held pointer + 2 clicks + loud audio: NaN 0, meanA 1.0.
**Gates:** precommit 1/1, naga-wasm 1/1, dead-slider audit PASS (intensity/speed/scale/detail all read), extrabuffer audit PASS (pre-existing 133..138 writes are in the allowed zone).

## Not verified / for the coordinator
- No real-GPU visual QA. Both effects looked right on the synthetic source only; the hook amplitude (0.9·glitchAmt) and dropout rate (1.1·glitchAmt per window) are tuned by eye on that source and a 2-fps-class software adapter.
- Audit scripts regenerate `reports/dead_sliders_audit.*`, `reports/extrabuffer_write_audit.json`, `reports/wgsl_precommit_report.json` — churn, not part of this fork; coordinator discards.
