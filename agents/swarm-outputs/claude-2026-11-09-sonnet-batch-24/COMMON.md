# sonnet/batch-24 — shared rules for all forks (spectral colour fields, fabric textures, cyber ripples; 7 first-pass + 3 second-pass)

Worktree: /root/iv-sonnet-batch-24 (branch sonnet/batch-24 = origin/main c37e2fb0 + prelude commit 7d29bf79; bindings are ALREADY `#include "_prelude.wgsl"`). Scratch: /tmp/claude-0/-root-image-video-effects/05f1f026-a1d2-4175-8f85-04efd88e36d5/scratchpad (own scratch in .../scratchpad/forkX/).
Contract: docs/SHADER_UPGRADE_BATCH.md (§0, §2, §9, §12). Add 2–4 NATIVE ideas to the existing effect. Do not reimagine. Plumbing is the floor, not the upgrade.
Batch date for headers: 2026-11-09.

## Shader ownership (do not touch another fork's files)
| Fork | Shaders (WGSL = public/shaders/<id>.wgsl) | JSON dir (shader_definitions/<dir>/<id>.json) | Pass |
|---|---|---|---|
| A | fabric-zipper | interactive-mouse | 2nd (has Ideas: twill weave; rolled tape lips) |
| A | fabric-step-gabor | advanced-hybrid | 1st |
| B | spectral-bleed-confine | advanced-hybrid | 1st |
| B | chroma-kinetic | interactive-mouse | 1st (has Upgraded 2026-08-02 but NO Ideas: = hygiene only) |
| B | magnetic-chroma | image | 2nd (has Ideas: RK2 smear; compass hue; N/S pole pair) |
| C | cyber-ripples-coupled | advanced-hybrid | 2nd (has Ideas: crest doubling; orbital charge ring) |
| C | digital-haze | interactive-mouse | 1st |
| D | data-stream-spectral | advanced-hybrid | 1st |
| D | vaporwave-horizon-prismatic | advanced-hybrid | 1st |
| D | audio-voronoi-gabor | advanced-hybrid | 1st |

## What you may touch
- ONLY your own shaders' WGSL + JSON (JSON: `features` / `tags` / `x-meta` only; `params` byte-exact; if a JSON has NO top-level `params` do NOT add one). Plus your notes: agents/swarm-outputs/claude-2026-11-09-sonnet-batch-24/BRIEFS-forkX.md (write BEFORE any WGSL edit) and NOTES-forkX.md.
- NO git commit/add/stash/checkout/reset/rebase, NO generate_shader_lists, NO upgrades:record, NO build/Vitest (coordinator does all of that). Other forks are editing other files in this same checkout.
- Bindings stay `#include "_prelude.wgsl"`; never paste them. 2nd-pass files: set `Upgraded: <prior date>, 2026-11-09`, EXTEND the `Ideas:` line (keep every existing idea, append yours + §12.2 row names). 1st-pass files: add the standard banner (Category / Features / Complexity / Upgraded: 2026-11-09 / Ideas: / A packing:) keeping any existing title lines; where an older `Upgraded:` date exists keep it first ("2026-08-02, 2026-11-09"). Do not put `fast-motion` in Features.
- JSON features: `upgraded-rgba` only when ACES is on the display RGB and the card is implemented; `audio-reactive` only when plasmaBuffer[0].xyz visibly modulates something; `mouse-driven` only when the pointer changes the picture. Do not add idea-named tags (they dilute the search index and fail the search test); drop tags that become false.

