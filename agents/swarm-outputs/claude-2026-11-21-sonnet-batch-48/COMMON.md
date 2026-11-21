# COMMON — sonnet/batch-48 (user's line-count list: tone pair, focus pair, CRT/spectrum, datamosh/vortex, kaleido/topology, guided filter)

Worktree: `/root/iv-sonnet-batch-48` (branch `sonnet/batch-48`, from origin/main 2e876e2e). Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12 (the fork already has it in context). Notes dir: `agents/swarm-outputs/claude-2026-11-21-sonnet-batch-48/` (gitignored → coordinator uses `git add -f`).

**BASELINE ("HEAD") for every comparison = the worktree file as it stands when you start** — the coordinator already ran `migrate_to_prelude.py` on five of them (header-only infra, no `Upgraded:` bump; pixel output identical to origin/main). Your very first action: copy each of your files to the scratch dir as `<id>_head.wgsl` together with `public/shaders/_prelude.wgsl` (and `_std/` if you use it) *before editing*, then render/time against that copy. `#include` resolves relative to the wgsl's directory.

**ID → file map** (every id equals its file name):

| id | wgsl (public/shaders/) | definition json (shader_definitions/) | pass |
|---|---|---|---|
| tone-histogram | tone-histogram.wgsl | post-processing/tone-histogram.json | 2nd (has `Ideas:`) |
| tone-histogram-apply | tone-histogram-apply.wgsl | post-processing/tone-histogram-apply.json | 1st (no `Upgraded:`) |
| cyber-focus | cyber-focus.wgsl | interactive-mouse/cyber-focus.json | 1st |
| pixel-focus | pixel-focus.wgsl | interactive-mouse/pixel-focus.json | has `Upgraded: 2026-06-28` + `Optimized:` but NO `Ideas:` → creative first pass |
| scanline-cyberpunk | scanline-cyberpunk.wgsl | image/scanline-cyberpunk.json | 1st (only a "Batch 66 ACES + semantic alpha" hygiene header) |
| spectrum-bleed | spectrum-bleed.wgsl | retro-glitch/spectrum-bleed.json | 2nd |
| data-moshing-diffusion | data-moshing-diffusion.wgsl | retro-glitch/data-moshing-diffusion.json | 2nd |
| vortex-distortion | vortex-distortion.wgsl | distortion/vortex-distortion.json | 2nd |
| hyb-kaleidoscope-pulse | hyb-kaleidoscope-pulse.wgsl | hybrid/hyb-kaleidoscope-pulse.json | 1st (`upgraded-rgba` tag but no `Upgraded:`/`Ideas:`) |
| rgb-topology | rgb-topology.wgsl | visual-effects/rgb-topology.json | has `Upgraded: 2026-08-21` but NO `Ideas:` → creative first pass |
| conv-guided-video-filter | conv-guided-video-filter.wgsl | image/conv-guided-video-filter.json | 2nd |

**Header rules.** Second pass: the existing `Ideas:` entries are KEEP VERBATIM (read the line — it names what is already there); your new ideas are additional, native, must not duplicate an existing one; append `, 2026-11-21` to `Upgraded:` and append the new idea names (with §12.2 row names) to `Ideas:`. First / creative-first pass: add (or extend) `Upgraded: 2026-11-21`, `Ideas:`, `A packing:` lines in the standard banner; `Features:` tags only if true per §8. A file that already has an old `Upgraded:` date and no `Ideas:` line: append `, 2026-11-21` to the LATER `Upgraded:` line.

**Forks (disjoint files — forks cannot see each other, obey the claims below):**
- **A** tone-histogram, tone-histogram-apply (tone / exposure pair)
- **B** cyber-focus, pixel-focus (both pointer-owned focus apertures)
- **C** scanline-cyberpunk, spectrum-bleed (CRT scan / chromatic bleed)
- **D** data-moshing-diffusion, vortex-distortion (both keep raw field state in A)
- **E** hyb-kaleidoscope-pulse, rgb-topology (folded / contoured geometry)
- **F** conv-guided-video-filter (single file; guided-filter kernel)

