# sonnet/batch-27 — shared rules for all forks (optical lenses: flares, heat haze, fisheye / zoom lenses, spectral dispersion)

Repo: /home/user/image_video_effects, branch `claude/ecstatic-darwin-l3cyoz` (= origin/main 09a7c03e + prelude-migration commit 36536cd0; **bindings are ALREADY `#include "_prelude.wgsl"`** in all ten files).
Contract: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §9, §12). Add 2–4 NATIVE ideas to the existing effect. Do not reimagine. Plumbing is the floor, not the upgrade. Batch date for headers: **2026-11-09**.
Cards + mechanism interrogation: `BRIEFS.md` in this folder (written BEFORE any WGSL edit). Your job is to implement the cards, not to re-decide them; if a card is impossible or wrong, say so in NOTES and implement the closest honest version.

## Ownership (do not touch another fork's files)
| Fork | Shaders (`public/shaders/<id>.wgsl`) | JSON (`shader_definitions/<dir>/<id>.json`) |
|---|---|---|
| A | ascii-lens | interactive-mouse |
| A | cross-mouse-spec-dispersion-lens | interactive-mouse |
| A | quantum-flux | interactive-mouse |
| B | cyber-magnifier | interactive-mouse |
| B | multi-fractal-compositor-lens | advanced-hybrid |
| B | interactive-fisheye | interactive-mouse |
| C | double-exposure | interactive-mouse |
| C | heat-haze-mirage | image |
| C | interactive-zoom-blur | distortion |
| coordinator | anamorphic-flare | interactive-mouse |

## What you may touch
- ONLY your own shaders' WGSL + JSON (JSON: `features` / `tags` / `x-meta` only; `params` byte-exact; never add a top-level `params`). Plus `NOTES-<fork>.md` in this folder.
- NO `git add/commit/stash/checkout/reset`, NO `generate_shader_lists`, NO `upgrades:record`, NO build / Vitest / `npm install` (coordinator does all of that). Other forks edit other files in this same checkout.
- Bindings stay `#include "_prelude.wgsl"`; never paste them. Update the header banner: `Category / Features / Complexity / Upgraded: <old dates, 2026-11-09> / Ideas: / A packing:` — keep every existing `Ideas:` item, append yours with the §12.2 row name where one applies. Do NOT put `fast-motion` in Features (double-exposure currently lists it in its banner and JSON — drop it from the banner and JSON features/tags unless the card says otherwise; it did not opt into a fast-motion brief).
- JSON features: `upgraded-rgba` only when ACES is on the display RGB and the card is implemented; `audio-reactive` only when plasmaBuffer[0].xyz / engine FFT visibly modulates something; `mouse-driven` only when the pointer changes the picture. No idea-named tags (they dilute the search index). Drop tags/features that become false (e.g. `spring-damper-pointer` stays only if the glide is real).
- Every idea gets a `// ── Idea n: …` comment where it acts; every rescue a `// ── Rescue Rn: …` comment. A reviewer must be able to point at each from the diff.

## Tools
- HEAD copies (before): `/tmp/claude-0/-home-user-image-video-effects/d42ad8f0-8e0e-5ffd-959e-50bf3ecd73aa/scratchpad/head/<id>.wgsl` (+ `_prelude.wgsl` beside them).
- Render harness (SwiftShader WebGPU, being built by a background agent): `/tmp/claude-0/-home-user-image-video-effects/d42ad8f0-8e0e-5ffd-959e-50bf3ecd73aa/scratchpad/harness/` — read its `README.md` for the exact command; wait for `README.md` to exist (poll with `ls`, sleep ≤30 s at a time) before rendering. Use it on HEAD AND your edit, same params/mouse/audio, and LOOK at the PNGs (Read tool views images). Check: not blank/black, not upside-down, no NaN (`nan:0`), idle default look still recognisably the same effect, nothing time-growing, no strobing between frames. Render at 192 px and once at 576 px; also a moved/held cursor and an audio render (e.g. `--audio 0.5,0.4,0.3`).
- Structural gates you run on YOUR files: `node scripts/verify-naga-wasm.mjs --files public/shaders/<id>.wgsl …` (Naga; the `naga` CLI is not installed) and `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl` (bindgroup/workgroup/extraBuffer/pasted-header), `python3 scripts/audit_extrabuffer.py` if you touch extraBuffer, `python3 scripts/audit_dead_sliders.py --files <id>` (check usage; when it scans 0 defs, grep sliders by hand: every `zoom_params.x/y/z/w` must still be consumed and visible).

