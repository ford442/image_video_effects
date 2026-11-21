# COMMON — sonnet/batch-50 (user's line-count list: ten generative ~310-330-line files)

Worktree: `/root/iv-sonnet-batch-50` (branch `sonnet/batch-50`, from origin/main 49395199). Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12 (a fork already has it in context). Notes dir: `agents/swarm-outputs/claude-2026-11-21-sonnet-batch-50/` (gitignored → coordinator uses `git add -f`).

**BASELINE ("HEAD") for every comparison = the worktree file as it stands when you start.** The coordinator already ran `migrate_to_prelude.py` on eight files (header-only infra, no `Upgraded:` bump; pixel output identical to origin/main). `gen-neuro-cosmos` already used the prelude. `gen-symbiotic-bismuth-crystal-dragon-core` was REFUSED by the codemod (see its rescue below). Your very first action: copy each of your files to your scratch dir as `<id>_head.wgsl` together with `public/shaders/_prelude.wgsl` (and `_std/` if you use it) *before editing*, then render/time against that copy. `#include` resolves relative to the wgsl's directory.

**ID → file map** (note kimi):

| id | wgsl (public/shaders/) | definition json (shader_definitions/generative/) | pass |
|---|---|---|---|
| gen-neuro-cosmos | gen-neuro-cosmos.wgsl | gen-neuro-cosmos.json | 2nd+ (`Ideas:` = saltatory conduction, integrate-and-fire soma, activity-dependent pruning, Hebbian corridors → KEEP VERBATIM) |
| cosmic-web | cosmic-web.wgsl | cosmic-web.json | 1st creative pass (only a "Batch 17" hygiene comment; no `Ideas:` line) |
| gen-alpha-aurora | gen-alpha-aurora.wgsl | gen-alpha-aurora.json | 2nd+ (`Ideas:` = curtain rays along the curl; greener lower border) |
| aurora-borealis-loom | aurora-borealis-loom.wgsl | aurora-borealis-loom.json | 2nd (`Ideas:` = fell line + reed beat-up; slub yarn light pools; pulsating aurora patches) |
| gen-symbiotic-light-networks | gen-symbiotic-light-networks.wgsl | gen-symbiotic-light-networks.json (no params) | 2nd (hub-thickened Physarum tubes; evanescent leakage halo; mycorrhizal colour exchange; luciferin afterglow) |
| gen-kimi-nebula | **gen_kimi_nebula.wgsl** (underscores!) | gen-kimi-nebula.json | 2nd (Stromgren ionization stratification; dust lanes + photoevaporated rims; PDR skin; EGG tails — already huge) |
| gen-symbiotic-bismuth-crystal-dragon-core | gen-symbiotic-bismuth-crystal-dragon-core.wgsl | gen-symbiotic-bismuth-crystal-dragon-core.json | 2nd (ichor seep; peristaltic ...) |
| gen-quantum-chrome-serpent-ouroboros | gen-quantum-chrome-serpent-ouroboros.wgsl | gen-quantum-chrome-serpent-ouroboros.json (no params) | 2nd (quantum dispersion trails; audio chromatic reflection aberration) |
| gen-radiant-cyber-plasma-astro-griffin | gen-radiant-cyber-plasma-astro-griffin.wgsl | gen-radiant-cyber-plasma-astro-griffin.json | 2nd (primary-feather slots; beak shear glint; flap ghost) |
| gen-inverse-mandelbrot | gen-inverse-mandelbrot.wgsl | gen-inverse-mandelbrot.json (no params) | 2nd (Pickover stalks on the colour-space orbit; arg(final_z) bands) |

**Forks (disjoint files — forks cannot see each other; obey the claims below):**
- **A** gen-alpha-aurora, aurora-borealis-loom (aurora pair)
- **B** gen-neuro-cosmos, cosmic-web (web/filament pair)
- **C** gen-symbiotic-light-networks, gen-kimi-nebula (volumetric organic-light / gas pair)
- **D** gen-symbiotic-bismuth-crystal-dragon-core, gen-quantum-chrome-serpent-ouroboros (raymarched chrome/crystal pair)
- **E** gen-radiant-cyber-plasma-astro-griffin, gen-inverse-mandelbrot