## Tools
- HEAD copies + _prelude.wgsl: …/scratchpad/head/ ; HEAD renders (192 px, idle `_a` = cursor 0.5,0.5 up, audio 0; `_b` = cursor 0.3,0.6 held, audio 0.4,0.3,0.2): …/scratchpad/base/<id>_head_{a,b}.png (3 panels: rgb | over-white | alpha) + .log JSON stats. Montage of all HEAD: base/m1.png, base/m2.png.
- Renderer (image filters need a source photo → ALWAYS use the img variant and SRC=img): `cd /root/iv-sonnet-batch-24 && SRC=img T0=2 node agents/minirender_img.mjs public/shaders/<id>.wgsl <out.png> <size> <frames> <tEnd> <p1,p2,p3,p4> <mx,my,down> <bass,mid,treb>` → stats line (meanL/stdL/meanA/nan/frameMs). Frames span [T0, T0+tEnd]. For long-run behaviour (cloth, sims) use e.g. 240 frames and tEnd 20. `python3 agents/montage.py out.png <panel 0|1|2> label=file ...`. #include resolves relative to the shader's dir, so scratch copies need `_prelude.wgsl` beside them (…/scratchpad/head/ already has it; copy HEAD wgsl there to render a "before").
- Default params = JSON defaults: fabric-zipper .5,.5,.5,.5 | spectral-bleed-confine .5,.5,.5,.5 | audio-voronoi-gabor .3,.5,.5,.5 | fabric-step-gabor .5,.5,.3,.5 | cyber-ripples-coupled .5,.5,.5,.5 | digital-haze .5,.5,.5,.5 | data-stream-spectral .5,.5,.5,.5 | vaporwave-horizon-prismatic .5,.5,.5,.5 | chroma-kinetic .5,.5,1,0 | magnetic-chroma .5,.3,.3,.2
- Gate: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`; `npm run audit:extrabuffer`; `npm run audit:dead-sliders -- --files <id>` (scans 0 defs when JSON has only x-meta — grep sliders by hand: every zoom_params.x/y/z/w must be consumed and visible).

## Known traps in this library — check each against HEAD BEFORE writing ideas
- Render HEAD first (192 AND 576 px, several T0 values, idle cursor AND a moved/held cursor, audio 0 AND 0.4,0.3,0.2). If HEAD is broken (blank/black half, upside-down, strobing, NaN, early return, dead control, time-growing term) FIX IT and document it as RESCUE (R1, R2…), separate from ideas. A rescue that changes the default look is expected — say so with meanL/stdL before→after.
- extraBuffer[0..255] is re-uploaded ZEROED every frame: springs/envelopes in extraBuffer[133..138] NEVER persist (hasSpring / extraBuffer[138]>0.5 is false every frame). Persistent state must live in A texels: texel (0,0) = state, texel (1,0) = `(fract(lastTime),0,0,0.7371)` sentinel (tol 0.001), zero/mask the C read on those texels, every thread integrates the same dt = clamp(fract(time − st1.x), 0.001, 0.05); store fract(time) (A is rgba16float on balanced/battery tiers). Reference implementations: /root/iv-sonnet-batch-20/public/shaders/gen-audio-spirograph.wgsl and acoustic-string-theory.wgsl (SENT const), public/shaders/cyber-lens.wgsl (cursor-track). minirender never re-uploads extraBuffer so extraBuffer state LOOKS alive there — judge nothing from it. Only give pointer state to a shader that already owns the pointer; if the spring is dead and not worth rescuing, REMOVE it honestly (raw mouse) and say so.
- `zoom_config.x` is TIME (= config.x), not a slider; `zoom_config.w` is mouseDown (0/1). Reading either as a parameter is a hidden-slider bug. plasmaBuffer[1..] is NEVER uploaded (always 0): only plasmaBuffer[0].xyz = bass/mids/treble is live; "per-bin FFT" reads of plasmaBuffer[1..8] are dead. extraBuffer is NOT an audio source. Never config.y or zoom_config.x as audio.
- A is rgba16float on most tiers: sim state stored as absolute uv in [0,1] has ~0.0005 resolution and small per-frame velocities quantise to zero. minirender is rgba32float and cannot show it — store small quantities (offsets), fract(time), and flag it in NOTES.
- Clamp before aces() (catalog ACES maps negatives to bright). Guard pow() bases (max(x,0)). No fwidth/dpdx in compute. No reserved identifiers (target, array, …). No filtering sampler on rgba32float history: use exact textureLoad(dataTextureC, coord, 0). Depth: non_filtering_sampler or textureLoad.
- Per-block hash noise gives a pixel mosaic at ≥512 px — use value noise; check 192 AND 576.
- Timings: 4 forks render concurrently under SwiftShader so frameMs is load-noisy; re-time HEAD vs current back-to-back (2 rounds) before accepting a per-pixel cost increase. Heavy ones at HEAD: audio-voronoi-gabor ~170–200 ms and spectral-bleed-confine ~190 ms at 192 px — do not make them slower than ~1.25× HEAD (hoist loop-invariants, share taps).
- Mouse: keep HEAD's pointer behaviour; idle cursor (0.5,0.5) must not move the default look. No spring+ripple+IQ-palette overlay stamped on a shader that does not already own those.

## Idea admission + batch de-dup (§12.4)
Same §12.2 row on ≤2 files in the batch. Row budget (a row not listed for you is someone else's; tactic-derived ideas that are not §12.2 rows are unlimited and preferred):
- Structure-tensor orientation (A): fabric-step-gabor (A) and spectral-bleed-confine (B) only.
- Fresnel–Schlick / Henyey–Greenstein / Beer–Lambert (F): fabric-zipper (A) and digital-haze (C) only.
- Cauchy dispersion (F): chroma-kinetic (B) and data-stream-spectral (D) only. vaporwave already has a 4-band Cauchy reflection — no new Cauchy there.
- Energy-conserving bloom (F): spectral-bleed-confine (B) and vaporwave-horizon-prismatic (D) only.
- Vorticity confinement / Damped wave / Deep-water dispersion (D): cyber-ripples-coupled (C) only.
- Isotropic 9-point Laplacian (D): fabric-step-gabor (A) and cyber-ripples-coupled (C) only.
- Schmitt-trigger lock / Dropout bursts / Block DCT quantization (B-family) and Sync-pulse timing: data-stream-spectral (D) only.
- Soft inverse-square (F), Airy disc, Lens-flare ghosts: vaporwave (D) or magnetic-chroma (B), one file each at most.
Every idea gets a `// ── Idea n: …` comment where it acts. Idea Card + mechanism interrogation (tactics 1,2,3,6 answered in writing, shader's own nouns) in BRIEFS-forkX.md BEFORE WGSL; same-noun / deletion / expert tests (§12.1).

