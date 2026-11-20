# COMMON — sonnet/batch-46 (user's line-count list: gravitational lens / flow / dispersion)

Worktree: `/root/iv-sonnet-batch-46` (branch `sonnet/batch-46`, from origin/main 673d780a). HEAD = `git show origin/main:public/shaders/<id>.wgsl` for every comparison. Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12 (the fork already has it in context). Notes dir: `agents/swarm-outputs/claude-2026-11-20-sonnet-batch-46/` (gitignored → coordinator uses `git add -f`).

**ID → file map** (every id equals its file name):

| id | wgsl (public/shaders/) | definition json (shader_definitions/) |
|---|---|---|
| gravitational-lensing-nlm | gravitational-lensing-nlm.wgsl | advanced-hybrid/gravitational-lensing-nlm.json |
| distortion-gravitational-prismatic | distortion-gravitational-prismatic.wgsl | advanced-hybrid/distortion-gravitational-prismatic.json |
| distortion_gravitational_lens | distortion_gravitational_lens.wgsl | artistic/distortion_gravitational_lens.json |
| kinetic-dispersion | kinetic-dispersion.wgsl | interactive-mouse/kinetic-dispersion.json |
| ethereal-swirl-coupled | ethereal-swirl-coupled.wgsl | advanced-hybrid/ethereal-swirl-coupled.json |
| hybrid-chromatic-liquid | hybrid-chromatic-liquid.wgsl | hybrid/hybrid-chromatic-liquid.json |
| conv-structure-tensor-flow | conv-structure-tensor-flow.wgsl | image/conv-structure-tensor-flow.json |
| optical-flow-tracer | optical-flow-tracer.wgsl | post-processing/optical-flow-tracer.json |
| cosmic-flow | cosmic-flow.wgsl | artistic/cosmic-flow.json |
| gen-raptor-mini-flow | gen-raptor-mini-flow.wgsl | advanced-hybrid/gen-raptor-mini-flow.json |

**Pass status.** Coordinator already ran `migrate_to_prelude.py` (header-only infra, no `Upgraded:` bump) on the 8 files that pasted bindings; the other two already include `_prelude.wgsl`. `conv-structure-tensor-flow` (Ideas: minor-eigenvector LIC; source-luma tint) and `optical-flow-tracer` (Ideas: Shi-Tomasi confidence; pyramidal coarse-to-fine Lucas-Kanade) are **second pass**: earlier ideas are KEEP VERBATIM; new ideas are additional and native; append `, 2026-11-20` to `Upgraded:` and append new idea names (with §12.2 row names) to `Ideas:`. The other eight have **no `Ideas:` line → first pass** (add `Upgraded: 2026-11-20` + `Ideas:` + `A packing:` lines; `kinetic-dispersion` already has `Upgraded: 2026-05-31` → append the date: `Upgraded: 2026-05-31, 2026-11-20`).

**Forks (two files each):**
- **A** gravitational-lensing-nlm, distortion-gravitational-prismatic
- **B** distortion_gravitational_lens, kinetic-dispersion
- **C** ethereal-swirl-coupled, hybrid-chromatic-liquid
- **D** conv-structure-tensor-flow, optical-flow-tracer
- **E** cosmic-flow, gen-raptor-mini-flow

**Cross-fork de-dup (forks cannot see each other — obey these claims).** Three files are gravitational lenses (nlm, prismatic, lens): no formula row may be shared across them. Reserved rows: **Cauchy dispersion (§12.2F) → distortion-gravitational-prismatic ONLY**; **non-local-means / patch-similarity kernel deepening → gravitational-lensing-nlm ONLY**; distortion_gravitational_lens must pick lens-physics rows that are neither of those (e.g. soft inverse-square, Einstein-ring magnification / convergence-shear, energy-conserving brightness) and kinetic-dispersion must not use Cauchy dispersion (use pointer-kinematics rows from §12.2C if the file owns the pointer). Fork D: structure-tensor row on conv-structure-tensor-flow only; optical-flow-tracer picks flow/temporal rows. Fork C: ethereal-swirl-coupled and hybrid-chromatic-liquid must not share a row.

