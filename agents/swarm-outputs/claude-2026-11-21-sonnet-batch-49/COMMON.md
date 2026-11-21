# COMMON — sonnet/batch-49 (user's line-count list: liquid / volumetric / field sims, 9 files)

Worktree: `/root/iv-sonnet-batch-49` (branch `sonnet/batch-49`, from origin/main d5c0fca6). Law: `docs/SHADER_UPGRADE_BATCH.md` §0–§12 (the fork already has it in context). Notes dir: `agents/swarm-outputs/claude-2026-11-21-sonnet-batch-49/` (gitignored → coordinator uses `git add -f`).

**BASELINE ("HEAD") for every comparison = the worktree file as it stands when you start.** The coordinator already ran `migrate_to_prelude.py` on eight of the nine (header-only infra, no `Upgraded:` bump; pixel output identical to origin/main); `liquid-rainbow-prismatic` already used the prelude. Your very first action: copy each of your files to your scratch dir as `<id>_head.wgsl` together with `public/shaders/_prelude.wgsl` (and `_std/` if you use it) *before editing*, then render/time against that copy. `#include` resolves relative to the wgsl's directory.

**ID → file map** (every id equals its file name):

| id | wgsl (public/shaders/) | definition json (shader_definitions/) | pass |
|---|---|---|---|
| liquid-rainbow-prismatic | liquid-rainbow-prismatic.wgsl | liquid-effects/liquid-rainbow-prismatic.json | **2nd** (`Ideas:` = gravity drainage + Newton's black film; dispersed caustics → KEEP VERBATIM) |
| liquid-lens | liquid-lens.wgsl | interactive-mouse/liquid-lens.json | 1st (only a "Batch 59" hygiene comment) |
| liquid-metal-prismatic | liquid-metal-prismatic.wgsl | advanced-hybrid/liquid-metal-prismatic.json | 1st ("Codex (e) audited" hygiene header) |
| liquid-oil-iridescence | liquid-oil-iridescence.wgsl | advanced-hybrid/liquid-oil-iridescence.json | 1st (same) |
| liquid-jelly-fluid | liquid-jelly-fluid.wgsl | advanced-hybrid/liquid-jelly-fluid.json | 1st (same) |
| interactive-magnetic-ripple-em | interactive-magnetic-ripple-em.wgsl | advanced-hybrid/interactive-magnetic-ripple-em.json | 1st |
| aerogel-smoke-hdr | aerogel-smoke-hdr.wgsl | advanced-hybrid/aerogel-smoke-hdr.json | 1st |
| atmos-fog-volumetric | atmos-fog-volumetric.wgsl | advanced-hybrid/atmos-fog-volumetric.json | 1st |
| heat-haze-volumetric | heat-haze-volumetric.wgsl | advanced-hybrid/heat-haze-volumetric.json | 1st |

**Header rules.** None of the first-pass files has an `Ideas:` line, so they are all *creative first pass*: write a standard banner (title, Category, Features, Upgraded: 2026-11-21, Ideas:, A packing:) and keep any existing descriptive comment line. Most files are written as dense one-line statements: **do not reflow code you do not touch** (the diff must stay reviewable); give each new idea its own lines with a `// ── Idea n: …` comment. `liquid-rainbow-prismatic` (2nd pass): append `, 2026-11-21` to `Upgraded:` and append the new idea names (with §12.2 row names) to `Ideas:`; the existing two ideas stay. `Features:` tags only if true per §8.

**Forks (disjoint files — forks cannot see each other, obey the claims below):**
- **A** liquid-rainbow-prismatic, liquid-lens (optical dispersion pair)
- **B** liquid-metal-prismatic, liquid-oil-iridescence (spectral surface pair)
- **C** liquid-jelly-fluid, interactive-magnetic-ripple-em (field solvers)
- **D** aerogel-smoke-hdr, atmos-fog-volumetric (scattering media)
- **E** heat-haze-volumetric (single file)

## Coordinator's read of HEAD (starting points to VERIFY, not instructions — your Idea Card must come from your own reading)

**Finding 1 — three of the four "template" sims are pass-through at default.** `aerogel-smoke-hdr`, `heat-haze-volumetric` and `interactive-magnetic-ripple-em` get their only source terms from the held pointer (`zoom_config.w`) and click ripples. With no pointer and no click, the state stays empty: `node agents/mr.mjs … 160 40 1.5` at defaults returns `meanA 0.000` and the picture equals the source photo (aerogel/heat-haze: `stdL` ≈ source). `atmos-fog-volumetric` is not affected (its `terrain` band is an ambient source, meanA 0.038). A viewer / thumbnail scanner sees the unmodified photo. Decide per file whether an *idle, native* source exists (heat haze: sun-heated bright surfaces radiate heat → scene luma is an intermediate the file never promotes; aerogel: a slow ambient density source) and, if you add one, say so loudly as a rescue and keep the pointer/click behaviour exactly. For `interactive-magnetic-ripple-em` an idle driver is optional — it is an *interactive* effect; if you add one it must be an EM source (e.g. a slowly orbiting dipole), not a costume.

**Finding 2 — `pow(x, 2.0)` with a possibly negative base** is used for the click-ring Gaussian in aerogel / heat-haze / atmos-fog / magnetic (`exp(-pow((length(cq)-radius)*K,2.0))`; atmos-fog also in `terrain`). `pow(neg, 2.0)` is undefined in WGSL. **SwiftShader does NOT show it** (I rendered all four with a click: `nan 0`), so this is latent on real GPUs, unproven here. Replace with `x*x` (bit-identical for finite values) in the files you touch and say "latent, unproven on SwiftShader" — do not claim it was a confirmed bug.

**Finding 3 — tags/params promise things the code never does.** `atmos-fog-volumetric` (tags `depth-aware`, param `depth_weight`) and `heat-haze-volumetric` (`depth-aware`) never read `readDepthTexture`. `liquid-jelly-fluid` lists `subsurface-scattering` and `elastic-bounce` but has no subsurface term. `atmos-fog` computes the sun phase `0.55+0.45*pow(max(sun.z,0.0),4.0)` from a constant vector, so the in-scatter colour is the same for every pixel (no HG forward-scatter toward the sun). `heat-haze` "shimmer" is a white per-pixel per-frame hash (frame-hash static, not coherent shimmer). `liquid-oil-iridescence` colours the film with a 3-phase cosine palette `spectral(h)` (an IQ-style fake) and computes `angle` but uses it only for alpha; `liquid-metal-prismatic` "metal" is `luma*(0.42,0.5,0.62)` plus bands — no facet normal shading.

**Finding 4 — `interactive-magnetic-ripple-em` Faraday sign (verify with a CPU port or energy-vs-time renders before touching).** The update is `E += c·(∂B/∂y, −∂B/∂x)` (= curl B) and `B += c·curlE` with `curlE = ∂Ey/∂x − ∂Ex/∂y`. Combining these gives `∂²B/∂t² = −∇²B` (elliptic → exponential growth of high-k modes) instead of a wave equation; the clamp ±2.5 and the heavy damping (`exp(-damping*(0.6+dt*30))` ≈ 0.9/frame at defaults) may be hiding it. If confirmed (energy grows / checkerboard noise at damping→0), flipping the B update to `−curlE` is a **rescue** — report it loudly with before/after energy numbers. If your port shows it is already stable, say so and leave it.

## Cross-fork row claims (a §12.2 row / term appears on at most two files in this batch; §12.4 de-dup is enforced by the coordinator)

- Cauchy dispersion (new idea): **liquid-metal-prismatic** only (liquid-lens uses lateral CA scaled by radius instead, not Cauchy; liquid-rainbow already HAS Cauchy at HEAD — keep it, do not re-add).
- Snell vector refraction, Jacobian-determinant caustic: **liquid-lens** only.
- Thin-film phase (§12.2F): **liquid-oil-iridescence** and **liquid-rainbow-prismatic** (the two files whose identity *is* thin film) — they must differ on every idea (rainbow: viewing-angle / Fresnel-weighted film strength on the surface normal it already computes; oil: π-phase-convention, coherence washout of high orders, replacing the cosine palette). No third file uses it.
- Fresnel–Schlick (new idea): **liquid-metal-prismatic** (conductor F0 on facet normals), **liquid-jelly-fluid** (dielectric sheen). Henyey–Greenstein: **aerogel-smoke-hdr**, **atmos-fog-volumetric**. Beer–Lambert on real depth: **atmos-fog-volumetric**, **liquid-jelly-fluid** (thickness). Rayleigh λ⁻⁴ spectral extinction: **aerogel-smoke-hdr** only. Energy-conserving bloom: **aerogel-smoke-hdr** only.
- MacCormack advection: **liquid-jelly-fluid** only. Vorticity confinement is already at HEAD in jelly (keep). Damped wave / dispersion / sponge boundary / dielectric medium: **interactive-magnetic-ripple-em** only. Boussinesq buoyancy, Gladstone–Dale refractive index: **heat-haze-volumetric** only. Shallow-water continuity (∂h/∂t = −∇·(h v)), surface tension: **liquid-oil-iridescence** only.
- Frame-hash strobing, generic spring/ripple overlays and IQ palettes are rejected everywhere. Pointer-owned files (liquid-lens, jelly, oil, metal, magnetic, the volumetrics' brush) may use the pointer/clicks they already own, not a new overlay. No new springs in `extraBuffer`.

## Per fork, in this order

1. Read each file + its JSON in full. Run HEAD first — find HEAD defects (blank / upside-down / dead sliders / wrong audio source / `pow` negative base / negative into ACES / illegal `textureStore` to read-only `dataTextureC` / `plasmaBuffer` never indexed / `ripples[i].w` always 0 / `fract(uv.x*resX)` dead masks / zero-C early return / `extraBuffer[0..132]` used as state / hardcoded alpha 1.0 where a semantic alpha is owed) and fix them as **rescues**; list them. Fixes for defects may change the default look, but say so loudly in your report.
2. Write `BRIEFS-fork<X>.md` here: Idea Card per shader + §12.1 mechanism interrogation answers (tactics 1,2,3,6) + §12.4 formula admission — **before any WGSL edit**.
3. Implement 2 (max 3) native ideas per shader in the existing main path; `// ── Idea n: …` comment at each. Saved `params` byte-exact (ids, names, defaults, min/max, mapping order); no spring/ripple/IQ-palette overlay unless the file already owns the pointer/that look. Sim state lives in A/C textures — **never extraBuffer[0..132]** (extraBuffer is re-uploaded every frame; 133..255 is also zeroed per frame, so no state there either). Clamp before `aces()` (catalog ACES maps negatives to bright). No `fwidth`/`dpdx` in compute. Raw-state A (jelly, oil, metal, magnetic, aerogel, heat-haze, atmos-fog) is NOT tone-mapped in storage — ACES only on `writeTexture`; keep each file's existing A packing (say so on the card).
4. JSON: append to `description` only if the visible behaviour changed; `features` tags only when true (§8); never touch `params`. `x-meta.upgrade.params` additive only.
5. Write `NOTES-fork<X>.md` per shader: Idea Card ADD list, KEEP VERBATIM, A packing, rescues, diff vs HEAD, timing, gates.

## Verify (VM = SwiftShader, no real GPU; do not claim visual QA)

- Render: `node agents/mr.mjs <wgsl> <out.png> [size] [frames] [tEnd] [p1,p2,p3,p4] [mx,my,down] [bass,mid,treb]` (env: `SRC=img` for an image-like source, `SRCFLAT`, `SEEDC`, `MPATH`, `T0`, `A16`, `RIPPLES='x,y,t,0;…'` to inject click ripples). Verified working in this worktree (the harness `.mjs` files were copied into `agents/`, which is gitignored). Scratch dir (use it, not /tmp): `/tmp/claude-0/-root-image-video-effects/28bfd289-1a0d-46f8-916c-0eb131340909/scratchpad/<fork-letter-lowercase>/`. Look at the PNG (Read it) at defaults AND with params/mouse/clicks/audio exercised; check the NaN count in the JSON it prints; check the picture isn't blank/saturated/uniform. For sims, render long enough (≥ 60 frames) for the state to build and for any instability to show.
- Time: `agents/mr_perf.mjs` (min-of-drained-frames, interleave HEAD/new, ≥4 rounds, median of per-round ratios; the box is loaded — five forks run at once — so single readings lie, and the coordinator re-times borderline files on a quiet box). Cap **≤ ~1.3×** HEAD; trim (fewer taps / `select` instead of `if` / no per-sample accumulators) if over, and say so.
- Gates, each file: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`; `node scripts/verify-naga-wasm.mjs --files public/shaders/<id>.wgsl` (stricter than precommit; `demote` etc. are reserved); `python3 scripts/audit_dead_sliders.py --files <id>`; `python3 scripts/audit_extrabuffer.py`. If a file's JSON has only `updatedParams`, the dead-slider audit scans 0 defs — grep each slider read by hand.
- `pkill -f "[p]attern"` form only (a bare pattern kills your own shell) and ONLY patterns that name your own scratch files — other forks are timing at the same moment.

## Do NOT

Commit, `git stash` (stash list is shared by every worktree), `git checkout`/`reset` anything, touch another fork's files, touch shared generated files (shader lists, search index, `reports/`, `src/contracts/*`, ledger) — the coordinator runs `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`. Do not add new params or rename ids. Do not bump `Upgraded:` for a rescue-only/hygiene change. Work ONLY under `/root/iv-sonnet-batch-49` (the main checkout `/root/image_video_effects` is on another session's branch with uncommitted manifests — never edit it).

## Report back (final message, ≤ 25 lines)

Per shader: the ADD ideas (one line each, with formula row), rescues, A packing, diff-vs-HEAD pixel %, timing ratio, gate results (N/N), and anything you could not verify. Shell cwd may reset — use absolute paths under `/root/iv-sonnet-batch-49`.
