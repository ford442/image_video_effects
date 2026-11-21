# NOTES — fork D (data-moshing-diffusion, vortex-distortion)

Baseline = the worktree file at fork start (origin/main 2e876e2e; both already `#include "_prelude.wgsl"`, no migration needed). VM = SwiftShader, `agents/mr.mjs` 3-panel PNG, left panel compared; "changed" = % of pixels with max-channel |Δ| > 0.02 unless stated. No real-GPU visual QA claimed. Nothing committed.

---
## data-moshing-diffusion  (2nd pass)

**Idea Card (as in BRIEFS):** ADD 1 macroblock motion carry (§12.2B); ADD 2 isotropic 9-point diffusion stencil (§12.2D).
**KEEP VERBATIM (verified by diff):** 4 params and roles; Fp128 offset accumulation + 0.96 damping + ±0.5 clamp; conveyor history load; mouse swirl/held weighting; packet force; ripple fronts; Perona–Malik `exp(-(g/κ)²)` coefficient; existing tangentDiffusion weighting on N/S/E/W; `avgCoeff = (cN+cS+cE+cW)/4` (so alpha is unchanged); trail mix; packetWake; ACES on display only; A = `(offset.xy, 0, alpha)` raw sim, not tone-mapped. `params`, `x-meta`, `features` byte-identical; only `description` extended.
**A packing:** raw sim (offset.xy, unused, alpha) — unchanged. Idea 1 changes what is *read* (history pulled toward the block-centre vector); the stored field is still read as a field next frame.

