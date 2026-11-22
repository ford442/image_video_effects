# COMMON — sonnet/batch-53 (user's list: depth / raymarch / volumetric, 164–285 lines, plus the tone-histogram pair)

Worktree: `/root/iv-sonnet-batch-53` (branch `sonnet/batch-53`, from origin/main a3706adc). Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12 (a fork already has it in context). Notes dir: `agents/swarm-outputs/claude-2026-11-22-sonnet-batch-53/` (gitignored → coordinator uses `git add -f`). `node_modules` is symlinked; `agents/mr*.mjs` (gitignored) are the patched harness copies.

The user's own words: "The usual failures are missing ACES, plasmaBuffer and the dataTextureC load, and writes to extraBuffer slots like 0 or 10." Treat that as a CHECKLIST TO VERIFY per file, not as a diagnosis — the coordinator's grep found **no writes** to `extraBuffer[0..132]` anywhere in the ten (only reads), and the HEAD gates are all green (precommit 10/10, naga-wasm 10/10, dead-sliders 0, extraBuffer violations 0). So the defects, where they exist, are in the *picture* and in *reads of engine slots as if they were parameters*. Engine map: `extraBuffer[0..2]` = bass/mid/treble, `[3]` reserved, `[4]` = historyHead (u32 as f32), `[5..132]` = FFT bins; `[133..255]` is zeroed every frame by `writeExtraBuffer` (no persistent state there either). Audio = `plasmaBuffer[0].xyz`; never `config.y` / `zoom_config.x`.

**BASELINE ("HEAD") for every comparison = the worktree file as it stands when you start.** All ten already use `#include "_prelude.wgsl"`. Your very first action: copy each of your files to your scratch dir as `<id>_head.wgsl` together with `public/shaders/_prelude.wgsl` (and `_std/` if used) *before editing*, then render/time against that copy.

## ID → file map. ALL TEN ALREADY HAVE `Ideas:` (this is a 2nd+ pass for every file; KEEP VERBATIM = every item on the existing `Ideas:` line)

| id | wgsl (public/shaders/) | definition json (shader_definitions/…) | params defaults (p1..p4) | existing `Ideas:` / state |
|---|---|---|---|---|
| parallax_depth_layers | parallax_depth_layers.wgsl | artistic/ | 0.5, 0.5, 0.3, 0.2 | slab occlusion + disocclusion fill; seamless dolly crossfade; rack-focus slice defocus; Beer-Lambert aerial perspective. No ACES. writes A. |
| volumetric-depth-zoom | volumetric-depth-zoom.wgsl | interactive-mouse/ | 1, 0.8, 0.5, 0.8 | slice drift at fg/bg speeds; focal sheet on focus plane. **Header says extraBuffer[0..7] = light_strength, ambient, normal_strength, dof_amount, cameraZ, fov, near, far and the code reads them** — but those are the engine's bass/mid/treble/reserved/historyHead/FFT slots. HEAD stats meanL 0.084 (near black, concentric rings) — verify what is driving that. |
| neural-raymarcher | neural-raymarcher.wgsl | advanced-hybrid/ | 0.5, 0.5, 0.5, 0 | marched in-scatter; action-potential wavefronts. Claims audio-reactive, no plasmaBuffer (reads extraBuffer[0], [10]). HEAD meanL 0.80 washed out. |
| neural-raymarcher-gabor | neural-raymarcher-gabor.wgsl | advanced-hybrid/ | 0.5, 0.5, 0.5, 0 | quadrature Gabor energy; cross-orientation divisive normalisation. Reads extraBuffer[0]/[10]; one hardcoded alpha 1.0 somewhere (alpha out = dominantOrientation). |
| multi-fractal-compositor | multi-fractal-compositor.wgsl | advanced-hybrid/ | 0.3, 0.5, 0, 0 | staggered octave composite; zoom dispersion. Reads extraBuffer[10]. **Pass-1 partner of volumetric-rainbow-clouds** (memory: batch-51 finding) — read both before judging what the compositor is compositing. |
| volumetric-rainbow-clouds | volumetric-rainbow-clouds.wgsl | interactive-mouse/ | 1, 0.5, 0.8, 1 | trilinear value-noise density; Beer-Lambert light-march self-shadow; HG silver lining; scattering-angle corona fringe. No plasmaBuffer. |
| gen-velocity-bloom | gen-velocity-bloom.wgsl | generative/ (no params) | — | Doppler streak fringe; cooling afterglow. The only file that `textureLoad`s C. Persists click state at extraBuffer[133],[134] (zeroed every frame → dead). HEAD meanL 0.86 blown out; no ACES. |
| hybrid-sdf-plasma | hybrid-sdf-plasma.wgsl | hybrid/ | 0.4, 0.5, 0.5, 0.6 | 45° AA halftone screen with dot gain; Sobel-hypot ink line; paper-tooth ink starvation. No ACES / plasmaBuffer, uses `_eNNN` naga-style temporaries. |
| tone-histogram | tone-histogram.wgsl | post-processing/ | 0.5, 0.5, 0.5, 0 | mouse spot meter; per-channel shoulder; density-weighted grain; Wallis local-brightness pull. **Upgraded 2026-11-21 (batch-48) — 3rd pass.** |
| tone-histogram-apply | tone-histogram-apply.wgsl | post-processing/ | 0.5, 0.5, 0.5, 0 | clip-limited CDF blend; percentile-anchored levels. **Upgraded 2026-11-21 (batch-48), already rescued once (histogram built in-pass) — 3rd pass.** Reads/writes A as a raw stats field; keep. |

