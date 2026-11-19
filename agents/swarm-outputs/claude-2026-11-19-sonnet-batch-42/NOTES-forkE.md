# NOTES — fork E

## gen-de-jong-attractor (second pass)
- KEEP VERBATIM: 6 earlier ideas untouched; header `Upgraded: 2026-10-10, 2026-11-19`, Ideas line appended. A packing unchanged (density, hue phase, tube depth, alpha).
- Rescue 1 (confirmed at HEAD): zero-density plane painted the full palette → flat saturated-blue floor (meanL .408 nearly all floor), lace faint specks. Density colour now scaled by `0.06 + 0.94·density` (L263-264).
- Idea 7 Log density tone (§12.2 density-histogram log tone), L257-259: `log(1+3000·acc)/log(3001)` replaces `clamp(acc·10)`. Ablation 192/90 frames: 66.9 % px, mean|Δ| .048. Also lifts alpha/depth (they read `density`).
- Idea 8 Lyapunov shadow-orbit tint (native), L152-155, L187-191, L265-268: twin orbit ε=1e-3, renormalised each step, g-weighted mean log-stretch (FTLE) → hot/cool tint on the lace. Ablation 192/90f: 12.3 % px, mean|Δ| .004. (At 30 frames, before the lace fills in: 0.5 %.)
- Look: HEAD idle meanL .408/stdL .040 → new .165/.157 (90f); dark field, visible lace disc + critical-curve lines + tube. Held/audio paths unchanged.
- frameMs ratio (load 42, interleaved 4 rounds): 2.08/1.29/1.19/1.15 → median ≈1.24×. Cost is the shadow orbit (one extra de_jong + log per of 128 iterations). Under 1.3× but noisy; coordinator re-time.
- 576: not re-ablated (SwiftShader 576 at 90 frames is too slow on this load); HEAD 192 vs 576 meanL identical, behaviour is resolution-independent.
- Gates: precommit pass, naga-wasm pass, dead-sliders PASS, extrabuffer PASS.
- Open: extraBuffer[133..138] mouse spring never persists (zeroed per frame) → behaves as raw mouse; harmless, left. 

## gen-velocity-bloom (first pass)
- Header: `Upgraded:` appended `, 2026-11-19`; added `Ideas:` and `A packing:` lines. JSON has `params: []` (x-meta defaults 0.3,0.7,0.5,0.85 used) → host shows no sliders; audit blind spot as per memory.
- Rescue 1 (confirmed): velocityField diffed the source against C.rgb = previous accumulated BLOOM, so "velocity" was high everywhere on a still image (HEAD meanL .794, alpha .926, whole frame blooming). A.a (HEAD hard 1.0) now stores source luma; velocity uses |Δluma|·1.7 (L63-66). New idle meanL .706, alpha .801 (bloom now on edges/motion only). A packing: rgb trail, a prev source luma.
- Idea 1 Doppler streak fringe (native), L119-128: anamorphic streak R weights leading half, B trailing half, split ∝ velocity. Motion-gated: on a still source 0.2 % px; with a 1-frame motion step (SEEDC=0 prev luma) 63.5 % @192, 63.1 % @576, mean|Δ| .018.
- Idea 2 Cooling afterglow (native), L229-232: carried trail ×(0.9,0.96,1.05) per frame before decay → old trails go blue. Still source 30f: 9.8 % px; seeded-trail decay (SEEDC=1,1,1,.5, 8f): 26.8 %, mean|Δ| .013.
- Held/audio: held .723, audio .967 (bass bloom pump, HEAD behaviour). nan 0 everywhere.
- frameMs (load 42): 1.61/1.12/1.13/0.84 → median ≈1.13×.
- Gates: precommit pass, naga-wasm pass, dead-sliders PASS, extrabuffer PASS.
- Open/not fixed: click "spring" in extraBuffer[133/134] never persists → acts as a held-mouse glow (still visible); `fftLow` reads extraBuffer[6..8], not a sanctioned audio source — left alone. Filter of the source despite gen- category.