**Header rules.** Nine files are *later passes*: keep the existing `Ideas:` items, append `, 2026-11-21` to `Upgraded:` and append the NEW idea names (with §12.2 row names where a row was used) to `Ideas:` (the line may be long; keep it one comment line). `cosmic-web` is a first creative pass: write the standard banner (title, Category, Features, Complexity, Upgraded: 2026-11-21, Ideas:, A packing:) and keep its existing descriptive comment lines. Most files are dense one-line statements: **do not reflow code you do not touch**; give each new idea its own lines with a `// ── Idea n: …` comment. `Features:` tags only if true per §8. Because these are SECOND+ passes, a new idea must be NEW: read the existing `Ideas:` line and the code first, do not re-add what is there, and do not remove or weaken a shipped idea (KEEP VERBATIM = every item already on the `Ideas:` line).

## Coordinator's read of HEAD (starting points to VERIFY, not instructions — your Idea Card must come from your own reading)

Renders at 256 px, 40 frames, tEnd 4 s, saved JSON defaults, mouse 0.5,0.5 up, audio 0.3,0.2,0.1, no source image. PNG = raw rgb | composite over white | alpha. HEAD stats (nan always 0 except cosmic-web, which does not compile):

| id | meanL | stdL | meanA | frameMs @256 (SwiftShader, 5 parallel) |
|---|---|---|---|---|
| gen-neuro-cosmos | 0.304 | 0.057 | 0.922 | 428 |
| gen-alpha-aurora | 0.175 | 0.222 | 0.145 | 1140 |
| gen-symbiotic-bismuth-crystal-dragon-core | 0.586 | 0.119 | 0.961 | 292 |
| gen-quantum-chrome-serpent-ouroboros | **0.070** | **0.024** | 0.950 | 179 |
| gen-symbiotic-light-networks | 0.098 | 0.147 | 0.494 | 1299 |
| aurora-borealis-loom | **0.740** | 0.027 | **0.122** | 99 |
| cosmic-web | — (COMPILE ERROR) | | | |
| gen-radiant-cyber-plasma-astro-griffin | 0.352 | 0.188 | 0.418 | 221 |
| gen-inverse-mandelbrot | 0.571 | 0.077 | 0.551 | 287 |
| gen_kimi_nebula | 0.558 | 0.087 | 0.373 | 145 |

**Finding 1 — `cosmic-web` does not compile in a real WebGPU engine.** It declares `let __finalRGB = …` (twice, lines ~294 and ~314 of the original). WGSL forbids identifiers that start with two underscores (SwiftShader/Dawn error: `identifiers must not start with two or more underscores`). The id is in `src/contracts/wgsl_validation.json` `knownFailures.ids` — the coordinator's `verify:shaders:fix` removes it once it is naga-clean. Also check why `textureStore(writeTexture, …)` appears twice (there may be a duplicated tail / two return paths) and what HEAD would draw once compiling; this is a rescue: report it loudly, with a before/after picture (HEAD cannot render at all, so "before" = fix only the identifier in a scratch copy and render that).

**Finding 2 — `gen-symbiotic-bismuth-crystal-dragon-core` has a wrong `Uniforms` field order.** It pastes `config, zoom_params, zoom_config, ripples` but the engine layout (prelude, `docs/BINDING_CONTRACT.md`) is `config, zoom_config, zoom_params, ripples`. So at HEAD `u.zoom_params` actually reads the engine's `zoom_config` (x = time seconds, yz = mouse, w = mouse_down) and `u.zoom_config.yz` reads slider 2/3. Net: zoom_level = time (grows without bound), `complexity` = mouse x, `breathing_speed` = mouse y, `iridescence_shift` = mouse_down, and "mouse_uv" = sliders p2/p3 — all four sliders are dead and the mouse is mis-routed. The migration codemod refuses to fix it because it changes rendering. Fix = replace the pasted header + struct with `#include "_prelude.wgsl"` BY HAND (this is the rescue; say so loudly; the default picture WILL change — the saved defaults 1.0/3.0/0.5/0.0 were never actually applied). Verify first by rendering HEAD with different slider values and seeing no change.

