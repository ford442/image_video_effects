# COMMON — sonnet/batch-47 (user's line-count list: chromatic split/swirl, temporal, strange-attractor/topological, voronoi, circuit, diffraction, brush)

Worktree: `/root/iv-sonnet-batch-47` (branch `sonnet/batch-47`, from origin/main 62680da7). HEAD = `git show origin/main:public/shaders/<id>.wgsl` for every comparison. Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12 (the fork already has it in context). Notes dir: `agents/swarm-outputs/claude-2026-11-20-sonnet-batch-47/` (gitignored → coordinator uses `git add -f`).

**ID → file map** (every id equals its file name):

| id | wgsl (public/shaders/) | definition json (shader_definitions/) |
|---|---|---|
| interactive-rgb-split | interactive-rgb-split.wgsl | distortion/interactive-rgb-split.json |
| chromatic-swirl | chromatic-swirl.wgsl | distortion/chromatic-swirl.json |
| gen-strange-field-flow | gen-strange-field-flow.wgsl | generative/gen-strange-field-flow.json |
| gen-topological-acoustic-knots | gen-topological-acoustic-knots.wgsl | generative/gen-topological-acoustic-knots.json |
| spec-temporal-path-tracer | spec-temporal-path-tracer.wgsl | advanced-hybrid/spec-temporal-path-tracer.json |
| gen-chrono-erosion-feedback-melting | gen-chrono-erosion-feedback-melting.wgsl | artistic/gen-chrono-erosion-feedback-melting.json |
| chronos-brush | chronos-brush.wgsl | interactive-mouse/chronos-brush.json |
| voronoi-zoom-turbulence | voronoi-zoom-turbulence.wgsl | geometric/voronoi-zoom-turbulence.json |
| hyb-chromatic-circuit | hyb-chromatic-circuit.wgsl | hybrid/hyb-chromatic-circuit.json |
| gen-rgb-diffraction | gen-rgb-diffraction.wgsl | generative/gen-rgb-diffraction.json |

**Pass status.** Coordinator already ran `migrate_to_prelude.py` (header-only infra, no `Upgraded:` bump) — all ten now `#include "_prelude.wgsl"`; the edited files in the worktree are therefore *already different from origin/main in the header only*. `spec-temporal-path-tracer` and `gen-chrono-erosion-feedback-melting` have **no `Upgraded:`/`Ideas:` line → first pass** (add the standard header lines: `Upgraded: 2026-11-20`, `Ideas:`, `A packing:`; `Features:` tags only if true per §8). The other **eight are second pass**: the existing `Ideas:` entries are KEEP VERBATIM (read the line, it names what is already there); your new ideas are additional, native, and must not duplicate an existing one; append `, 2026-11-20` to `Upgraded:` and append the new idea names (with §12.2 row names) to `Ideas:`.

**Forks (two files each — forks cannot see each other, obey the claims below):**
- **A** interactive-rgb-split, chromatic-swirl (both chromatic distortion; the two files must not share a formula row)
- **B** gen-strange-field-flow, gen-topological-acoustic-knots (both generative field/flow; no shared row)
- **C** spec-temporal-path-tracer, gen-chrono-erosion-feedback-melting (both temporal accumulation / feedback; no shared row)
- **D** chronos-brush, voronoi-zoom-turbulence
- **E** hyb-chromatic-circuit, gen-rgb-diffraction

**Cross-fork row claims.**
- Cauchy dispersion (§12.2F), Brown–Conrady radial (§12.2B), chroma delay line → fork **A** only (and at most one file each).
- Airy disc / diffraction-grating / thin-film / blaze rows → **gen-rgb-diffraction only**; hyb-chromatic-circuit must pick PCB / trace / circuit-native ideas (e.g. trace-width physics, via annular ring, solder-mask, skin-effect/current crowding, IR-drop tint) and **must not** use Cauchy or any lens-dispersion row.
- Orbit trap / smooth iteration / fold-count rows → fork **B** only. Temporal Monte-Carlo / TAA / variance-clamp / history-disocclusion rows → fork **C** only. Stroke-tangent / drying / dwell / wet-edge rows → **chronos-brush only**; voronoi-zoom-turbulence picks Worley/cell-native ideas (e.g. cell-wall relaxation, F1 gradient normal, Lloyd-style centroid drift, domain-warp of the point lattice) not used by anyone else.
- Frame-hash strobing, generic spring/ripple overlays and IQ palettes are rejected everywhere.

