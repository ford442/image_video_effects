# sonnet/batch-22 — shared rules for all forks (glass creature & relic ten, all SECOND-PASS: every file already has an `Ideas:` line)

Worktree: /root/iv-sonnet-batch-22 (branch sonnet/batch-22, origin/main a3ccd30a + prelude commit 01eef824). Scratch: /tmp/claude-0/-root-image-video-effects/277dbc64-b071-4218-b367-90c90269ce93/scratchpad (use /tmp/claude-0/-root-image-video-effects/277dbc64-b071-4218-b367-90c90269ce93/scratchpad/forkX/ for your own scratch).
Contract: docs/SHADER_UPGRADE_BATCH.md (§0, §2, §9, §12). Add 2–4 NEW native ideas on top of the existing `Ideas:` line, never replacing it. Do not reimagine.

## What you may touch
- ONLY your own shaders' `public/shaders/<id>.wgsl` and `shader_definitions/generative/<id>.json` (JSON: features / x-meta only; `params` byte-exact; if the JSON has NO top-level `params` do NOT add one — the app feeds 0.5 x4 and adding params changes defaults).
- Your notes: agents/swarm-outputs/claude-2026-11-08-sonnet-batch-22/BRIEFS-forkX.md (write BEFORE any WGSL edit) and NOTES-forkX.md.
- NO git commit/add/stash/checkout/reset, NO generate_shader_lists, NO upgrades:record, NO build/Vitest (coordinator does all of that). Other forks are editing other files in this same checkout.
- Bindings stay `#include "_prelude.wgsl"`; never paste them. Do not bump `Upgraded:` for plumbing; DO set `Upgraded: <prior date>, 2026-11-08`-style (keep prior date, append 2026-11-08) when ideas land, and extend the `Ideas:` line (keep every existing idea, append yours, tag the §12.2 row names).

## Tools (HEAD copies + _prelude.wgsl are in /tmp/claude-0/-root-image-video-effects/277dbc64-b071-4218-b367-90c90269ce93/scratchpad/head/; HEAD renders in /tmp/claude-0/-root-image-video-effects/277dbc64-b071-4218-b367-90c90269ce93/scratchpad/base/*_head.png)
- Renderer: `cd /root/iv-sonnet-batch-22 && T0=2 node agents/minirender.mjs <wgsl> <out.png> <size> <frames> <tEnd> <p1,p2,p3,p4> <mx,my,down> <bass,mid,treb>` → 3 panels (rgb | over-white | alpha) + JSON stats line (meanL/stdL/meanA/nan). `/tmp/claude-0/-root-image-video-effects/277dbc64-b071-4218-b367-90c90269ce93/scratchpad/rb.sh <id> <out.png> <T0> <size> <frames> <tEnd> <params> <mouse> <audio>` is a wrapper. Montage: `python3 agents/montage.py out.png <panel 0|1|2> label=file ...`. #include resolves relative to the shader's dir, so scratch copies need `_prelude.wgsl` beside them.
- Default params to render with (JSON defaults; 0.5 x4 where the JSON has no params): see /tmp/claude-0/-root-image-video-effects/277dbc64-b071-4218-b367-90c90269ce93/scratchpad/baseline.sh.
- Gate: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`; `npm run audit:extrabuffer`; `npm run audit:dead-sliders -- --files <id>` (audit scans 0 defs when JSON has only x-meta — grep sliders by hand).

## Known traps in this library (from earlier batches — check each against HEAD BEFORE writing ideas)
- Render HEAD first (192 AND 576 px, several T0 values, idle cursor 0.5,0.5 AND a moved cursor, audio 0 AND 0.4,0.3,0.2). If HEAD is broken (blank/black half, upside-down camera, camera inside an SDF, ACES-on-ACES wash, pow(negative), off-screen centre, early return when C≈0) FIX IT and document as RESCUE (R1, R2…) separately from ideas — default looks changing is expected for rescues, say so.
- Baseline observations from the coordinator (192px, t=2..5, default params): crystalline-forge is BLANK (stdL 0, meanA 0.002); chandelier lower half black / upper half noisy; ethereal-nautilus is noisy sand not a shell; scarab dim (meanL 0.08); the rest plausible. Single frame, verify yourself.
- extraBuffer[0..255] is re-uploaded ZEROED every frame: springs/envelopes in extraBuffer[133..138] never persist. Persistent state must live in A texels (scheme: A(0,0)=state, A(1,0)=(fract(lastTime),0,0,0.7371) sentinel tol 0.001, mask the C read on those texels, every thread integrates same dt = clamp(fract(time-st1.x),0.001,0.05); store fract(time) — A is rgba16float on balanced/battery tiers). Only add pointer state to a shader that already owns the pointer. minirender never re-uploads extraBuffer, so extraBuffer state LOOKS alive there — judge nothing from it.
- plasmaBuffer[1..] is never uploaded (always 0): only plasmaBuffer[0].xyz = bass/mids/treble is live. Never config.y / zoom_config.x as audio.
- Clamp before aces() (catalog ACES maps negatives to bright). Guard pow() bases (max(x,0)). No fwidth/dpdx in compute. No reserved identifiers (target, array, …).
- Per-block hash noise gives a pixel mosaic at >=512 px — use value noise; check 192 AND 576.
- Timings: 4 forks render concurrently under SwiftShader so frameMs is load-noisy; a new per-step cost in a raymarcher must be re-timed HEAD vs current back-to-back (2 rounds) before you accept it. Keep new work out of map() unless floor-hit/post-march.
- Mouse: keep HEAD's pointer behaviour; idle cursor (0.5,0.5) must not move the default look. No spring+ripple+IQ-palette overlay.

## Idea admission + batch de-dup (§12.4)
Same §12.2 row on ≤2 files in the batch. Row budget per fork (a row not listed for you is someone else's or already used — tactic-derived ideas that are not §12.2 rows are unlimited):
- Fork A (ethereal nautilus, radiant nautilus, mycelium engine): Fresnel–Schlick/Beer–Lambert (F), Golden-angle layout (E), Additive domain twist (E).
- Fork B (scarab, crystalline-forge, kryonic core): Fold count as material (E), SDF curvature (E), Over-relaxed sphere tracing (E). NOT orbit trap (kryonic already has it).
- Fork C (celestial tornado, vitreous chandelier): Snell vector refraction (F), Step-count AO (E), Airy disc (F), Soft inverse-square (F). Cauchy is already on the tornado — at most one more Cauchy in the batch (fork C only).
- Fork D (chromatic singularity loom, neuro-lace matrix): Henyey–Greenstein (F), Energy-conserving bloom (F), Smooth iteration count (E) only if an escape loop exists.
Every idea gets a `// ── Idea n: …` comment where it acts; Idea Card + mechanism interrogation (tactics 1,2,3,6 answered in writing, shader's own nouns) in BRIEFS-forkX.md BEFORE WGSL; same-noun / deletion / expert tests.

## Deliverables per fork
1. BRIEFS-forkX.md (cards + interrogation + RESCUE list), 2. edited WGSL + JSON, 3. NOTES-forkX.md per shader: kept verbatim, A packing, which ideas are in the diff (with line refs), rescues, default-look change (yes/no, how big: meanL/stdL before→after), formula names per file, gate results (precommit gate, extraBuffer audit, 192+576 renders incl. moved-cursor + audio), open items. 4. Final message: a ≤15-line summary per shader — ideas added, rescues, anything you are unsure of. Do not claim visual QA on a real GPU.