**Finding 3 — near-black / near-white defaults.** `gen-quantum-chrome-serpent-ouroboros` (meanL 0.07, stdL 0.024) is almost an empty frame at default and its JSON has no params: find out whether that is the audio-gated scene, a sun/lighting that is too dark, a camera inside geometry, or a dead term. `aurora-borealis-loom` is pale grey (meanL 0.74, stdL 0.027, alpha 0.12) with a few vertical lines at default — it is a feedback shader; check whether it relies on `readTexture` (the harness feeds none unless `SRC=img`), whether the zero-C early return pattern applies (see memory `project_zero_c_early_return`: feedback shaders that need C ≈ 0 to start never start), and render with `SRC=img` too before judging. `gen-alpha-aurora`, `gen-symbiotic-light-networks` are 1.1-1.3 s/frame at 256 on SwiftShader (5 parallel) — they have little cost headroom; the 1.3× cap applies. `gen-neuro-cosmos` looks like teal curtains, not a neural web at default — verify the picture is what its description says.

**Finding 4 — params.** `gen-quantum-chrome-serpent-ouroboros`, `gen-symbiotic-light-networks`, `gen-inverse-mandelbrot` have `params: []` in JSON (updatedParams-only or none): the dead-slider audit may scan 0 defs; grep `zoom_params` by hand. Do not add params. Check whether any of these read `zoom_params` at all and which `mouse`/audio they actually use (audio = `plasmaBuffer[0].xyz`; never `config.y`/`zoom_config.x`).

## Cross-fork §12.2 row ownership (a row appears on at most two files in the batch; coordinator enforces §12.4 de-dup)