**Forks (disjoint files — forks cannot see each other; obey the claims below):**
- **A** parallax_depth_layers, volumetric-depth-zoom (depth / parallax pair)
- **B** neural-raymarcher, neural-raymarcher-gabor (the two neural raymarchers — different ideas on each, they share lineage)
- **C** multi-fractal-compositor, volumetric-rainbow-clouds (compositor + its pass-1 source)
- **D** tone-histogram, tone-histogram-apply (tone pair, kept together; both were upgraded yesterday)
- **E** gen-velocity-bloom, hybrid-sdf-plasma

**Header rules.** Keep every existing `Ideas:` item, append `, 2026-11-22` to `Upgraded:` and append the NEW idea names (with §12.2 row names where a row was used) to `Ideas:` (one comment line, may be long). Do not reflow code you do not touch; give each new idea its own lines with a `// ── Idea n: …` comment. `Features:` tags only if true per §8. A rescue-only / hygiene-only change does NOT bump `Upgraded:`. **If, after the §12.1 interrogation, a file genuinely has no 2nd+-pass idea that passes the §12.4 admission test (the tone pair especially: both got 2 ideas yesterday), say so in your brief and ship 1 idea or rescue-only — do not invent an overlay to fill the quota.**

## The failure checklist (run on EVERY file, in this order, before writing a card)