## Facts about THIS engine (verified in `src/renderer/webgpu/{audioDepth,frame}.ts` — do not rely on older docs where they disagree)
- `extraBuffer[0..255]` is **re-uploaded every frame** (`writeExtraBuffer`, a 256-float scratch: `[0..2]` = bass/mid/treble, `[4]` = historyHead, `[5..132]` = FFT bins, everything else **zero**). So `[133..255]` springs/envelopes NEVER persist: HEAD's "spring" code in these files is dead (the init flag `extraBuffer[137/138]` reads 0 every frame → every pixel falls back to the raw cursor). Persistent state must live in A texels (see R1 below). Don't "fix" it by writing extraBuffer.
- **Per-bin FFT IS live**: engine FFT bins are `extraBuffer[5u + bin]`, bin 0..127, normalised 0..1, read-only (guard with `arrayLength(&extraBuffer)`; precedent: `kimi_fractal_dreams.wgsl` `fftBin()`, `gen_grokcf_interference.wgsl` `fftBand()`). **`plasmaBuffer[1..]` is never uploaded (always 0)** — any `plasmaBuffer[k>0]` read in these files is a dead-audio bug (rescue it by reading `extraBuffer[5 + bin]` for per-bin voices, keep `plasmaBuffer[0].xyz` for bass/mids/treble). Low bins carry most energy; map the 8 old "bins" to roughly bins {0,1,2,4,7,11,19,32} (or averages of a few adjacent ones) so each voice is audible; at zero audio the old (dead) value was 0 so the idle look must not change.
- `zoom_config.x` is TIME (= `config.x`), not a slider; `zoom_config.w` is mouseDown (0/1). Never `config.y` / `zoom_config.x` as audio. `config.y` = rippleCount; ripple slots past it are zero.
- A (`dataTextureA`) is `rgba16float` on most real tiers (rgba32float on the high tier); C = last frame's A, read with exact `textureLoad(dataTextureC, coord, 0)` (never a filtering sampler). Absolute uv in A has ~0.0005 resolution; store small quantities / `fract(time)`.
- Clamp before `aces()` (catalog ACES maps negatives to bright). Guard `pow()` bases (`max(x,0.0)`), `sqrt`, divisions. No `fwidth`/`dpdx` in compute. No reserved identifiers (`target`, `array`, `filter`, `sample`…). Branchless where cheap (`select`, `mix`, masks).
- Mouse Y is top-down (no `1.0 - y` flip). Idle cursor (0.5,0.5) must not move the default look.

## R1 — the shared cursor-glide rescue (used by ascii-lens, cross-mouse-spec-dispersion-lens, quantum-flux, multi-fractal-compositor-lens, double-exposure, interactive-zoom-blur, heat-haze-mirage; interactive-fisheye uses only the lag vector)
HEAD's `extraBuffer[133..138]` springs are dead (above). Rescue them with the same scheme `cyber-magnifier.wgsl` already ships (its glide lives in A texel (0,0)):
```wgsl
// ── Rescue R1: cursor glide in A texel (0,0) ─────────────────────────
// extraBuffer[133..] is re-uploaded zeroed every frame, so the spring could never persist.
// State = A(0,0) = (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel reads the same C texel and
// integrates the same step, only pixel (0,0) stores it. First-order glide (a velocity cannot be stored
// f16-safely); the lag vector (raw - glide) is the velocity proxy.
const GLIDE_MARK: f32 = 7.0;
fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
    let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w < 1.0;
    let dt = clamp(fract(time - st.w), 0.001, 0.05);
    let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
    let snapped = select(g, raw, length(raw - g) < 0.003);   // exact at rest even through f16 rounding
    return select(raw, snapped, ok);
}
// in main(): let st = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
//            let glide = glideStep(st, rawMouse, time, 8.0);   // rate ~ old omega
//            ... at the end, for the (0,0) thread only, store (glide, GLIDE_MARK, fract(time)) into A instead of the display texel.
```
Rules: (a) texel (0,0) of A is no longer display data — `writeTexture` at (0,0) stays the real display pixel; (b) every place that READS C as colour/history/sim-state must treat texel (0,0) as masked (use the current value instead): double-exposure `hist`, heat-haze `prev`, zoom-blur `prev` (advected coords can land on (0,0)), fisheye sim neighbour/self reads; (c) keep HEAD's "mouse < 0 → centre" fallbacks; (d) document the (0,0) texel in the `A packing:` line; (e) say in NOTES that this is a first-order glide replacing a dead critically-damped spring, and what the visible change is (at rest: none; moving: lens/epicentre lags ~1/rate s).
If a shader's card says "lag only" (fisheye), keep the droplet at the raw cursor and use `raw - glide` only as the velocity proxy.

## Idea admission + batch de-dup (§12.4) — §12.2 row budget (≤2 files per row unless noted; tactic-derived ideas are unlimited)
- Cauchy dispersion (F): cross-mouse-spec-dispersion-lens (already has it; deepen) and heat-haze-mirage only.
- Soft inverse-square (F), Lens-flare ghosts (F): anamorphic-flare only.
- Brown–Conrady radial (B): cyber-magnifier only.
- Snell vector refraction (F), Damped wave (D), Isotropic 9-point Laplacian (D): interactive-fisheye only.
- cos⁴ vignetting (A): double-exposure only. Halation / H&D curve / density grain (A): not used in this batch.
- Structure-tensor / edge orientation (A): ascii-lens only.
No two files in the batch share both formulae. Every idea: same-noun / deletion / expert tests (§12.1) — they are answered per shader in BRIEFS.md; keep to them.

## Deliverables per fork
1. Edited WGSL + JSON (headers with `Ideas:` / `A packing:`), 2. `NOTES-<fork>.md` with, per shader: kept verbatim, A packing, ideas with line refs, rescues with line refs, default-look change (yes/no, meanL/stdL HEAD→new from the harness), formula names, gate results (Naga, precommit gate, dead-slider check, renders at 192 + 576 incl. moved/held cursor and audio; long-run 200+ frames for the fisheye sim), open items. 3. Final message ≤15 lines per shader: ideas, rescues, anything unsure. Never claim visual QA on a real GPU — harness PNGs are SwiftShader structural proof only.
