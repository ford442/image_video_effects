# COORDINATOR_REVIEW — sonnet/batch-52 (temporal + audio-reactive post-processing ten)

Worktree `/root/iv-sonnet-batch-52`, branch `sonnet/batch-52` from origin/main a3706adc. Uncommitted. Forks A–E per COMMON.md; each wrote BRIEFS before editing (briefs and notes present, 5 + 5 files). VM = SwiftShader: **no real-GPU visual QA was done**; structural gates and harness renders only.

## Gates (coordinator, whole batch)

precommit 10/10 · naga-wasm 30.0 10/10 valid, 0 new · dead-sliders 0 new · extrabuffer PASS · `verify:shaders:fix` all 11 gates pass · `upgrades:record` 9 `upgraded` + 1 `fixed` (layered-time-stamps) · `npm run build` ok · Vitest 2038/2041 pass, 2 fail in `src/__tests__/RendererManager.test.ts` in the full parallel run (box load ~3.7) and 56/56 pass alone; no TS touched by this batch (known load flake, same file as batch-51 notes).

Quiet-box timing (load ~3.3, `mr_ab_hist.mjs`, 160 px, 16 cycles, paired median NEW/HEAD): freq-decomp 1.16 · pyramid 1.08 · flow-tracer 1.12 · zoom-tracer 1.05 · decay-multires 1.17 · dispersion 1.14 · rgb-ghost 1.04 · 3d-conv 1.15 · layered-stamps 0.93 · slit-scan 1.00. All under the 1.3× cap. (min-ratio outliers 1.23–1.25 on freq-decomp/zoom-tracer are single-sample noise.)

## Per file

| id | verdict | new ideas (§12.2 row) | rescues | A packing | tags |
|---|---|---|---|---|---|
| temporal-frequency-decomposition | PASS, 1 idea (judgement call) | DC-detrended DFT, same 7 taps | static leakage (Hann 8-sample leaks 29 % of a still pixel at default; HEAD tinted the frame orange + red lens blob); dead `plasmaBuffer[1..8]` voices → real FFT bins; lens `pow` ghost → dead-zone sharpen; ACES on emitted glow only (verified clamped ≥0) | unchanged | kept `upgraded-rgba` (ACES on glow) |
| spatio-temporal-3d-conv | PASS | linear-light shutter integration (motion-blur mode); noise-gated temporal coring (sharpen mode) | motion-blur `mix` extrapolated past 1 at p4=1 + loud bass (meanL −3.59) → trail weight capped 0.95 | unchanged | dropped `upgraded-rgba` |
| optical-flow-tracer | PASS, 1 idea | comet taper + continuous Trail Age (was a 5-step stair; dead `t` now used) | none | raw flow, unchanged | dropped `upgraded-rgba` |
| temporal-feedback-zoom-tracer | PASS (see open call 3) | keystone camera tilt; auto-exposure loop gain (spot meter, loop gain ≤ 0.93) | clock-ring/spectral phase multiplied absolute `time` by audio → rings re-scrambled late in a session (11× at t=60 s) → bounded phase offset | display RGBA, unchanged | dropped `upgraded-rgba` |
| temporal-decay-multiresolution | PASS | scale-coupled timescales (older ages read at growing tap offsets); temporal band-pass glint (gated on real frame change) | `plasmaBuffer[1..8]` never uploaded → real FFT bins (invisible, 0.1 % px) | unchanged | dropped `upgraded-rgba` |
| temporal-layered-time-stamps | PASS (rescue only, no `Upgraded:` bump) | none (saturated, fifth idea rejected) | onion outlines were a feedback loop (ring holds own output → ink re-detected one px wider per frame; noise by frame 24); now edges from a clean source-luma ring | **display RGBA → 4-age clean-luma ring in A/C** (exact `textureLoad`) | dropped `upgraded-rgba` |
| audio-reactive-pyramid | PASS | across-edge fine band (oriented-edge boost); pitch-slid band scales (spectral centroid ±30 %, identical to HEAD at silence/flat) | none | display RGBA | none |
| audio-reactive-rgb-dispersion | PASS | blue defocus / purple fringing (4 blue taps, own reach); r³ lateral CA (Brown–Conrady k₁, §12.2B, owned) | uv-space offsets → fringe size depended on direction (16:9: 1.316 px vs 2.340 px); now equal, square canvases bit-exact | display RGBA | none |
| temporal-rgb-ghost | PASS (largest look change) | highlight-weighted comet; held-pointer time focus (G/B delays collapse in a cursor lens, local to r<0.5) | ring holds own output → gain ≈ 1 feedback: HEAD whites out (blend 0.8 × boost 1.25) or blacks out (vignette re-read each frame); coordinator re-verified: HEAD static 120 f meanL 0.459 / stdL 1.451, NEW 0.332 / 0.123. Vignette now scales only ghost deviation; bounded lift; tube-lag leak keeps gain ≤ 0.96; fringe compares luma | display RGBA | dropped `upgraded-rgba`; `mouse-driven` now true (pointer lens) |
| chrono-luma-slit-scan | PASS | runner wake (sawtooth tail); long-exposure integration for deep ages | none picture-level | display RGBA | dropped `upgraded-rgba` and unearned `fast-motion` (bulk commit 07a46977, no brief); added `mouse-driven` |

