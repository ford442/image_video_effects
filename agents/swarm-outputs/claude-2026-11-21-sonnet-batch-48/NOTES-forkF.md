# NOTES — fork F (sonnet/batch-48): conv-guided-video-filter

Second pass (HEAD `Ideas:` = "depth-augmented guide; exact integer C loads for P", `Upgraded: 2026-09-08`). Cards + interrogation: `BRIEFS-forkF.md`. Files touched: `public/shaders/conv-guided-video-filter.wgsl`, `shader_definitions/image/conv-guided-video-filter.json` (description only). Nothing committed.

## What the file is, and what stayed verbatim

Previous pass's output (dataTextureC = P) re-fitted to the crisp source frame (guide G = `mix(luma, depth, 0.35)`) by the He et al. local linear model `q = a·G + b` over a (2r+1)² box; mouse proximity shrinks r→1 and ε→0.05ε.
KEEP VERBATIM (unchanged lines): box window and the five accumulators (sumG/sumP/sumGP/sumG2/count), vec3 `a`/`b`, exact integer C load addressing (`ic`), guide mix 0.35, param mapping (`rad`→r 1..8, `eps`→ε 0.0002..0.08, `guide strength`→`mix(P, guided, z)`, `mouse strength`→`exp(−d²·10)` focus), `bass`→`ε·(1−0.2·bass)`, `mids`→`1+0.15·mids`, `acesToneMap`, confidence α = `|a|·2` → `0.75·conf + 0.25·src.a`, depth pass-through, dataTextureB untouched, no spring/ripple/palette. Saved `params`, `features`, `x-meta` byte-identical (verified by diff against `git show HEAD:`).

## Ideas actually in the diff (grep `// ── Idea`)