**Per fork, in this order:**
1. Read the law doc sections you need, then each file + its JSON in full. Run HEAD first (see Verify) — find HEAD defects (blank / upside-down / dead sliders / wrong audio source / `pow` negative base / negative into ACES / illegal textureStore to read-only dataTextureC / `plasmaBuffer` never indexed / `ripples[i].w` always 0 / `fract(uv.x*resX)` dead masks / zero-C early return) and fix them as **rescues**; list them.
2. Write `BRIEFS-fork<X>.md` here: Idea Card per shader + §12.1 mechanism interrogation answers (tactics 1,2,3,6) + §12.4 formula admission — **before any WGSL edit**.
3. Implement 2 (max 3) native ideas per shader in the existing main path; `// ── Idea n: …` comment at each. Saved `params` byte-exact; no spring/ripple/IQ-palette overlay unless the file already owns the pointer/that look. Sim state lives in A/C textures — **never extraBuffer[0..132]** (extraBuffer is re-uploaded every frame; 133..138 is also zeroed per frame, so no state there either).
4. JSON: append to `description` only if the visible behaviour changed; `features` tags only when true (§8); never touch `params`. `x-meta.upgrade.params` additive only.
5. Write `NOTES-fork<X>.md` per shader: Idea Card ADD list, KEEP VERBATIM, A packing, rescues, diff vs HEAD, timing, gates.

**Verify (VM = SwiftShader, no real GPU; do not claim visual QA):**
- Render: `node agents/mr.mjs <wgsl> <out.png> [size] [frames] [tEnd] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]` (env: `SRC=img` for an image-like source, `SRCFLAT`, `SEEDC`, `MPATH`, `T0`, `A16`). `#include` resolves relative to the wgsl's directory, so to render HEAD copy it **plus** `_prelude.wgsl` (and `_std/` if used) into a scratch dir under the scratchpad (`/tmp/claude-0/-root-image-video-effects/bd0d6c66-96e3-4dcc-84fd-ec19638d2915/scratchpad/`). Look at the PNG (Read it) at defaults AND with params/mouse/audio exercised; check NaN count in the JSON it prints; check the picture isn't blank/saturated/uniform.
- Time: `agents/mr_perf.mjs` (min-of-drained-frames, interleave HEAD/new, ≥4 rounds, median of per-round ratios; load on the box is high so single readings lie). Cap **≤ ~1.3×** HEAD; trim (fewer taps / `select` instead of `if` / no per-sample accumulators) if over, and say so.
- Gates, each file: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`; `node scripts/verify-naga-wasm.mjs --files public/shaders/<id>.wgsl` (stricter than precommit; `demote` etc. are reserved); `python3 scripts/audit_dead_sliders.py --files <id>`; `python3 scripts/audit_extrabuffer.py`. If a file's JSON has only `updatedParams`, the dead-slider audit scans 0 defs — grep each slider read by hand.
- `pkill -f "[p]attern"` form only (a bare pattern kills your own shell).

**Do NOT:** commit, `git stash` (stash list is shared by every worktree), `git checkout`/`reset` anything, touch another fork's files, touch shared generated files (shader lists, search index, `reports/`, `src/contracts/*`, ledger) — the coordinator runs `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`. Do not add new params or rename ids. Do not bump `Upgraded:` for a rescue-only/hygiene change.

**Report back (final message, ≤ 25 lines):** per shader: the ADD ideas (one line each, with formula row), rescues, A packing, diff-vs-HEAD pixel %, timing ratio, gate results (N/N), and anything you could not verify. Shell cwd may reset — use absolute paths under `/root/iv-sonnet-batch-46`.