Use only rows you own below, or ideas that are NOT §12.2 rows (domain-native mechanisms from §12.1 — an aurora's emission-altitude layering, a neuron's refractory period, a sunk-cost tapestry's warp tension — need no ownership and are the better ideas). A row you do not own may not be used.

- **Orbit trap, smooth iteration count**: gen-inverse-mandelbrot only (HEAD has Pickover stalks = already a trap; add smoothing / a different trap shape only if it is a genuinely new look; do not duplicate the stalks).
- **Fold count as material, SDF curvature, over-relaxed sphere tracing**: gen-symbiotic-bismuth-crystal-dragon-core only.
- **Step-count AO**: gen-quantum-chrome-serpent-ouroboros, gen-radiant-cyber-plasma-astro-griffin.
- **Additive domain twist, Cauchy dispersion, Fresnel–Schlick**: gen-quantum-chrome-serpent-ouroboros (Fresnel also gen-symbiotic-bismuth-crystal-dragon-core).
- **Golden-angle layout**: cosmic-web only.
- **Beer–Lambert (airmass / depth absorption)**: gen-alpha-aurora only.
- **Soft inverse-square**: gen-neuro-cosmos only. **Energy-conserving bloom**: gen-symbiotic-light-networks only.
- **Rayleigh / blackbody, Airy disc**: gen_kimi_nebula only (blackbody star colour from temperature / diffraction spikes on the bright stars it already draws).
- **Henyey–Greenstein, thin-film, Snell, lens-flare ghosts, vorticity confinement, curl-noise warp**: nobody (unless it is already at HEAD in your file — keep, do not extend).
- Frame-hash strobing, generic spring/ripple overlays, IQ cosine palettes bolted on as the whole look and `fwidth` are rejected everywhere. Pointer-owned files (all ten claim `mouse-driven` or similar; check the code) may use the pointer/clicks they already own, not a new overlay. **No new springs in `extraBuffer`** (extraBuffer[133..255] is zeroed per frame, so no state there; never `[0..132]`).

## Per fork, in this order

1. Read each file + its JSON in full. Run HEAD first — find HEAD defects (blank / upside-down / dead sliders / wrong audio source / `pow` negative base / negative into ACES / illegal `textureStore` to read-only `dataTextureC` / `plasmaBuffer` never indexed / `ripples[i].w` always 0 / `fract(uv.x*resX)` dead masks / zero-C early return / `extraBuffer[0..132]` used as state / hardcoded alpha 1.0 where a semantic alpha is owed / camera inside geometry / ray starts inside SDF / mirrored y) and fix them as **rescues**; list them. Fixes for defects may change the default look, but say so loudly in your report.
2. Write `BRIEFS-fork<X>.md` here: Idea Card per shader + §12.1 mechanism interrogation answers (tactics 1,2,3,6) + §12.4 formula admission — **before any WGSL edit**. The ideas must be NEW relative to the existing `Ideas:` line.
3. Implement 2 (max 3) native ideas per shader in the existing main path; `// ── Idea n: …` comment at each. Saved `params` byte-exact (ids, names, defaults, min/max, mapping order); no spring/ripple/IQ-palette overlay unless the file already owns it. Sim/feedback state lives in A/C textures — keep each file's existing A packing and SAY SO on the card (read how C is read back; raw-state A is not tone-mapped in storage, ACES only on `writeTexture`; display-RGBA A stays display). Clamp before `aces()` (catalog ACES maps negatives to bright). No `fwidth`/`dpdx` in compute.
4. JSON: append to `description` only if the visible behaviour changed; `features` tags only when true (§8); never touch `params`. `x-meta.upgrade.params` additive only.
5. Write `NOTES-fork<X>.md` per shader: Idea Card ADD list, KEEP VERBATIM, A packing, rescues, diff vs HEAD, timing, gates.

## Verify (VM = SwiftShader, no real GPU; do not claim visual QA)

- Render: `node agents/mr.mjs <wgsl> <out.png> [size] [frames] [tEnd] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]` (env: `SRC=img` for an image-like source, `SRCFLAT`, `SEEDC`, `MPATH`, `T0`, `A16`, `RIPPLES='x,y,t_start_abs,0;…'`; the stock harness treats the 3rd RIPPLES value as a constant age — use `agents/mr_c_abs.mjs` for an absolute start time). **The harness defaults sliders to 1,1,1,1: always pass the JSON defaults explicitly** (they are in the table in your brief). Scratch dir (use it, not /tmp): `/tmp/claude-0/-root-image-video-effects/12631154-16b4-44ad-a621-195684eec032/scratchpad/<fork-letter-lowercase>/` (the coordinator's HEAD renders of all ten are in `.../scratchpad/c/head_<file>.png`, do NOT write there). Look at the PNG (Read it) at defaults AND with params/mouse/clicks/audio exercised, at ≥2 times (t ≈ 2 and ≈ 20 for temporal ones), and with an image source (`SRC=img`) where the file reads `readTexture`; check the NaN count in the JSON it prints; check the picture is not blank / saturated / uniform. For feedback/sim state render ≥ 60 frames.
- Time: `agents/mr_ab.mjs <size> <cycles> <params> <mouse> <audio> <wgslHEAD> <wgslNEW>` (interleaved, min/median; ≥4 rounds; ratio of medians). The box is shared with four other forks, so single readings lie; the coordinator re-times borderline files on a quiet box. Cap **≤ ~1.3×** HEAD; trim (fewer taps / `select` instead of `if` / no per-sample accumulators) if over, and say so.
- Gates, each file: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<file>.wgsl`; `node scripts/verify-naga-wasm.mjs --files public/shaders/<file>.wgsl` (stricter than precommit; `demote`/`target`/`__x` etc. are reserved); `python3 scripts/audit_dead_sliders.py --files <id>`; `python3 scripts/audit_extrabuffer.py`. If a file's JSON has only `updatedParams` or no params, the dead-slider audit scans 0 defs — grep each slider read by hand.
- `pkill -f "[p]attern"` form only (a bare pattern kills your own shell) and ONLY patterns that name your own scratch files — other forks are timing at the same moment.

## Do NOT

Commit, `git stash` (stash list is shared by every worktree), `git checkout`/`reset` anything, touch another fork's files, touch shared generated files (shader lists, search index, `reports/`, `src/contracts/*`, ledger) — the coordinator runs `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`. Do not add new params or rename ids. Do not bump `Upgraded:` for a rescue-only/hygiene change. Work ONLY under `/root/iv-sonnet-batch-50` (the main checkout `/root/image_video_effects` is on another session's branch — never edit it).

## Report back (final message, ≤ 25 lines)

Per shader: the ADD ideas (one line each, with formula row if any), rescues, A packing, diff-vs-HEAD pixel %, timing ratio, gate results (N/N), and anything you could not verify. Shell cwd may reset — use absolute paths under `/root/iv-sonnet-batch-50`.