§12.4 de-dup: only one §12.2 row used in the whole batch (Brown–Conrady on dispersion, owned); anti-halo, Cauchy, Schmitt etc. left as at HEAD / unused. No generic overlay shared between files, no new springs, no `extraBuffer` writes anywhere, saved `params` byte-exact on all ten.

## Verified by coordinator (not just forwarded)

`temporal-rgb-ghost` HEAD instability (static 120 f and moving 40 f renders); before/after pictures for `temporal-frequency-decomposition` (HEAD red blob → clean, blinkers detected) and `temporal-layered-time-stamps` (HEAD full-frame noise at 40 f → clean spiralling onion outlines); ACES clamp in freq-decomp; quiet-box timing for all ten; gates and ledger.

## Open calls (user)

1. **P-ACES tag removal.** 7 of 10 files lost the unearned `upgraded-rgba` tag (WGSL `Features:` and JSON `features`) instead of gaining ACES on the photo path, which would regrade every image. Only freq-decomp keeps it (ACES on the emitted glow). Reverse only if you want ACES on the photo path.
2. **layered-time-stamps A repack.** Clean-luma ring in A/C (outlines of where things *were*) vs tracing the live frame's edges (no C read, loses that). Fork chose the ring. New default is darker/greener than the source on the harness scene; eyeball on a GPU.
3. **zoom-tracer default.** The always-on rainbow clock-ring overlay (predates this pass) dominates the default picture and hides the tunnel and bezels; the new keystone tilt is subtle under it (71 % px, mean Δ 0.015 at silence). Removing or gating the overlay is the largest available improvement and was left alone.
4. **freq-decomp ships one idea.** The second (spectral purity → glow saturation) was built, measured (8 taps cannot separate tone from noise: noise median 0.68–0.74 vs tones 0.37–0.74) and dropped; measurements in BRIEFS-forkA.
5. **rgb-ghost default comets are subtle** after the rescue (displace 0.8 + g_delay 0.3 gives vivid cyan comets); a bolder default means raising the leak floor or lift coefficient. Also 100 % of pixels differ from HEAD by design (rescue).
6. **Default looks change** on: freq-decomp (100 % px), rgb-ghost (100 %), layered-stamps (noise → clean), dispersion (16:9 only, non-horizontal fringes), decay-multires (33.5 % px).

## Follow-ups outside this batch

- **63 other catalog shaders read `plasmaBuffer[1..8]`**, which the engine never uploads: their per-region audio is dead (Fork A). Engine decision (upload them) or per-shader rescue.
- optical-flow-tracer accuracy collapses with speed (rms 0.7 px @ 1.1 px/frame, 2.1 @ 3.4, 8.7 @ 6.7); batch-46's solver, no cost headroom.
- `extraBuffer[133..255]` zero-per-frame is still an engine decision ([[project-sonnet-batch-51]]); decay-multires' and freq-decomp's `[133..138]` pointer spring is dead (pixel-identical to raw mouse), left as is.
- Stock `agents/mr.mjs` cannot exercise history-ring/FFT shaders; use `agents/mr_hist.mjs` / `mr_ab_hist.mjs` (gitignored here; copy before reuse).