**Known HEAD findings the coordinator already has (verify, then fix as rescues; say so loudly):**
1. `tone-histogram-apply` is an **orphan Pass 2**: its JSON says `prevShader: "tone-histogram"`, and it reads `extraBuffer[1]` (total), `extraBuffer[2]` (peak bin) and 256 bins at `extraBuffer[3..258]` — but `tone-histogram` was later rewritten as a *single-pass* v2 and no longer writes any histogram (its only `extraBuffer` mention is the binding). `src/renderer/multipassRegistry.ts` lists only `tone-histogram-apply` (pass 2, no pass-1 entry). So at HEAD the "histogram" is zeros/garbage: meanLuma clamps to 0.001 → exposure pinned at 3.5, p05/p95 degenerate → contrast ×63. Also `extraBuffer[0..132]` is re-uploaded every frame, so it is not a legal home for a cross-pass histogram anyway. Fork **A** must (a) grep `src/` (gpuChores, renderer, multipass) for anything that *does* write `extraBuffer[1..258]`, (b) render HEAD with image-like input to confirm, and (c) if nothing writes it, rescue by making Pass 2 self-contained *without changing what it is* (histogram → auto-exposure + percentile contrast + saturation + peak-bin hue shift): e.g. a `var<workgroup>` `atomic<u32>` 256-bin luma histogram filled by each workgroup from a stratified grid of `readTexture` samples across the **whole frame** (all 256 invocations cooperate, `workgroupBarrier()`), then the existing reduction. Saved `params` and their roles stay byte-exact. Keep it cheap (≤ ~1.3× HEAD cost is not the right cap here since HEAD is degenerate — state the cost and keep it modest). Decide the Idea Card from the *intended* mechanism.
2. `pixel-focus`, `rgb-topology` and others have header `Upgraded:` dates from hygiene sprints with no `Ideas:` line (see MEMORY: composer-batch files are not upgraded) — treat as creative first pass.