**Per fork, in this order:**
1. Read the law doc sections you need (already in your context), then each file + its JSON in full. Run HEAD first (see Verify) — find HEAD defects (blank / upside-down / dead sliders / wrong audio source / `pow` negative base / negative into ACES / illegal textureStore to read-only dataTextureC / `plasmaBuffer` never indexed / `ripples[i].w` always 0 / `fract(uv.x*resX)` dead masks / zero-C early return / extraBuffer[0..132] used as state) and fix them as **rescues**; list them. Fixes for defects are allowed even when they change the default look, but say so loudly in your report.
2. Write `BRIEFS-fork<X>.md` here: Idea Card per shader + §12.1 mechanism interrogation answers (tactics 1,2,3,6) + §12.4 formula admission — **before any WGSL edit**.
3. Implement 2 (max 3) native ideas per shader in the existing main path; `// ── Idea n: …` comment at each. Saved `params` byte-exact; no spring/ripple/IQ-palette overlay unless the file already owns the pointer/that look. Sim state lives in A/C textures — **never extraBuffer[0..132]** (extraBuffer is re-uploaded every frame; 133..138 is also zeroed per frame, so no state there either).
4. JSON: append to `description` only if the visible behaviour changed; `features` tags only when true (§8); never touch `params`. `x-meta.upgrade.params` additive only.
5. Write `NOTES-fork<X>.md` per shader: Idea Card ADD list, KEEP VERBATIM, A packing, rescues, diff vs HEAD, timing, gates.

**Verify (VM = SwiftShader, no real GPU; do not claim visual QA):**
- Render: `node agents/mr.mjs <wgsl> <out.png> [size] [frames] [tEnd] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]` (env: `SRC=img` for an image-like source, `SRCFLAT`, `SEEDC`, `MPATH`, `T0`, `A16`). `#include` resolves relative to the wgsl's directory, so to render HEAD copy it **plus** `_prelude.wgsl` (and `_std/` if used) into a scratch dir under the scratchpad (`/tmp/claude-0/-root-image-video-effects/0cb7fcb4-a909-48c6-8c65-36fcc249f77c/scratchpad/<fork-letter>/`). Look at the PNG (Read it) at defaults AND with params/mouse/audio exercised; check NaN count in the JSON it prints; check the picture isn't blank/saturated/uniform.
- Time: `agents/mr_perf.mjs` (min-of-drained-frames, interleave HEAD/new, ≥4 rounds, median of per-round ratios; the box is loaded so single readings lie). Cap **≤ ~1.3×** HEAD; trim (fewer taps / `select` instead of `if` / no per-sample accumulators) if over, and say so.
- Gates, each file: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`; `node scripts/verify-naga-wasm.mjs --files public/shaders/<id>.wgsl` (stricter than precommit; `demote` etc. are reserved); `python3 scripts/audit_dead_sliders.py --files <id>`; `python3 scripts/audit_extrabuffer.py`. If a file's JSON has only `updatedParams`, the dead-slider audit scans 0 defs — grep each slider read by hand.
- `pkill -f "[p]attern"` form only (a bare pattern kills your own shell).

**Do NOT:** commit, `git stash` (stash list is shared by every worktree), `git checkout`/`reset` anything, touch another fork's files, touch shared generated files (shader lists, search index, `reports/`, `src/contracts/*`, ledger) — the coordinator runs `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`. Do not add new params or rename ids. Do not bump `Upgraded:` for a rescue-only/hygiene change. Work ONLY under `/root/iv-sonnet-batch-47` (the main checkout `/root/image_video_effects` has unrelated uncommitted work — never edit it).

**Report back (final message, ≤ 25 lines):** per shader: the ADD ideas (one line each, with formula row), rescues, A packing, diff-vs-HEAD pixel %, timing ratio, gate results (N/N), and anything you could not verify. Shell cwd may reset — use absolute paths under `/root/iv-sonnet-batch-47`.
