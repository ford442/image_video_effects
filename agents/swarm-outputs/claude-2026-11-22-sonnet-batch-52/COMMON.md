# COMMON — sonnet/batch-52 (user's list: temporal + audio-reactive post-processing, 126–220 lines)

Worktree: `/root/iv-sonnet-batch-52` (branch `sonnet/batch-52`, from origin/main a3706adc). Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12 (a fork already has it in context). Notes dir: `agents/swarm-outputs/claude-2026-11-22-sonnet-batch-52/` (gitignored → coordinator uses `git add -f`). `node_modules` is a symlink to the main checkout's.

**BASELINE ("HEAD") for every comparison = the bytes in `/tmp/claude-0/-root-image-video-effects/547473e0-56ec-49ad-94b1-b40db5a7c127/scratchpad/coord/head/<id>.wgsl`** (+ `_prelude.wgsl`, `_std/` beside it; `#include` resolves relative to the wgsl). The coordinator already ran `migrate_to_prelude.py` on `temporal-frequency-decomposition` (it pasted the 13 bindings; header-only, no `Upgraded:` bump, pixel output identical). Your very first action: copy your files to your own scratch dir as `<id>_head.wgsl` + `_prelude.wgsl` (+ `_std/`) and render/time against that copy. Coordinator HEAD renders: `.../scratchpad/coord/head_<id>.png` (read-only for you) and their stats (meanL/stdL/meanA/frameMs, one line per id) in `.../scratchpad/coord/head_render.log`. They were made with `mr_hist.mjs <head wgsl> <png> 256 40 4 <JSON defaults> 0.5,0.5,0 0.3,0.2,0.1`. Cost headroom is tight on `optical-flow-tracer` (≈3.3 s/frame at 256 on SwiftShader), `audio-reactive-pyramid` and `audio-reactive-rgb-dispersion` (≈1.6–1.7 s/frame): the 1.3× cap applies and you have little room.

## The pasted claim vs HEAD (coordinator verified; do not re-litigate, but DO verify anything you build on)

The user's note said: *almost all lack ACES and the exact load from dataTextureC, most write to extraBuffer slot 4, the two audio-reactive ones never read plasmaBuffer, temporal-rgb-ghost says interactive but has no mouse code.* Against HEAD:

