# COMMON — sonnet/batch-51 (last un-ideated standalone effects, 7 files)

Worktree: `/root/iv-sonnet-batch-51` (branch `sonnet/batch-51`, from origin/main 49395199). Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12 (the fork already has it in context). Notes dir: `agents/swarm-outputs/claude-2026-11-21-sonnet-batch-51/` (gitignored → coordinator uses `git add -f`).

**Why these seven.** The user pasted nine ids that sonnet/batch-49 (PR #1720) had already upgraded and merged hours earlier, then chose "pick a fresh batch". A scan of origin/main for files with NO idea text at all (any format: `Ideas:`, `Ideas (date):`, `// Idea n`) leaves 29 files; 22 are multi-pass pipeline stages (optical-flow-*, chromatographic-*, kuwahara-*, physarum-*, murmuration-*, dla-*, sph-*, sim-fluid-*, photonic-emitter, gen_capabilities) or claimed by another live session (cosmic-web in /root/iv-sonnet-batch-50). These seven are the standalone effects left. Several carry only a **hygiene header** from an old batch ("Batch 34 / 18 / 58B / Visualist") — that is NOT an idea pass, treat them as first pass. Do not touch any other file. **Another Claude session owns `/root/iv-sonnet-batch-50` (generative `gen-*` batch) — never read-modify anything there.**

**BASELINE ("HEAD") for every comparison = the worktree file as it stands when you start.** The coordinator already ran `migrate_to_prelude.py` on rain, prismatic-3d-compositor, prismatic-feedback-loop, echo-trace, generative-psy-swirls (header-only infra, pixel output identical to origin/main, no `Upgraded:` bump); alucinate and liquid-smear already used the prelude. Your very first action: copy each of your files to your scratch dir as `<id>_head.wgsl` together with `public/shaders/_prelude.wgsl` (and `_std/` if you use it) *before editing*, then render/time against that copy. `#include` resolves relative to the wgsl's directory.

**ID → file map** (every id equals its file name; definitions live in `shader_definitions/<category>/<id>.json`):

| id | wgsl (public/shaders/) | definition json | name in catalog |
|---|---|---|---|
| rain | rain.wgsl | artistic/rain.json | Rain |
| prismatic-3d-compositor | prismatic-3d-compositor.wgsl | interactive-mouse/prismatic-3d-compositor.json | Prismatic 3D Compositor (Pass 2) |
| prismatic-feedback-loop | prismatic-feedback-loop.wgsl | interactive-mouse/prismatic-feedback-loop.json | Prismatic Feedback Loop (Pass 2) |
| echo-trace | echo-trace.wgsl | artistic/echo-trace.json | Temporal Velocity Echo |
| alucinate | alucinate.wgsl | image/alucinate.json | Alucinate |
| generative-psy-swirls | generative-psy-swirls.wgsl | generative/generative-psy-swirls.json | Psychedelic Swirls |
| liquid-smear | liquid-smear.wgsl | liquid-effects/liquid-smear.json | Liquid Smear |

**Forks (disjoint files — forks cannot see each other, obey the claims below):**
- **A** rain, prismatic-3d-compositor
- **B** prismatic-feedback-loop, echo-trace
- **C** alucinate, generative-psy-swirls
- **D** liquid-smear

**Header rules.** None of the seven has an `Ideas:` line, so all are *creative first pass*: write the standard banner (title, Category, Features, `Upgraded: 2026-11-21`, `Ideas:`, `A packing:`), and **keep the existing descriptive header text** (modes, slider contracts). If the file has a hygiene `Upgraded:` line keep it and append `, 2026-11-21`. Do not reflow code you do not touch; give each new idea its own lines with a `// ── Idea n: …` comment so the coordinator can point at it from the diff. `Features:` tags only if true per §8 (several JSONs/headers already over-claim — do not add more, and report over-claims you find).

## Coordinator's read of HEAD (starting points to VERIFY, not instructions — your Idea Card must come from your own reading)

**Finding 1 — `echo-trace` is dead at HEAD (needs a rescue before any idea).** Harness idle render (192², SRC=img, 60 frames, pointer up) gives `meanL 0.078, stdL 0.027, meanA 0.903` against a source of mean luma ~0.5: the photo is *gone* and the output is a dark violet plate with one blob at the pointer (`agents/mr.mjs … ` panel 1 of `/tmp/claude-0/-root-image-video-effects/ca8ee2a1-4d82-49d9-a35a-5be25191af56/scratchpad/co/head_echo-trace.png`). Cause (read the file to confirm): **A packing lie** — it stores covariance diagnostics `[pPos*300, pPos*300, pVel*45, pVel*45]` into `dataTextureA`, then reads `dataTextureC` as **colour history** (`color = mix(history.rgb, echo, …)`), so the "history" colour is a covariance field. Second: the Kalman state is kept in `extraBuffer[133..141]`, which Finding 2 shows is zeroed every frame, so `initialized` is always false, `updatedVel` is always 0 and `innovation` ≈ 0 → `residualMag` 0 → `predictedTrail` is `smoothstep(0.002,0.08,0)` = 0: the dashed predicted trails never draw. Decide the minimal truthful rescue (history colour in A.rgb like the file reads it; Kalman/pointer state where it can persist — see Finding 2) and report before/after numbers loudly. The identity to keep: a Kalman pointer estimator driving Mahalanobis-shaped dashed trails + held-brush tighten + click spark echoes over the photo.

**Finding 2 — `extraBuffer[133..255]` does NOT persist in the real engine.** `src/renderer/webgpu/audioDepth.ts` `writeExtraBuffer` does `device.queue.writeBuffer(extraBuf, 0, extraScratch)` with a full 256-float scratch every frame, so floats 133..255 are rewritten to 0 before every dispatch (222 catalog shaders use that range as "persistent" state; `WGSL_BUILTINS_GENERATIVE.md` still calls it safe — it is not). **The harness used to hide this** (it created `extraBuffer` once and never re-zeroed it); the coordinator has **patched `agents/mr.mjs`, `mr_perf.mjs`, `mr_ab.mjs`, `mr_c_abs.mjs`, `mr_box.mjs`, `mr_dots.mjs`** to re-zero `[133..255]` before every dispatch, matching the engine. Consequences you must check per file: `prismatic-feedback-loop` ("sprung held deformation", 133..136), `liquid-smear` ("spring-damper-pointer"/velocity smear, 133..136), `generative-psy-swirls` ("sprung-mouse-vortex", 133..138) and `echo-trace` (Kalman, 133..141) all keep a pointer spring / velocity there. In the real engine each of those reads `initialized == 0` and therefore gets *raw pointer, zero velocity*, every frame. Decide per file whether the spring is the effect's **identity** (liquid-smear's drag direction *is* pointer velocity; echo-trace *is* a velocity estimator) or garnish (psy-swirls, feedback-loop). Rules: (a) never write a new persistence scheme into `extraBuffer`; (b) where the pointer velocity IS the identity you may carry the minimal pointer state in the file's own `dataTextureA` — reserve **at most two texels** (e.g. `(0,0)` and `(1,0)`) written only by their own invocations, state it on the Idea Card as the A packing, make every consumer of C at those texels clamp/offset so no pixel of the picture reads state as colour — and report it as a **rescue**, not an idea; (c) where it is garnish, keep the code honest (drop the pretence, no half-dead spring) or leave it and say "dead in engine, left alone" — do not claim an idea that depends on a persisting spring; (d) the fix of `writeExtraBuffer` itself (write only `[0..132]`) is an **engine decision for the user, out of scope** — do not touch `src/`; mention it in your report.

