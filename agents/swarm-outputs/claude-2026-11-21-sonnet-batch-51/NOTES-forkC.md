# NOTES — fork C (alucinate, generative-psy-swirls)

Harness = `agents/mr_c_abs.mjs` / `mr_ab.mjs` (patched by the coordinator to re-zero extraBuffer[133..255] per frame), SwiftShader, 192² renders, 256² timing, SRC=img for alucinate. **No visual QA claimed; real-GPU look is external.** Box load average was 42–55 during timing.

## alucinate (first pass; no lost version in history)
- **KEEP VERBATIM:** 4 sliders/roles; domainWarp/fbm/conformalMap/grayScott bodies; IFS constants and 5 iterations; R/G/B tap structure; rainbow mix; gamma; depth shade; alpha; depth pass-through; A = (a, b, gradient, diffusionRate).
- **ADD (3):** (1) mirror-cell chirality, fold count as material §12.2E — `kaleidoscopeIFS` counts `step(z,0)` reflections, parity flips the axis-fixed chromatic offsets on mirrored facets (`chirality`, `abC`); (2) IFS orbit-trap filigree §12.2E — `trap = min |‖z‖−1|` → `vein = exp(−20·trap)` lifts the rainbow value (×1.3) and mix (+0.25); (3) Turing-cell lenslets (tactic 7) — forward-difference ∇a of the same analytic grayScott (+2 evals) displaces R/B taps by ±`lens` along the cell edge normal.
- **Rescues:** R1 click clock: `rt = (config.x − ripple.z)·0.5` gated 0..4, count capped 50 (HEAD: a click at t=10 turned the whole picture into border-clamped concentric noise until t=20; verified before/after); R3 A.z is now the true |∇a| (was `length(vec2(a,b))`).
- **A packing:** raw field (a, b, |∇a|, diffusionRate), no reader in this file (still unread — changing z cannot break a reader here; a downstream reader of A.z, if any, now sees a real gradient).
- **Ablation (full vs without, 192², t≈10):** veins 53.5 % px differ, chirality 44.7 %, lens 67.6 %; full vs HEAD 93 % (mean|d| .055). Clamped luma mean/std: HEAD .553/.106, new .584/.114 (1.2 % px ≥ .99).
- **Stress (nan 0 each):** sliders all 1, all 0, held pointer, audio 1/1/1, two clicks at t≈10, t=300.
- **Timing (interleaved, paired medians, 4 rounds): 1.09, 0.83, 1.12, 1.07 → ~1.08× HEAD.** Low confidence (load 42).
- **Gates:** precommit 1/1, verify-naga-wasm OK, dead sliders 0, extraBuffer pass.
- **OPEN CALL — ACES not added.** The catalog fit cuts this high-key remix's clamped luma std .12 → .07 at any exposure (a lower exposure only darkens it). The user left chrono-erosion's ACES as a call in batch-47; same here. Consequence: the `upgraded-rgba` tag stays an over-claim. One line (`color = acesToneMap(max(color, 0))`) re-adds it.
- Over-claim only: `reaction-diffusion` tag — there is no RD state (analytic Gray-Scott-style function). A real solver would replace the kaleido-tied pattern → fails §12.4, not done.

## generative-psy-swirls (SALVAGE of batch-28 9acc4b18 + 2 new ideas)
- **KEEP VERBATIM:** 4 sliders/roles; arm × ring, HSV layer fn, hue drift, mids hue fan, treble/bass nudges, fbm warp, layer offsets, click ring (cap 50, 1.7 s), trail memory (4 % + mids, clamp 1.2, tint), relief depth, coverage alpha, ACES(color·1.1).
- **ADD (4):** 1 arm-wound hue and 2 Rankine eye-wall (**salvaged**, unchanged code); 3 Lamb-Oseen core wring §12.2E (`coreProfile`, `surgeR/G/B`, `wring` into `wound`); 4 per-channel flow lag (±0.6 s, Ω = 0.55). Idea 3 uses a [2/2] Padé form of (1−e^−s)/s (within 3 % for s ≤ 3): no exp/sqrt/0÷0.
- **Rescue (salvaged):** glide in A(0,0) replaces the dead extraBuffer spring. Verified: moving pointer 74 % px differ from raw, at rest 0 %.
- **Audit of the lost version:** clean (see BRIEFS amendment). Integration fix mine: hue uses `wound` incl. the wring so bands follow the sheared arms.
- **A packing:** raw trail colour (clamp 1.2, pre-ACES, C read as colour); texel (0,0) = (glide.xy, 7, fract(time)).
- **Ablation (t = 2.86 / 8.6, defaults):** without hue 74.7 / 76.4 % px differ, without eye-wall 11.9 / 12.2 %, without wring 91.4 / 87.7 %, without lag 17.7 / 13.4 %; full vs HEAD 93.3 / 85.7 %.
- **Stress (nan 0):** defaults, all-1 / all-0, audio 1/1/1, clicks, held pointer sweep, t = 3600 and 100000.
- **Timing, 4 variants interleaved:** salvage-only ≈ 1.1–1.2× HEAD (1.28, 1.23, 1.08, 1.09 and .92, 1.17, 1.12 in two sets); merged ≈ 1.1–1.3× (1.13, 1.21, 1.04 pre-Padé; 1.15, 1.23, 1.14 with Padé). **Borderline vs the 1.3× cap and noisy (load 42–55): coordinator should re-time on a quiet box.** The salvage alone is most of the cost.
- **Gates:** precommit 1/1, verify-naga-wasm OK (2/2 with alucinate), dead sliders 0 (3 defs incl. psy-swirls), extraBuffer pass.
- **Not changed / for the user:** `psy-swirls` preset shares the WGSL with mismatched slider names (x default 1 = full twist); `sprung-mouse-vortex` tag now describes a first-order glide; `invLayers = 1/layers` still divides by the float count (≤14 % dimmer at fractional counts); the darkness (meanL ~.24) is design (arm·ring product), not changed.

## Engine note (out of scope)
`writeExtraBuffer` zeroes extraBuffer[133..255] every frame (222 shaders use it). Not touched.