**Cross-fork row claims (a §12.2 row appears on at most one file in this batch unless stated; §12.4 de-dup rule is enforced by the coordinator):**
- Local-contrast normalization (Wallis, A2), H&D characteristic curve, density-weighted grain, photon shot noise, halation, CLAHE-style clip-limit / percentile-black-point ideas → fork **A** only (one file each).
- Block-DCT quantization → **cyber-focus** only. Cauchy dispersion, Brown–Conrady radial, CFA zipper → **pixel-focus** only.
- Sync-pulse timing, field interlace, dropout bursts, Schmitt-trigger lock (§12.2B) → **scanline-cyberpunk** only (≤2 of them). Chroma delay line (4:2:0) → **spectrum-bleed** only.
- Macroblock motion carry, isotropic 9-point Laplacian → **data-moshing-diffusion** only. Vorticity confinement, MacCormack advection → **vortex-distortion** only.
- Orbit trap, fold-count-as-material, golden-angle layout, additive domain twist → **hyb-kaleidoscope-pulse** only. **rgb-topology** picks contour / height-field-native ideas (e.g. iso-line widening by 1/|∇h|, relief from the field's own gradient, per-channel offset terrain physics) that no other fork uses; no SDF/raymarch costume.
- Structure-tensor orientation (A1), anti-halo envelope, guided-filter/bilateral rows → **conv-guided-video-filter** only.
- Frame-hash strobing, generic spring/ripple overlays and IQ palettes are rejected everywhere (pointer-owned files cyber-focus / pixel-focus / vortex-distortion / data-moshing-diffusion may use the pointer/spring they already own, not a new overlay).

**Per fork, in this order:**
1. Read the law doc sections you need (already in your context), then each file + its JSON in full. Run HEAD first — find HEAD defects (blank / upside-down / dead sliders / wrong audio source / `pow` negative base / negative into ACES / illegal textureStore to read-only dataTextureC / `plasmaBuffer` never indexed / `ripples[i].w` always 0 / `fract(uv.x*resX)` dead masks / zero-C early return / extraBuffer[0..132] used as state / hardcoded alpha 1.0 where a semantic alpha is owed) and fix them as **rescues**; list them. Fixes for defects are allowed even when they change the default look, but say so loudly in your report.
2. Write `BRIEFS-fork<X>.md` here: Idea Card per shader + §12.1 mechanism interrogation answers (tactics 1,2,3,6) + §12.4 formula admission — **before any WGSL edit**.
3. Implement 2 (max 3) native ideas per shader in the existing main path; `// ── Idea n: …` comment at each. Saved `params` byte-exact; no spring/ripple/IQ-palette overlay unless the file already owns the pointer/that look. Sim state lives in A/C textures — **never extraBuffer[0..132]** (extraBuffer is re-uploaded every frame; 133..138 is also zeroed per frame, so no state there either). Clamp before `aces()` (catalog ACES maps negatives to bright). No `fwidth`/`dpdx` in compute.
4. JSON: append to `description` only if the visible behaviour changed; `features` tags only when true (§8); never touch `params`. `x-meta.upgrade.params` additive only.
5. Write `NOTES-fork<X>.md` per shader: Idea Card ADD list, KEEP VERBATIM, A packing, rescues, diff vs HEAD, timing, gates.

**Verify (VM = SwiftShader, no real GPU; do not claim visual QA):**
- Render: `node agents/mr.mjs <wgsl> <out.png> [size] [frames] [tEnd] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]` (env: `SRC=img` for an image-like source, `SRCFLAT`, `SEEDC`, `MPATH`, `T0`, `A16`). Verified working in this worktree. Scratch dir (use it, not /tmp): `/tmp/claude-0/-root-image-video-effects/2b7775f4-9af2-40c8-a5e7-7ac04b08ac66/scratchpad/<fork-letter-lowercase>/`. Look at the PNG (Read it) at defaults AND with params/mouse/audio exercised; check the NaN count in the JSON it prints; check the picture isn't blank/saturated/uniform.
- Time: `agents/mr_perf.mjs` (min-of-drained-frames, interleave HEAD/new, ≥4 rounds, median of per-round ratios; the box is loaded so single readings lie). Cap **≤ ~1.3×** HEAD; trim (fewer taps / `select` instead of `if` / no per-sample accumulators) if over, and say so.
- Gates, each file: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`; `node scripts/verify-naga-wasm.mjs --files public/shaders/<id>.wgsl` (stricter than precommit; `demote` etc. are reserved); `python3 scripts/audit_dead_sliders.py --files <id>`; `python3 scripts/audit_extrabuffer.py`. If a file's JSON has only `updatedParams`, the dead-slider audit scans 0 defs — grep each slider read by hand.
- `pkill -f "[p]attern"` form only (a bare pattern kills your own shell).

**Do NOT:** commit, `git stash` (stash list is shared by every worktree), `git checkout`/`reset` anything, touch another fork's files, touch shared generated files (shader lists, search index, `reports/`, `src/contracts/*`, ledger) — the coordinator runs `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`. Do not add new params or rename ids. Do not bump `Upgraded:` for a rescue-only/hygiene change. Work ONLY under `/root/iv-sonnet-batch-48` (the main checkout `/root/image_video_effects` has unrelated uncommitted work — never edit it).

**Report back (final message, ≤ 25 lines):** per shader: the ADD ideas (one line each, with formula row), rescues, A packing, diff-vs-HEAD pixel %, timing ratio, gate results (N/N), and anything you could not verify. Shell cwd may reset — use absolute paths under `/root/iv-sonnet-batch-48`.
