# COMMON — sonnet/batch-45 (user's line-count list: conv / retro / sim / weather)

Worktree: `/root/iv-sonnet-batch-45` (branch `sonnet/batch-45`, from origin/main 8c537fe6). HEAD = `git show origin/main:public/shaders/<id>.wgsl` for every comparison. Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12 (the fork already has it in context). Notes dir: `agents/swarm-outputs/claude-2026-11-19-sonnet-batch-45/` (gitignored → coordinator uses `git add -f`).

**ID → file map** (the user's list uses catalog ids; `galaxy-sim` is `public/shaders/galaxy.wgsl`):

| id | wgsl | definition json |
|---|---|---|
| conv-steerable-pyramid | public/shaders/conv-steerable-pyramid.wgsl | shader_definitions/image/conv-steerable-pyramid.json |
| conv-anisotropic-diffusion | …/conv-anisotropic-diffusion.wgsl | shader_definitions/image/conv-anisotropic-diffusion.json |
| conv-fractal-kernel | …/conv-fractal-kernel.wgsl | shader_definitions/image/conv-fractal-kernel.json |
| data-moshing | …/data-moshing.wgsl | shader_definitions/retro-glitch/data-moshing.json |
| crt-phosphor-decay | …/crt-phosphor-decay.wgsl | shader_definitions/retro-glitch/crt-phosphor-decay.json |
| rgb-glitch-trail | …/rgb-glitch-trail.wgsl | shader_definitions/retro-glitch/rgb-glitch-trail.json |
| galaxy-sim | …/galaxy.wgsl | shader_definitions/artistic/galaxy-sim.json |
| lenia | …/lenia.wgsl | shader_definitions/artistic/lenia.json |
| snow | …/snow.wgsl | shader_definitions/artistic/snow.json |
| luminance-wind | …/luminance-wind.wgsl | shader_definitions/artistic/luminance-wind.json |

**Pass status.** Coordinator already ran `migrate_to_prelude.py` (header-only infra, no `Upgraded:` bump) on galaxy, snow, luminance-wind. `lenia` and `galaxy` have **no `Ideas:` line → first pass** (add `Upgraded: 2026-11-19` + `Ideas:` + `A packing:` lines; if an older `Upgraded:` exists, append the date). The other eight ALREADY carry `Ideas:` (second pass): new ideas must be **additional** and native; the earlier ideas and everything on their `Ideas:` line are KEEP VERBATIM. Append `, 2026-11-19` to `Upgraded:` and append the new idea names (with §12.2 row names) to `Ideas:`.

**Forks (two files each):**
- **A** conv-steerable-pyramid, conv-anisotropic-diffusion
- **B** conv-fractal-kernel, data-moshing
- **C** crt-phosphor-decay, rgb-glitch-trail
- **D** galaxy-sim (galaxy.wgsl), lenia
- **E** snow, luminance-wind

Fork A: both are orientation/gradient-driven image kernels — give them DIFFERENT §12.2 rows (the structure-tensor row may land on at most one). Fork C: both are retro-glitch; do not give both the same latch/chroma-delay formula.

**Per fork, in this order:**
1. Read the law doc sections you need, then each file + its JSON in full. Run HEAD first (see Verify) — find HEAD defects (blank / upside-down / dead sliders / wrong audio source / `pow` negative base / negative into ACES / illegal textureStore to read-only dataTextureC / `plasmaBuffer` never indexed) and fix them as **rescues**; list them.
2. Write `BRIEFS-fork<X>.md` here: Idea Card per shader + §12.1 mechanism interrogation answers (tactics 1,2,3,6) + §12.4 formula admission — **before any WGSL edit**.
3. Implement 2 (max 3) native ideas per shader in the existing main path; `// ── Idea n: …` comment at each. Saved `params` byte-exact; no spring/ripple/IQ-palette overlay unless the file already owns the pointer/that look. Sim state lives in A/C textures — **never extraBuffer[0..132]** (extraBuffer is re-uploaded every frame; 133..138 is also zeroed per frame, so no state there either).
4. JSON: append to `description` only if the visible behaviour changed; `features` tags only when true (§8); never touch `params`. `x-meta.upgrade.params` additive only.
5. Write `NOTES-fork<X>.md` per shader (same shape as batch-44 notes): Idea Card ADD list, KEEP VERBATIM, A packing, rescues, diff vs HEAD, timing, gates.

**Verify (VM = SwiftShader, no real GPU; do not claim visual QA):**
- Render: `node agents/mr.mjs <wgsl> <out.png> [size] [frames] [tEnd] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]` (env: `SRC=img` for an image-like source, `SRCFLAT`, `SEEDC`, `MPATH`, `T0`, `A16`). `#include` resolves relative to the wgsl's directory, so to render HEAD copy it **plus** `_prelude.wgsl` (and `_std/` if used) into a scratch dir under the scratchpad. Look at the PNG (Read it) at defaults AND with params/mouse/audio exercised; check NaN count in the JSON it prints; check the picture isn't blank/saturated/uniform.
- Time: `agents/mr_perf.mjs` (min-of-drained-frames, interleave HEAD/new, ≥4 rounds, median of per-round ratios; load on the box is high so single readings lie). Cap **≤ ~1.3×** HEAD; trim (fewer taps / `select` instead of `if` / no per-sample accumulators) if over, and say so.
- Gates, each file: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`; `node scripts/verify-naga-wasm.mjs --files public/shaders/<id>.wgsl` (stricter than precommit; `demote` etc. are reserved); `python3 scripts/audit_dead_sliders.py --files <id>`; `python3 scripts/audit_extrabuffer.py`. If a file's JSON has only `updatedParams`, the dead-slider audit scans 0 defs — grep each slider read by hand.
- `pkill -f "[p]attern"` form only (a bare pattern kills your own shell).

**Do NOT:** commit, `git stash` (stash list is shared by every worktree), `git checkout`/`reset` anything, touch another fork's files, touch shared generated files (shader lists, search index, `reports/`, `src/contracts/*`, ledger) — the coordinator runs `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`. Do not add new params or rename ids. Do not bump `Upgraded:` for a rescue-only/hygiene change.

**Report back (final message, ≤ 25 lines):** per shader: the ADD ideas (one line each, with formula row), rescues, A packing, diff-vs-HEAD pixel %, timing ratio, gate results (N/N), and anything you could not verify. Shell cwd may reset — use absolute paths under `/root/iv-sonnet-batch-45`.