- **extraBuffer[4]**: NO file writes it. All read it as `historyHead` (engine-owned: `[0]=bass [1]=mid [2]=treble [3]=0 [4]=historyHead [5..132]=128 FFT bins`, `src/renderer/webgpu/audioDepth.ts`). Nothing to fix. **Never write `[0..132]`.** Do not add state in `[133..255]` either (zeroed every frame by `writeExtraBuffer`).
- **dataTextureC**: only `optical-flow-tracer` reads C (already `textureLoad`, exact). The other nine use the **history ring (binding 13)** as their temporal memory and never read C. There is no sampled-C bug to fix and **do not invent C feedback**; keep A as it is (display copy of the output) unless you find it is inconsistent with a documented read.
- **ACES**: `temporal-frequency-decomposition, temporal-feedback-zoom-tracer, temporal-decay-multiresolution, temporal-rgb-ghost, spatio-temporal-3d-conv, temporal-layered-time-stamps, chrono-luma-slit-scan` have none but 5 of them carry the `upgraded-rgba` tag. **Policy P-ACES (decided; do not improvise):** these are passthrough photo composites. ACES on the whole output regrades every image (`audio-reactive-pyramid`'s header already makes this call). So: (a) do NOT add ACES to the photo path; (b) where the shader *emits* light beyond the source range (glow, accumulated feedback > 1, streaks), tone-map only that emitted term, after `clamp(max(x,0))` (catalog ACES maps negatives to bright), and keep the tag; (c) where nothing emits, remove the unearned `upgraded-rgba` from the JSON `features` and say so in the notes (§8: the tag is true only if ACES is in the WGSL). Never use `pow` with a possibly-negative base.
- **Audio**: `audio-reactive-pyramid` and `audio-reactive-rgb-dispersion` take bass/mid/treble from `extraBuffer[0..2]` and read the FFT bins `[5..132]`. The engine writes `[0..2]` and `plasmaBuffer[0].xyz` from the same state, so values are identical. **The bins are the idea (only source of per-bin data) and must stay.** Switching the three band scalars to `plasmaBuffer[0].xyz` is allowed (zero pixel change, matches the documented convention); the fork decides, with a diff-vs-HEAD of 0 px at identical audio as proof. Do not claim a rescue for it. Other files that read `plasmaBuffer[0].xyz` already follow the convention.
- **temporal-rgb-ghost** has `mouse-driven` in `Features:` and JSON `features` but contains no pointer read at all: either give the pointer a real native job (a spatially varying version of an existing param — tactic 4; the pointer must visibly change the picture) or drop the tag. Verify what HEAD does at defaults first: in the coordinator smoke render the static background came out near-black with alpha ≈ 0 (only moving edges survive) — decide whether that is the designed look or a defect, and say which.

## ID → file map (all `public/shaders/<id>.wgsl`, JSON in `shader_definitions/post-processing/<id>.json`)

Defaults = saved JSON params in `zoom_params.xyzw` order. **The harness defaults sliders to 1,1,1,1 — always pass these explicitly.** Every file is a 2nd-or-later pass: the `Ideas:` line is **KEEP VERBATIM** (every item stays; do not remove, weaken or re-add one).

| id | defaults (x,y,z,w) | existing `Ideas:` (KEEP VERBATIM) |
|---|---|---|
| temporal-frequency-decomposition | 0.25, 0.6, 0.17, 0.8 | Hann-windowed DFT; DFT phase -> glow hue |
| spatio-temporal-3d-conv | 0.4, 0.5, 0, 0.7 | motion-adaptive temporal weights (NR mode); variance-driven NR strength |
| optical-flow-tracer | 0.6, 0.4, 0.5, 0.35 | Shi-Tomasi confidence; pyramidal (coarse-to-fine) Lucas-Kanade; Gaussian-weighted LK window (§12.1 tactic 1); temporal flow carry through C (§12.1 tactic 6) — **upgraded 2 days ago (batch-46); A packing = raw flow field, documented in its header; keep it** |
| temporal-feedback-zoom-tracer | 0.5, 0.625, 0.71, 0.29 | nested monitor bezels; recursion hue drift; field lag; feedback-camera falloff |
| temporal-decay-multiresolution | 0.5, 0.5, 0.5, 0.3 | decay-shaped timescale kernels; time-inversion click rings; cross-scale cascade; stationary mute |
| temporal-layered-time-stamps | 0.5, 0.5, 0.6, 0.5 | true per-age spiral; onion-skin outlines; peg-bar shift; inter-stamp smear |
| audio-reactive-pyramid | 0.4, 0.5, 0.6, 0.7 | depth-routed bands; per-band chroma split; anisotropic fine gate; anti-halo envelope (§12.2A) |
| audio-reactive-rgb-dispersion | 0.5, 0, 0.5, 0.1 | bandwidth rainbow; lateral vs transverse CA by band balance; Cauchy tap spacing (§12.2F); edge-weighted falloff |
| temporal-rgb-ghost | 0.17, 0.67, 0.8, 0.25 | blue comet-tail integration; motion-gated displacement; fractional G delay; leading red; disagreement fringe |
| chrono-luma-slit-scan | 1, 0.3, 0.5, 0.1 | isochrone contour lines at integer-age seams; scan-runner windows onto the oldest frame; slit-travel smear; raised-cosine shutter |

Most of these already carry the 4-idea ceiling. **A second pass must be genuinely new and must pass the §12.1 same-noun / deletion / expert tests. If a file has no honest new native idea, ship its rescues only, say "no new idea — saturated" in the notes, and do not bump `Upgraded:`.** Do not invent a 5th idea to fill the slot. Line count is not a metric.

## Forks (disjoint files — forks cannot see each other; obey the claims below)

- **A** temporal-frequency-decomposition, spatio-temporal-3d-conv (temporal filters over the ring)
- **B** optical-flow-tracer, temporal-feedback-zoom-tracer (motion tracer / feedback tracer)
- **C** temporal-decay-multiresolution, temporal-layered-time-stamps (layered ring timescales)
- **D** audio-reactive-pyramid, audio-reactive-rgb-dispersion (FFT-driven pair)
- **E** temporal-rgb-ghost, chrono-luma-slit-scan (per-channel delay / slit scan)

## Cross-fork §12.2 row ownership (coordinator enforces §12.4 de-dup)

Prefer **domain-native** mechanisms (§12.1: a camera's rolling shutter, a tape deck's wow/flutter, a scope's graticule, a prism's real optics, an NR filter's noise model) — they need no ownership. Use a §12.2 row only if you own it:

- **Schmitt-trigger lock**: temporal-rgb-ghost, chrono-luma-slit-scan. **Dropout bursts / chroma delay line**: nobody. **Field interlace**: chrono-luma-slit-scan only.
- **Local contrast normalization (Wallis), guided-filter base/detail, structure tensor**: spatio-temporal-3d-conv only (Wallis/variance gating is already near what its idea 2 does — check before adding).
- **Anti-halo envelope, density-weighted grain**: audio-reactive-pyramid only (anti-halo already shipped; keep). **Cauchy dispersion, Brown–Conrady radial**: audio-reactive-rgb-dispersion only (Cauchy already shipped; keep). **Halation, photon shot noise**: nobody.
- **Damped wave / dispersion / vorticity / MacCormack**: nobody (these are sim rows; none of the ten is a solver).
- **Semi-Lagrangian advection of C along the flow**: optical-flow-tracer only (it owns C; any use must keep the documented raw-flow A packing).
- Frame-hash strobing, generic spring/ripple overlays, IQ cosine palettes bolted on as the whole look and `fwidth`/`dpdx` (do not exist in compute) are rejected everywhere. **No new springs in `extraBuffer`.** Files that already own the pointer/click (zoom-tracer, decay-multires, layered-time-stamps, slit-scan, frequency-decomposition) may extend what they already read; a pointer you add must visibly change the picture.

## Per fork, in this order

1. Read each file + its JSON in full. Run HEAD first (harness below), find HEAD defects (history-ring age/head off-by-one, `ageN` beyond `histDepth` clamp, blank/dark default, dead sliders, negative into a tonemap, `pow` negative base, hardcoded alpha 1.0 where a semantic alpha is owed, wrong audio source, dead mouse tag, divide by zero on silence/static) and fix them as **rescues**; list them. Rescues may change the default look: say so loudly.
2. Write `BRIEFS-fork<X>.md` here: Idea Card per shader + §12.1 interrogation answers (tactics 1,2,3,6) + §12.4 formula admission — **before any WGSL edit**. New ideas only.
3. Implement ≤3 new native ideas per shader (2 is the norm) in the existing main path; `// ── Idea n: …` comment at each; saved `params` byte-exact; keep the file's A packing and SAY SO on the card. Do not reflow code you do not touch.
4. Header: append `, 2026-11-22` to `Upgraded:` and the NEW idea names (with §12.2 row names) to the single `Ideas:` line — only if an idea was added. Rescue-only: no bump, add a short `// Rescue (2026-11-22): …` line. `Features:` tags only if true (§8).
5. JSON: append to `description` only if visible behaviour changed; `features` tags only when true; never touch `params`; `x-meta.upgrade.params` additive only.
6. `NOTES-fork<X>.md` per shader: Idea Card ADD list, KEEP VERBATIM, A packing, rescues, diff vs HEAD (% pixels differing), timing ratio, gates.

## Harness (VM = SwiftShader; no real GPU; do not claim visual QA)

**Use `agents/mr_hist.mjs`, NOT `mr.mjs`** — the stock harness binds a 1-layer empty ring and never writes `extraBuffer[0..4]`/FFT bins, so none of these ten does anything in it (a 1-layer ring returns the live frame at every age). `mr_hist.mjs` is engine-faithful: 8-layer ring filled with each frame's *output*, `extraBuffer[4]=head` (age a reads layer `(head+8-a)%8`), `[0..2]` = bass/mid/treble, `[5..132]` = 128 FFT bins, `[133..255]` zero, `plasmaBuffer[0]` = audio. Source = a MOVING scene (textured bg + translating disc + two blinking squares at 8- and 4-frame periods + gradient) regenerated every frame.

```
node agents/mr_hist.mjs <wgsl> <out.png> [size=256] [frames=40] [tEnd=4] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]
  env: D=8 | VX,VY disc px/frame at size 160 | STATIC=1 | OSC=0 | MPATH='[[x,y,d],[x,y,d]]' | SEEDC=r,g,b,a
       FFT=bands|flat|off | PERF=1 | RAW=path | SHOW=hist (4th panel = ring layer age 4) | T0=start time
  PNG panels (each `size` px wide): source(last frame) | output rgb | output over white | alpha
node agents/mr_ab_hist.mjs <size> <cycles> <p1..p4> <mx,my,down> <bass,mid,treb> <wgslHEAD> <wgslNEW>   # interleaved timing, ring populated; ratio of medians, ≥4 rounds
```

Render HEAD and NEW at defaults AND with params/mouse/audio exercised, at ≥2 times (e.g. frames 40/tEnd 4 and frames 120/tEnd 12), STATIC=1 and moving, FFT=bands with audio `0.8,0.6,0.5` and silence `0,0,0` (silence must not produce NaN/black/uniform output — check). Read the PNG. Check `nan` = 0 in the JSON it prints; check the picture is not blank/saturated/uniform. Cap **≤ ~1.3×** HEAD on the interleaved timer; trim if over and say so. The box is shared with other forks, so single readings lie; the coordinator re-times borderline files on a quiet box.

Scratch dir (not /tmp): `/tmp/claude-0/-root-image-video-effects/547473e0-56ec-49ad-94b1-b40db5a7c127/scratchpad/<fork-letter-lowercase>/`.

Gates, each file: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<file>.wgsl`; `node scripts/verify-naga-wasm.mjs --files public/shaders/<file>.wgsl` (stricter; `demote`/`target`/`__x` reserved); `python3 scripts/audit_dead_sliders.py --files <id>` (if the JSON has only `updatedParams` it scans 0 defs → grep each slider read by hand); `python3 scripts/audit_extrabuffer.py`. `pkill -f "[p]attern"` form only, and ONLY patterns naming your own scratch files.

## Do NOT

Commit, `git stash` (stash list is shared by every worktree), `git checkout`/`reset` anything, touch another fork's files, touch shared generated files (shader lists, search index, `reports/`, `src/contracts/*`, ledger) — the coordinator runs `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`. Do not add params or rename ids. Work ONLY under `/root/iv-sonnet-batch-52` (never edit `/root/image_video_effects`, which is on another branch).

## Report back (final message, ≤ 25 lines)

Per shader: the ADD ideas (one line each, with formula row if any), rescues, A packing, diff-vs-HEAD pixel %, timing ratio, gate results (N/N), tag changes (`features`, `Features:`), and anything you could not verify. Use absolute paths under `/root/iv-sonnet-batch-52`.
