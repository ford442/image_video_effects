# COORDINATOR_REVIEW — sonnet/batch-53 (2026-11-22, Sonnet 5.5)

Worktree `/root/iv-sonnet-batch-53`, branch `sonnet/batch-53` from origin/main a3706adc. Five forks (A–E), disjoint files. Briefs: `BRIEFS-fork{A..E}.md`; notes: `NOTES-fork{A..E}.md`; common brief: `COMMON.md`. **Nothing committed.** VM = SwiftShader: structural proof + synthetic-photo renders only, no real-GPU visual QA.

## The user's failure list vs what was actually there

The user wrote "usual failures are missing ACES, plasmaBuffer and the dataTextureC load, and writes to extraBuffer slots like 0 or 10". Measured at HEAD: **zero writes to `extraBuffer[0..132]` in all ten**; every HEAD gate was green (precommit 10/10, naga-wasm 10/10, dead-slider 0, extraBuffer 0). The real defects were (a) **reads of engine slots as parameters** (`volumetric-depth-zoom`: `extraBuffer[0..4]` = bass/mid/treble/reserved/historyHead read as light/ambient/normal/DOF/cameraZ; `neural-raymarcher(-gabor)`: `extraBuffer[0]` bass used raw as a UV offset, `[10]` = FFT bin 5 as a "click"), (b) **dead persistent state** (`gen-velocity-bloom` click energy in `extraBuffer[133..134]`, zeroed every frame), and (c) several wrong **pictures** (inverted edge glow, non-zero-mean Gabor kernel, region-fill specular, posterize that never reaches white, dead shoulder slider). Missing ACES was real on `parallax_depth_layers` / `gen-velocity-bloom` only; `hybrid-sdf-plasma` has a display-referred print output, ACES deliberately not added. `dataTextureC`: only `gen-velocity-bloom` loads it (exact `textureLoad`, was already correct); the others write a dead mirror A or no A.

## Per-file verdict against the Idea Cards