1. **Display ACES present and fed non-negative input?** (catalog ACES fit maps negatives to bright: `aces(-0.18) ≈ 0.68`.) Is the output already display-referred (a colour read back post-ACES and re-tone-mapped)? No ACES on a file that outputs HDR-range values = clipped white (`gen-velocity-bloom` meanL 0.86, `neural-raymarcher` 0.80 — check whether that is clipping or the harness's test-pattern). If A stores raw sim state, never ACES the stored fields, only `writeTexture`.
2. **Audio via `plasmaBuffer[0].xyz`?** If the JSON claims `audio-reactive` the WGSL must modulate something visible from `plasmaBuffer[0].xyz` (or the FFT bins `extraBuffer[5..132]`, read-only). `extraBuffer[0..2]` is bass/mid/treble — legal to read as audio, but not as a parameter. A JSON tag that is not true gets removed in the JSON (§8), a missing audio path is only added if it is native to the effect.
3. **`dataTextureC` read/`dataTextureA` write consistent?** A is next frame's C. If a file writes A but never loads C, the A write is dead — say what it is for. If it loads C it must be `textureLoad(dataTextureC, coord, 0)` (no sampler on rgba32float), clamp the coord, and the write packing must match how C is read back. Zero-C early return (feedback shaders that need C≈0 never start), state texels read as colour, alpha-as-mask read as colour = rescues.
4. **extraBuffer.** No writes to `[0..132]`. No persistent state in `[133..255]` (zeroed per frame). Reads of `[0..7]` / `[10]` as *parameters or fake audio* are defects (`[10]` is FFT bin 5, `[4]` is historyHead, `[3]` is reserved zero).
5. **Others from past batches:** `pow(negative, n)` → NaN; `ripples[i].w` is always 0 (never scale by it); `fract(uv.x * resX)` is always 0.5 (dead masks); upside-down uv / camera inside geometry / ray starting inside the SDF; mirrored y (mouse y is already top-down — no `1-y`); hardcoded alpha 1.0 where a semantic alpha is owed; sliders that do nothing or are shared across roles; `config.y` read as dt/audio/click count; derivatives (`fwidth`, `dpdx`) in compute.

Fixes for defects may change the default look: do them as **rescues**, list them, say loudly if the default picture changes and by how much (pixel % + meanL). Verify a defect on HEAD first (render with the offending input varied) before fixing it.

## HEAD renders (coordinator, read-only — do NOT write here)

`/tmp/claude-0/-root-image-video-effects/0808efa3-e4d2-4c02-b58e-093c2450d257/scratchpad/c/head_<id>.png` (+ `.json`), and `sheet_head.png` (raw | over-white per shader). 256 px, 40 frames, tEnd 4 s, saved JSON defaults, mouse 0.5,0.5 up, audio 0.3,0.2,0.1, `SRC=img` (the harness's synthetic photo: two discs on a soft pattern) — the generative file ran without source.

| id | meanL | stdL | meanA | frameMs @256 (SwiftShader, 3 parallel) | nan |
|---|---|---|---|---|---|
| parallax_depth_layers | 0.365 | 0.102 | 0.485 | 67 | 0 |
| multi-fractal-compositor | 0.656 | 0.157 | 0.320 | 44 | 0 |
| neural-raymarcher | 0.802 | 0.119 | 0.319 | 41 | 0 |
| gen-velocity-bloom | 0.861 | 0.186 | 0.800 | 85 | 0 |
| neural-raymarcher-gabor | 0.508 | 0.097 | 0.967 | 249 | 0 |
| volumetric-depth-zoom | **0.084** | **0.024** | 0.502 | 40 | 0 |
| tone-histogram-apply | 0.481 | 0.286 | 1.000 | 167 | 0 |
| tone-histogram | 0.511 | 0.183 | 0.498 | 31 | 0 |
| hybrid-sdf-plasma | 0.292 | 0.174 | 0.385 | 24 | 0 |
| volumetric-rainbow-clouds | 0.552 | 0.124 | 0.391 | 74 | 0 |

## Cross-fork §12.2 row ownership (a row appears on at most one file in the batch; coordinator enforces §12.4 de-dup)

Use only rows you own below, or ideas that are NOT §12.2 rows (domain-native mechanisms from §12.1 — a neuron's refractory period, a halftone screen's dot gain, a camera's depth-of-field circle of confusion — need no ownership and are the better ideas). A row you do not own may not be used. Rows already present in a file at HEAD stay (do not extend them without a new look).

- **Step-count AO**: neural-raymarcher only. **Over-relaxed sphere tracing**: neural-raymarcher-gabor only. **SDF curvature**: hybrid-sdf-plasma only.
- **Orbit trap, smooth iteration count**: multi-fractal-compositor only.
- **Energy-conserving bloom**: gen-velocity-bloom only. **Vorticity confinement, MacCormack advection**: gen-velocity-bloom only (HEAD has curl-noise advection + a flow estimate; add only if it is a new look).
- **Halation, H&D characteristic curve, photon shot noise, Schmitt-trigger lock, guided-filter base/detail, cos⁴ vignetting**: tone-histogram / tone-histogram-apply only (fork D decides the split; Wallis, density-weighted grain, CLAHE clip are already used — do not duplicate).
- **Cauchy dispersion**: multi-fractal-compositor / volumetric-rainbow-clouds already carry dispersion/fringe at HEAD — no new Cauchy use anywhere.
- **Beer–Lambert, Henyey–Greenstein**: already shipped on parallax_depth_layers and volumetric-rainbow-clouds (keep verbatim, no extension); nobody else may add them.
- **Fresnel–Schlick, Snell, thin-film, lens-flare ghosts, Airy disc, golden-angle layout**: nobody.
- Frame-hash strobing, generic spring/ripple overlays, IQ cosine palettes bolted on as the whole look and `fwidth` are rejected everywhere. **No new springs in `extraBuffer`.** The pointer/clicks only where the file already owns them.

## Per fork, in this order

1. Read each file + its JSON in full. Run HEAD first. Run the failure checklist. Find HEAD defects by varying inputs (sliders, mouse, audio, SRC=img vs no source) and fix them as **rescues**; list them.
2. Write `BRIEFS-fork<X>.md` here: Idea Card per shader + §12.1 mechanism interrogation answers (tactics 1,2,3,6) + §12.4 formula admission — **before any WGSL edit**. The ideas must be NEW relative to the existing `Ideas:` line.
3. Implement 2 (max 3) native ideas per shader in the existing main path; `// ── Idea n: …` comment at each. Saved `params` byte-exact (ids, names, defaults, min/max/step, mapping order); no spring/ripple/IQ overlay unless the file already owns it. State lives in A/C — keep each file's existing A packing and SAY SO on the card. Clamp before `aces()`. No `fwidth`/`dpdx`.
4. JSON: append to `description` only if the visible behaviour changed; `features` tags only when true (§8) — remove a tag that is false (`audio-reactive` without a live audio path, `upgraded-rgba` without ACES); never touch `params`. `x-meta.upgrade.params` additive only.
5. Write `NOTES-fork<X>.md` per shader: Idea Card ADD list, KEEP VERBATIM, A packing, rescues, diff vs HEAD, timing, gates.

## Verify (VM = SwiftShader, no real GPU; do not claim visual QA)

- Render: `node agents/mr.mjs <wgsl> <out.png> [size] [frames] [tEnd] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]` (env: `SRC=img` for the synthetic photo — **these are all image-processing / photo-input shaders except gen-velocity-bloom, so use SRC=img**; `SRCFLAT`, `SEEDC`, `MPATH`, `T0`, `A16`, `RIPPLES='x,y,t_start_abs,0;…'`; the stock harness treats the 3rd RIPPLES value as a constant age — use `agents/mr_c_abs.mjs` for an absolute start time). PNG = raw rgb | over-white | alpha, 3 panels 256 wide. **The harness defaults sliders to 1,1,1,1: always pass the JSON defaults explicitly** (table above). Scratch dir (use it, not /tmp): `/tmp/claude-0/-root-image-video-effects/0808efa3-e4d2-4c02-b58e-093c2450d257/scratchpad/<fork-letter-lowercase>/`. Look at the PNG (Read it) at defaults AND with params/mouse/clicks/audio exercised, at ≥2 times, and compare HEAD vs NEW side by side (a contact sheet via PIL is fine); check NaN count; check the picture is not blank / saturated / uniform. 512 works for readback (500 fails).
- Time: `agents/mr_ab.mjs <size> <cycles> <params> <mouse> <audio> <wgslHEAD> <wgslNEW>` (interleaved, min/median; ≥4 rounds; ratio of medians). The box is shared with four other forks (and possibly another session's Playwright jobs — never pkill them), so single readings lie; the coordinator re-times borderline files on a quiet box. Cap **≤ ~1.3×** HEAD; trim (fewer taps / `select` instead of `if` / no per-sample accumulators) if over, and say so. Per-pixel loops cost linearly on SwiftShader even when a branch is never taken.
- Gates, each file: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<file>.wgsl`; `node scripts/verify-naga-wasm.mjs --files public/shaders/<file>.wgsl` (stricter than precommit; reserved words like `demote`/`target`, `__x` names); `python3 scripts/audit_dead_sliders.py --files <id>`; `python3 scripts/audit_extrabuffer.py`. Grep each slider read by hand if the dead-slider audit scans 0 defs.
- `pkill -f "[p]attern"` form only and ONLY patterns that name your own scratch files.

## Do NOT

Commit, `git stash` (stash list is shared by every worktree), `git checkout`/`reset` anything, touch another fork's files, touch shared generated files (shader lists, search index, `reports/`, `src/contracts/*`, ledger) — the coordinator runs `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`. Do not add new params or rename ids. Work ONLY under `/root/iv-sonnet-batch-53` (the main checkout `/root/image_video_effects` is on another session's branch, and `/root/iv-sonnet-batch-52` belongs to another live session — never edit either).

## Report back (final message, ≤ 25 lines)

Per shader: the ADD ideas (one line each, with formula row if any), rescues (with the verification that proved the HEAD defect), A packing, diff-vs-HEAD pixel %, meanL before/after, timing ratio, gate results (N/N), and anything you could not verify or any open call for the user. Shell cwd may reset — use absolute paths under `/root/iv-sonnet-batch-53`.