Where the ideas are in the diff (`// ── Idea n` comments):
1. **Macroblock motion carry** — `blockPx = max(8, res.y/48)`, `blockCentre`, `blockMV = textureLoad(C, blockHist).xy`, `offset = mix(pixelHist, blockMV, clamp(quantize*1.2, 0, 0.9))`. Weight rides the Quantize role: 0 at quantize = 0 (HEAD look), 0.36 at saved default 0.3, 0.84 at 0.7. Visible as a block lattice in the smear trail and cleaner packet streaks (HEAD's sawtooth is averaged per block).
2. **Isotropic 9-point stencil** — 4 taps hoisted out of the loop (loop-invariant; HEAD refetched them per iteration) + 4 diagonal taps; weights 0.8 axis / 0.2 corner (total 4.0 = HEAD's 4×1, so overall diffusion rate unchanged); corner coefficients = Perona–Malik of the corner gradient × `(1 + 1.4·|t·d̂|)` — HEAD's contour-tangent weight extended to the diagonals (t from the same `gradVec`).

**Rescue R1:** `quantize` ≥ 0.947 gave < 2 levels (at 1.0, `floor(c*1)/1 = 0`): the slider maximum rendered near-black (HEAD meanL 0.084 @ quantize 1, default 0.480). Now `max(q, 2.0)` → meanL 0.231, still strongly posterized, not black. Default (q = 15) unchanged.
**Free fold:** one `textureSampleLevel(...).rgb` instead of three identical ones (verified 0.0% diff).

**Diff vs baseline (pixels):** default (q 0.3, mouse still) 15.3 % changed (meanAbs 0.0109); pointer path + 2 clicks 30.1 % (0.0195); q 0.7 + pointer 34.7 % (0.0387); **quantize 0 → 0.0 % (meanAbs 0.0001)** = Idea 1 off, Idea 2 alone. **Honest read:** Idea 1 is the visible one. Idea 2 is a quiet kernel refinement: on the high-frequency `SRC=tex` source with diffusion maxed (smear 0, κ 0.8, dt 1) only 0.8 % of pixels exceed 0.02 (max Δ 0.047); the amplified diff lights up along gratings of all orientations (incl. the 45°/135° ones), i.e. it does what it says, it is just subtle at 1-px taps.
**Timing (mr_ab, 512², interleaved, paired-median vs baseline):** before the tap fold 1.20 / 1.14 / 1.23; after the fold 1.13 / 1.24 / 1.09 / 1.05. Loaded box; cap ≤ ~1.3× holds.
**Gates:** precommit 1/1 (extraBuffer 0, pasted headers 0), naga-wasm 1/1, dead sliders 0 new (all 4 `zoom_params` read), audit_extrabuffer pass, NaN 0 on every render.
**Not verified:** real-GPU look/perf; block size feel at > 1080p (block = res.y/48, so ≥ 8 px, ~22 px at 1080p); behaviour on real photos with fine texture (only synthetic sources here).

---
## vortex-distortion  (2nd pass)

**Idea Card (as in BRIEFS, with the amendments in BRIEFS-forkD.md):** ADD 1 vorticity confinement (§12.2D); ADD 2 MacCormack round-trip correction of the backtrace (§12.2D, trajectory form).
**KEEP VERBATIM (verified by diff):** 4 params/roles (Γ signed, ν, KH, aberration); `lambOseen`, `khPerturbation`, ripple vortices (alternating sign, `exp(-0.3 age)`, cap 20); vel·0.04 displacement; 4-tap streamline smear (tap 0 now shared with sG); source-tied vorticity overlay, glow, semantic alpha; A = `(vel.xy, vorticity, speed)` raw, never ACES'd; HEAD's A.z "vorticity" (= |v|·sign Γ, a pseudo-vorticity) left as documented. `params`, `x-meta`, `features` byte-identical; only `description` extended.
**A packing:** raw field (vel.xy, vorticity, speed) — unchanged semantics. `vel.xy` now includes the confinement term. C is now READ (exact `textureLoad`, `.xy`/`.w`) — the shader already owned this history (it writes A every frame) but never read it; the `temporal` feature tag is now true.

Where the ideas are in the diff:
1. **Vorticity confinement** — `lambOseenOmega` (closed form `ω = Γ/(π rc²)·e^(−r²/rc²)`, `∇ω = −2dω/rc²`, promoted from the Gaussian lambOseen already computes), accumulators Σω, Σ|ω|, Σ|ω|·rc, Σ∇ω over the same vortices, `Δv = ε·|Σω|·h̄·(ĝ.y, −ĝ.x)` with `ĝ = ∇ω/max(|∇ω|, 2|ω|/h̄)` and ε = `mix(0.1, 0.35, viscosity)`. Per vortex a Gaussian core spin-up (~ +20 % at r = rc at the saved viscosity; far-field circulation unchanged; Γ = 0 ⇒ nothing); because ĝ comes from the SUM, overlapping click vortices bind.
2. **MacCormack backtrace correction** — `histY = textureLoad(C, px(uv+uvOff))`, `uvOffY` from it, `uvBase = uv − uvOff + ½(uvOffY − uvOff)` (length-bounded to ½|uvOff|). To first order the RK2 departure point `x − v + ½(∇v)v`; for a rotation it cancels the outward Euler drift. Frame 0 / cleared C ⇒ exactly the Euler point (verified 0.0 % diff).

**Rescue R1:** the mouse vortex used `age = time*0.1` on the app's global clock, so `rc = sqrt(4νt)` grew without bound: at T0 = 300 s the Γ = +6.4 pointer vortex was a faint smudge. Now `burgersAge(t) = (1 − e^(−0.8t))/0.8` (axial-strain-arrested core, a = 0.4; saturates at t_eff 1.25, ≈ HEAD for t ≲ 0.5), also used for the KH `coreR`. At T0 = 300 the swirl is back at its t ≈ 12 s strength (99.9 % of pixels differ from HEAD there — that *is* the rescue). At T0 = 0 (2.4 s) R1 alone moves 0.9 % of pixels.
**Left, flagged:** JSON default `circulation` = 0.5 ⇒ Γ = `mix(−8, 8, 0.5)` = 0, so at the JSON defaults the shader is an image + chroma fringe (HEAD and new differ by 0.1 %, max Δ 0.004). It is a signed-slider zero detent and the app ships `shaderDefaults.ts` `[0.45, 0.45, 0.55, 0.40]` (Γ ≈ −0.8), so I did not change the mapping (it would break saved presets). Coordinator call if the JSON default should move off 0.5.
**Free fold:** smear tap 0 == sG texel, fetched once (0.0 % diff).

**Diff vs baseline (pixels, SwiftShader, 384²):** app default sliders `[.45,.45,.55,.40]` 2.9 % (meanAbs 0.0029); strong Γ 0.9 + 3 ripples + moving pointer **43.2 %** (0.0329): MacCormack alone 41.8 %, confinement alone 9.2 %, R1 alone 0.9 %; T0 = 300 → 99.9 % (R1); JSON default (Γ = 0) 0.1 %.
**Timing (mr_ab, 512², strong Γ, paired-median vs baseline):** 1.04 / 1.24 / 1.07 / 1.32 / 1.34 (median ≈ 1.24×, noisy box); the no-ideas control sits at ≈ 0.92–1.07. Cost comes from the dependent `textureLoad(C)` + the extra `exp` per vortex; at Γ = 0 the history is skipped (velocity ≈ 0). Not measured with 20 live ripples: expect the per-ripple `lambOseenOmega` exp to add ~ 15–25 % to the vortex loop.
**Gates:** precommit 1/1, naga-wasm 1/1, dead sliders 0 new (4 sliders read), audit_extrabuffer pass, NaN 0 on every render.
**Not verified:** real-GPU look/perf; behaviour with a fast pointer jump (C is one frame stale; the correction is bounded to ½ the Euler step, but I did not render a teleporting pointer); real-photo content. A faint 1-texel "eye" pin-dot at the exact vortex centre pixel exists at HEAD too (v = 0 there by HEAD's `r < 0.0001` guard) — not introduced here.

---
## Process notes for the coordinator
- `scripts/wgsl_precommit_gate.py`, `audit_dead_sliders.py`, `audit_extrabuffer.py` regenerated `reports/dead_sliders_audit.{json,md}`, `reports/extrabuffer_write_audit.json`, `reports/wgsl_precommit_report.json` (shared files, other forks' runs touch them too) — discard per §8c, I did not revert them (no `git checkout`).
- Formula rows used: data-moshing §12.2B macroblock motion carry + §12.2D isotropic 9-pt; vortex §12.2D vorticity confinement + §12.2D MacCormack (trajectory form). No row appears on another file in this fork. No spring/ripple/IQ overlay was added to either file.
- Scratch (renders, variants, `tools/pdiff.py`): `/tmp/claude-0/-root-image-video-effects/2b7775f4-9af2-40c8-a5e7-7ac04b08ac66/scratchpad/d/`.