**Finding 3 — the two "(Pass 2)" files.** `prismatic-3d-compositor` and `prismatic-feedback-loop` are named "Pass 2" in their definitions, so they may be placed after another effect; they must stay valid on any `readTexture` (do not assume a specific pass 1). Neither has a catalog pass-1 partner; verify before you rely on any claim.

**Finding 4 — triage numbers** (192², SRC=img, 60 frames, tEnd 3, mouse (0.5,0.5) up, audio 0.3/0.2/0.1, saved defaults; all compile, nan 0): rain meanL .49 stdL .172 meanA .042 · compositor .618/.258/.813 · feedback-loop .513/.173/1.0 · echo-trace .078/.027/.903 (**outlier**) · alucinate .566/.118/.839 · psy-swirls .14/.118/.16 (dark, mean alpha .16 — check whether that is the design or a defect) · liquid-smear .51/.17/.842.

## Cross-fork row claims (a §12.2 row / term appears on at most two files in this batch; §12.4 de-dup is enforced by the coordinator)

- Cauchy dispersion, energy-conserving bloom, soft inverse-square: **prismatic-3d-compositor** only.
- Snell vector refraction, Beer–Lambert absorption, Henyey–Greenstein: **rain** only.
- Isotropic 9-point Laplacian, orbit trap / fold-count material, smooth iteration: **alucinate** only.
- Semi-Lagrangian smudge / MacCormack, wet-edge accumulation, drying, speed-thinning: **liquid-smear** only (HEAD already has monotone reconstruction + edge-guided transport — build on them, don't replace).
- Schmitt-trigger lock / latched states: **echo-trace** only. Dwell pressure: echo-trace or liquid-smear, not both.
- Frame-hash strobing, generic spring/ripple overlays, IQ-palette stamping and holographic/neon costumes are rejected everywhere. The psychedelic pair (alucinate, psy-swirls) already *are* palette-led; ideas there must still be structure/motion, not a palette swap.
- Any row not listed: free, but if you pick one that another fork might also pick (vorticity, 9-pt Laplacian, thin-film, Fresnel), say so in your BRIEFS so the coordinator can de-dup.

## Per fork, in this order

1. Read each file + its JSON in full. Run HEAD first — find HEAD defects (blank / upside-down / dead sliders / wrong audio source / `pow` negative base / negative into ACES / illegal `textureStore` to read-only `dataTextureC` / `plasmaBuffer` never indexed / `ripples[i].w` always 0 / `fract(uv.x*resX)` dead masks / zero-C early return / `extraBuffer[0..132]` used as state / dead springs (Finding 2) / hardcoded alpha 1.0 where a semantic alpha is owed / over-claimed `features` tags) and fix them as **rescues**; list them. Fixes for defects may change the default look, but say so loudly in your report.
2. Write `BRIEFS-fork<X>.md` here: Idea Card per shader + §12.1 mechanism interrogation answers (tactics 1,2,3,6) + §12.4 formula admission — **before any WGSL edit**.
3. Implement 2 (max 3) native ideas per shader in the existing main path; `// ── Idea n: …` comment at each. Saved `params` byte-exact (ids, names, defaults, min/max, mapping order); no spring/ripple/IQ-palette overlay unless the file already owns the pointer/that look. Clamp before `aces()` (catalog ACES maps negatives to bright). No `fwidth`/`dpdx` in compute. State A/C packing truthfully on the card; raw-state A is not tone-mapped in storage, display-colour A is whatever the file already reads C as.
4. JSON: append to `description` only if visible behaviour changed; `features` tags only when true (§8); never touch `params`. `x-meta.upgrade.params` additive only.
5. Write `NOTES-fork<X>.md` per shader: Idea Card ADD list, KEEP VERBATIM, A packing, rescues, diff vs HEAD, timing, gates.

## Verify (VM = SwiftShader, no real GPU; do not claim visual QA)

- Render: `node agents/mr.mjs <wgsl> <out.png> [size] [frames] [tEnd] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]` (env: `SRC=img` for an image-like source, `SRCFLAT`, `SEEDC`, `MPATH='x0,y0,d0;x1,y1,d1'` for a moving pointer, `T0`, `A16`, `RIPPLES='x,y,t,0;…'`). **Always pass the saved defaults explicitly** — with no params the harness uses `1,1,1,1`, which is not the default look. Output panels: raw rgb | rgb over white by alpha | alpha. **The `RIPPLES` third value is a constant age in `mr.mjs`; use `agents/mr_c_abs.mjs` (absolute start time) when a click must age.** Scratch dir (use it, not /tmp): `/tmp/claude-0/-root-image-video-effects/ca8ee2a1-4d82-49d9-a35a-5be25191af56/scratchpad/<fork-letter-lowercase>/`. Look at the PNG (Read it) at defaults AND with params/mouse (a moving `MPATH` for pointer files)/clicks/audio exercised; check NaN count; check the picture isn't blank/saturated/uniform. For feedback/sim files render ≥ 60 frames.
- Time: `agents/mr_perf.mjs` and `agents/mr_ab.mjs <size> <cycles> <params> <mouse> <audio> <wgslHEAD> <wgslNEW>` (min-of-drained-frames, interleave HEAD/new, ≥4 rounds, median of per-round ratios). Four forks run at once on a loaded box, so single readings lie; the coordinator re-times borderline files on a quiet box. Cap **≤ ~1.3×** HEAD; trim (fewer taps / `select` instead of `if` / no per-sample accumulators) if over, and say so.
- Gates, each file: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`; `node scripts/verify-naga-wasm.mjs --files public/shaders/<id>.wgsl` (stricter than precommit; `demote` etc. are reserved); `python3 scripts/audit_dead_sliders.py --files <id>`; `python3 scripts/audit_extrabuffer.py`. If a file's JSON has only `updatedParams`, the dead-slider audit scans 0 defs — grep each slider read by hand.
- `pkill -f "[p]attern"` form only (a bare pattern kills your own shell) and ONLY patterns that name your own scratch files — other forks (and another session's Playwright job) are running at the same moment; never `pkill` by `node`/`chrom`.

## Do NOT

Commit, `git stash` (stash list is shared by every worktree), `git checkout`/`reset` anything, touch another fork's files, touch shared generated files (shader lists, search index, `reports/`, `src/` incl. `src/contracts/*`, ledger) — the coordinator runs `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`. Do not add new params or rename ids. Do not bump `Upgraded:` for a rescue-only/hygiene change. Work ONLY under `/root/iv-sonnet-batch-51` (the main checkout `/root/image_video_effects` is on another branch; `/root/iv-sonnet-batch-50` belongs to another live session — never edit either).

## Report back (final message, ≤ 25 lines)

Per shader: the ADD ideas (one line each, with formula row), rescues, A packing, diff-vs-HEAD pixel %, timing ratio, gate results (N/N), and anything you could not verify. Shell cwd may reset — use absolute paths under `/root/iv-sonnet-batch-51`.