1. **Edge-aware ε weighting — weighted guided filter Γ (§12.2A guided-filter row).** `sumG3/sumG32` accumulate the 3×3 sub-window of the same taps inside the existing loop (no extra fetches); after the loop `Γ = clamp((σ₃·σ_R + 1e-5)/(0.0012 + 1e-5), 0.5, 4)`, `ε_eff = ε/Γ` feeds `a = cov/(varG + ε_eff)`. Flats ≤ ε×2 (smoother), edges ε/4 (a→1). `eps` keeps its role as the base regulariser.
2. **Guide-gated anti-halo envelope (§12.2A anti-halo row, joint-range variant).** `minP/maxP` (per channel) over the window taps whose guide is within `τ = clamp(2·√ε, 0.06, 0.30)` of the centre guide (the pixel's side of the edge); `q = clamp(q, minP − allow, maxP + allow)`, `allow = 0.01 + 0.5·ε`. Centre tap always passes the gate, so `minP ≤ maxP` is guaranteed (no undefined `clamp`).

Third idea considered and dropped (BRIEFS): edge-tangent guide smoothing from the 3×3 Sobel orientation — visually ≈ 0 on a smooth video guide for +4 loads/pixel. The fork-claimed structure-tensor row is therefore **not used**.

## Rescues (HEAD defects, found by rendering HEAD — LOUD)

- **R1 — black-forever on empty C.** HEAD with C = 0 (slot 1, first frame, after a shader switch / device loss) renders pure black *forever* (meanL 0.000): P = 0 → a = b = 0 → q = 0 → A = 0 → C = 0. Now `useSrc` (per pixel, `max(C.rgba) ≤ 1e-5`) swaps the source tap in for P, so an empty previous pass degrades to the classic self-guided edge-preserving smoother. Any non-zero C is untouched. **This changes the default look only in the empty-C case (black → picture).**
- **R2 — negatives into ACES.** `a·G+b` can dip below 0 and the catalog ACES fit maps negatives bright; `guidedLin = max(…, 0)` before `acesToneMap`.
- **R3 — A packing / ACES inside the feedback loop.** HEAD stored the ACES'd display colour in A, which is re-read next frame as P. Self-fed (slot 1) that contracts to ACES's fixed point: with only R1 applied, 40 frames → meanL 0.728, **stdL 0.002 (flat grey)**. Now A = **pre-ACES** guided state + confidence α; `writeTexture` keeps HEAD's exact display formula `mix(P, ACES(q), guideStr)`. Same scratch run with the un-ACES'd state: stable (stdL 0.145 at frame 40). In the chain case the display is formula-identical to HEAD; only what a *later* slot reads from C is no longer double tone-mapped. **Open call for the coordinator: this is a change to what A holds (header `A packing:` line updated).**

## A packing

`writeTexture`: ACES display RGBA, semantic α (confidence). `dataTextureA`: pre-ACES guided colour (display-range, upper end left unclamped so HDR P survives) + the same confidence α. B untouched. C read as colour P with exact `textureLoad`.

## Measured diff vs HEAD (SwiftShader, 256², chain case = C seeded with a posterized / 5×5-blurred / channel-rotated copy of the source and held fixed; textured source = oriented gratings + noise + speckle)

| Case | RGB px differing >1/255 | >4/255 | >16/255 |
|---|---|---|---|
| default params, smooth synthetic image | 2.0% | 0.7% | 0.00% |
| default params, textured source | 36.2% | 3.4% | 0.11% |
| eps = 0.04, smooth image | 8.2% | 1.2% | 0.04% |
| eps = 0.04, textured | 67.4% | 18.6% | 0.54% |
| eps = 0, textured | 46.1% | 28.1% | 3.79% |

Honest read: at **default `eps = 0.3`** the regulariser is large, `a` is small everywhere and the envelope essentially never binds (0.1–1% of pixels) — the upgrade is *quiet* there (edge/stripe contrast up ~10–20%: max |∇L| across a checker border 0.20→0.24, and the signed diff image shows paired +/− bands exactly on disc rims and grating stripes, flats unchanged). It is clearly visible from `eps ≲ 0.15` and with larger radius, which is where the guided filter's halo/noise-leak problems actually live. Confidence α changes on ~57% of pixels (textured) because `a` is now edge-weighted. No NaN in any run.

Γ distribution on the textured source at defaults: 17% on the ½ floor / 28% mid / 29% in (2,4) / 27% on the ×4 ceiling; on the very smooth synthetic image 96% sit on the floor (so Γ ≈ "ε×2" there). First draft (χ_ref 0.004, floor ¼) put 96% of the smooth image at ε×4 — recalibrated.

Empty-C / standalone (SRC=img, no seed): HEAD meanL 0.000 stdL 0.000 → new frame 1 meanL 0.490 stdL 0.174; 60 self-fed frames meanL 0.499 stdL 0.147 (textured source: 0.502 / 0.093) — structure kept, fine gratings smooth away (iterated edge-preserving smoothing, a painterly drift, not a collapse).

Other runs (all NaN 0, not blank): mouse down near (0.7,0.3), audio 0.8/0.6/0.3, params 0,0,0,0 and 1,1,1,1.

## Timing (SwiftShader, `forkF_multi.sh`, interleaved HEAD/new, chain-style C, min-of-drained-frames, load average 5)

- default radius (rad 0.4 → r = 3, 128²): HEAD 10.9 ms → new 13.6 ms, **1.248× (min and median, n = 12)**.
- large radius (rad 0.9 → r = 7, 96²): **1.156× min / 1.209× median (n = 8)**.
- Path to get under the ~1.3× cap (box load 15–17 for most of the session, so first numbers read 1.33–1.44×): isolated per-idea cost (R1 ≈ 1.03×, each idea ≈ +0.15–0.2×); tried and **rejected** `if`-gated 3×3 (1.69×), `&` instead of `&&` (no change), `textureLoad` for guide/depth taps (**slower**, 1.67–1.86×), luma-scalar envelope (cheap, 1.17–1.21×, but weakens Idea 2: 15–41% of low-ε pixels differ from the per-channel envelope, up to 0.39); **adopted** per-pixel empty-C test + per-row hoist of the 3×3 gate (pixel-identical output, 1.38×→1.25×).
- The timing box is shared with the other forks; treat ±0.05 as noise. Real-GPU re-time is external.

## Gates (single file)

`wgsl_precommit_gate.py` 1/1 (naga OK, bindgroup compatible, 0 pasted headers, 0 extraBuffer violations) · `verify-naga-wasm.mjs` 1/1 valid · `audit_dead_sliders.py` 0 new (all four `zoom_params` components read by hand: x radius, y ε, z guide strength, w mouse) · `audit_extrabuffer.py` PASS (file uses no extraBuffer) · JSON `params`/`features`/`x-meta` identical to HEAD.

## Header (as written)

`Upgraded: 2026-09-08, 2026-11-21`; `Ideas: depth-augmented guide; exact integer C loads for P; edge-aware ε weighting (weighted guided filter Γ, §12.2A); guide-gated anti-halo envelope (§12.2A)`; `A packing: pre-ACES guided colour state + confidence α (ACES on writeTexture only)`. `Features:` unchanged (mouse-driven, audio-reactive both still true).

## Could not verify / for the coordinator

- No real-GPU visual QA (SwiftShader only); the synthetic "processed C" is my own posterize/blur/rotate stand-in, not a real prior pass.
- At default `eps` the visible change is modest by design (see table); if the user wants it louder at the default, the lever is Γ's range, not new params.
- R3 changes what slot ≥ 3 reads from C (un-tone-mapped instead of ACES'd). Only matters for chains that read this shader's A.
- The `time` local at the top of `main` is unused (HEAD had it; left).
- Helper scripts used: `forkF_multi.sh`, `mr_f.mjs`, `mr_perf_f.mjs` (copied beside this file; they hard-code the scratch path and use `CPROC=1`/`NOFB=1` env flags for the chain-style C).