| id | new ideas (pointable in WGSL) | rescues | default picture | timing (interleaved, loaded box) | verdict |
|---|---|---|---|---|---|
| parallax_depth_layers | multiplane head-parallax shear (cursor = viewer's head); head-lamp contact shadow | added display ACES (clamped ≥0) + `upgraded-rgba` tag | meanL 0.365 → 0.491, 99% px change | 0.71–0.93× | PASS; **open call: ACES brightening is large** |
| volumetric-depth-zoom | light-facing rim glint; focal-plane iso-depth contour | engine-slot reads → constants (+ bass pumps light); edge specular was a region fill; Parallax slider dead (uv ÷ res twice); focal sweep `fract` snap → ping-pong | meanL 0.084 → 0.536 | 1.08× | PASS; **open call: old ring overlay left** |
| neural-raymarcher | firing-shell portal; depth-crease occlusion (step-count AO) | audio → `plasmaBuffer[0].xyz`; inverted/misreferenced edge glow → true rim | meanL 0.802 → 0.509, 99.9% px | ~1.03× | PASS |
| neural-raymarcher-gabor | Gabor phase colouring; iso-orientation surround suppression | same audio + rim fixes; even kernel not zero-mean (flat source gave alpha 1); 4 orientations share one 9×9 pass | meanL 0.508 → 0.384, meanA 0.967 → 0.431 | ~0.82× | PASS |
| multi-fractal-compositor | Droste spiral twist; expanding annulus windows | none needed | 84% px (twist), meanL 0.656 → 0.650 | ~1.09× | PASS |
| volumetric-rainbow-clouds | wind shear between slabs; in-cloud lightning (bass-gated) | view vector had no z → specular exactly 0 everywhere (HEAD pixel-identical with spec forced 0); undefined `normalize(0)` at centre | ~10% px (specular alive) + shear/lightning | ~1.09× | PASS (+ `audio-reactive` tag now true) |
| gen-velocity-bloom | signed-motion flare & wake; energy-conserving composite (§12.2F) | click pulse stateless from `u.ripples` (HEAD raced / blocky tiles); ACES on bloom light only (HEAD clipped to white) | 99.6% px, meanL 0.761 → 0.762 | ~0.9–1.0× | PASS; **open call: ACES placement** |
| hybrid-sdf-plasma | plate misregistration (black key plate off the colour plate); ink squash (denser dots at rim) | posterize `floor(c·L)/L` never reached white → `/(L−1)` | meanL 0.292 → 0.334, 87% px | 0.91× / 1.15× (two runs) | PASS |
| tone-histogram | H&D exponential shoulder knee (§12.2A); chroma follows the tone curve | Shoulder slider moved 0.0% px at HEAD → now 20.8% at 0→1 | 3.4% px, ≤ 7/255 | 1.01–1.09× | PASS; **open call: shoulder direction flips** |
| tone-histogram-apply | luma-held saturation/hue stage (1 idea only; two more rejected on the card) | Saturation 0/0.5/1 swung meanL 0.518/0.482/0.446 → 0.499/0.498/0.492 | 28–59% px, ≤ 15/255 | ~1.00× | PASS (1 idea — the pair was upgraded yesterday) |

Coordinator read of the two largest behavioural diffs (gen-velocity-bloom, volumetric-depth-zoom) and the neural-raymarcher rescue: bounded loops, clamped before ACES, no state in `extraBuffer`, exact C load kept, semantic alpha kept, A packings unchanged. No generic spring/ripple/IQ overlay was added anywhere (the click pulse in `gen-velocity-bloom` replaces the file's own dead one).

## Gates (all run by the coordinator on the final tree)

precommit 10/10 (0 extraBuffer violations, 0 pasted headers) · naga-wasm 10/10 · dead sliders 0 new · `audit_extrabuffer` pass · `upgrades:record --ids=` 10 changed · `generate_shader_lists` · `verify:shaders:fix` all 11 gates pass · `npm run build` ok · Vitest 227 files / 2040 passed, 1 skipped. After the gates: discarded regenerated `reports/*` (except `shader-upgrade-ledger.json`) and `public/shader-search-index.json`; kept the six `public/shader-lists/*.json`.

## Corrections to my own brief

- COMMON.md said `multi-fractal-compositor` is the pass-2 partner of `volumetric-rainbow-clouds`. **Wrong.** The batch-51 memory's "compositor" is `prismatic-3d-compositor` (clouds' real next pass). `multi-fractal-compositor` is a stand-alone zoom tunnel of the input photo. Fork C caught it; it changed nothing in the work.

## Open calls for the user

1. **parallax_depth_layers ACES** lifts the default picture (meanL +0.126). If the photo's tonality should stay, swap for a highlight-only shoulder.
2. **volumetric-depth-zoom** still has the old `clockRings` / `clickFront` rainbow overlay (concentric tinted rings on every pixel). It is the generic stamp §4 forbids; with the photo restored it reads as rings over the picture. Left in place — removing it is a look decision.
3. **gen-velocity-bloom ACES placement:** bloom-light-only (shipped) vs whole-frame (capped whites at 0.80 and greyed the photo; kept in fork E's scratch as `vb_variant_a.wgsl`). Also: no bright-pass, so a blurred copy veils the frame at default intensity (the original look, not redesigned); first frame after load flashes (HEAD too).
4. **tone-histogram Idea 5 flips the Shoulder direction** (lift → roll-off): saved presets with Shoulder > 0 render highlights slightly dimmer. Drop Idea 5 if the old behaviour is wanted.
5. **tone-histogram-apply.json** still declares `multi-pass-2` / `multipass.prevShader: "tone-histogram"` although the shader builds its own histogram; chained after tone-histogram it double tone-maps. Registry decision, not changed.
6. **neural-raymarcher(-gabor):** catalog depth is 1 = near but both fog with `exp(-depth·…)` (nearer = foggier; in gabor the `glow` default fades near objects to navy) — one-line flip per file. `neural-raymarcher` slot roles (`camera_rotation` is really fog density, `network_depth`/`activation_vis` are layer speeds) left alone since saved params are byte-exact. Zoom sawtooth pops every 1/speed seconds (a crossfade would double the march). Gabor kernel capped at ±4 taps while σ reaches 4.
7. **volumetric-rainbow-clouds:** a mouse-down click instantly doubles the perspective (`zoom_config.w` used as a continuous value); density is `abs(fbm)` (black marble veins). Both left.
8. **hybrid-sdf-plasma** slider names are stale ("Plasma Detail" etc. actually drive dot size / edge threshold / posterize / ink density); not renamed (saved params byte-exact).
9. Timing was taken on a box at load 10–45 (another session's Playwright jobs); all ratios ≤ ~1.15× but a quiet-box re-time is still owed. Real-GPU look and thumbnails (`thumbs:generate -- --stale`) are external.