## Coordinator's pre-read of HEAD (HYPOTHESES from reading the code + baseline renders — verify each yourself, do not trust blindly)
- spectral-bleed-confine: `bleedRate = zoom_config.x*0.6+0.1` is TIME-driven → mix(src,bled, edgeMask*bleedRate) extrapolates past 1.0 after ~1.5 s (overshoot); `confinementStr = zoom_config.w*3+0.5` is a hidden mouseDown switch (0.5 ↔ 3.5); history sampled with filtering sampler; alpha hard 1.0; no audio; no ACES/clamp on the HDR glow written to A; banner promises "anisotropic diffusion with channel-dependent tensors" but diffuseChannel is an isotropic Gaussian and recomputes the loop-invariant confFactor + 2 Sobels per call.
- chroma-kinetic: spring dead (springVel always 0 → flick bonus dead); `sectorVoice` reads plasmaBuffer[1..8] (dead); the "velocity" is radial-from-centre, not cursor velocity, so "kinetic" has no motion. Real cursor velocity via the A-texel scheme is the natural native upgrade (A holds display RGBA, C not read).
- magnetic-chroma: 2nd pass, looked healthy; check hue/compass behaviour at idle cursor and with the pole axis; keep `Ideas:` and add on top.
- fabric-zipper: 2nd pass, healthy; native material/mechanism ideas only (zipper kinematics, metal, stitching), keep twill + lips.
- fabric-step-gabor: cloth state in A = (pos, prevPos) absolute uv; the "constraint" only acts while rest-distance is in (2 texels, tearThreshold texels) so once a pixel is pushed past ~4 texels nothing pulls it back (permanent tear; wind+gravity accumulate) — run 300+ frames and look; reads C with non_filtering_sampler at uv=coord/size (texel-edge, not centre) instead of exact textureLoad; B written (strain, vel) but never read (HEAD owns it — keep). f16: store offsets not absolute positions if you touch the packing.
- audio-voronoi-gabor: `getAudioBands` reads extraBuffer[idx*4] (not audio) and, when it is ~0, substitutes a sin()-simulated beat that is ALWAYS ON → at zero audio the whole image strobes and Voronoi cells flash white (treble sparkle); real audio is plasmaBuffer[0].xyz. Colour only clamped to 0..2 (no ACES). 4 orientations × 81 taps = very heavy.
- cyber-ripples-coupled: spring dead → `mouseVel` is 0 for all pixels, so cursor motion never stirs the fluid (only click ripples do); the stored "vorticity" is `vel.x - vel.y` (not a curl); alpha idles at its 0.06 clamp. A = raw sim state (vel.xy, vorticity, dens) — keep raw; only add state that fits.
- digital-haze: spring dead (window follows raw cursor with zero lag; comments lie); `cellBin = plasmaBuffer[1..8]` dead; no standard header; A = (mask, alpha, 0, 1) and C.r is read back as mask hysteresis.
- data-stream-spectral: spring dead (mousePos = raw); `fftStrip = plasmaBuffer[1..8]` dead; no standard header; band 3 subtracts a blur (negative values, clamped before ACES — keep it that way).
- vaporwave-horizon-prismatic: looked healthy; `time*gridSpeed*heldBoost` jumps the scroll phase by (heldBoost−1)·time·gridSpeed when the button goes down/up (time is not held) — fix without changing the default look; no standard header.

## Deliverables per fork
1. BRIEFS-forkX.md (cards + mechanism interrogation + RESCUE list), 2. edited WGSL + JSON, 3. NOTES-forkX.md per shader: kept verbatim, A packing, which ideas are in the diff (with line refs), rescues, default-look change (yes/no, meanL/stdL before→after), formula names per file, gate results (precommit gate, extraBuffer audit, 192 + 576 renders incl. moved-cursor + audio; long-run for sims), open items. 4. Final message: ≤15 lines per shader — ideas added, rescues, anything you are unsure of. Do not claim visual QA on a real GPU.
