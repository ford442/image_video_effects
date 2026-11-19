# NOTES — fork B

## nebula-gyroid (first pass)
- HEAD is NOT a raymarch: 5-layer recursive zoom of readTexture around the cursor. Identity kept. JSON description ("raymarched gyroid SDFs") was false → rewritten (+10 chars), `raymarched` removed from features (provably false). Tags `raymarch`/`sdf` left (tags not in my remit to prune; coordinator may drop).
- Header added: banner, `Upgraded: 2026-11-19`, `Ideas:`, `A packing:` (alpha = fog/fresnel coverage, unchanged).
- Rescue 1 (L240, confirmed by reading audioDepth.ts layout): `chroma = extraBuffer[0]` = bass → split dead at idle, ~0.8 UV shift loud. Now `0.006 + bass*0.014`.
- Rescue 2 (L172, confirmed): `clickIntensity = extraBuffer[10]` = FFT bin. Now bass*0.6 + age-windowed ripple recency (ripples[i].z only).
- Idea 1 Gyroid veil warp (native, L206 + L266): flow offset along gyroid gradient, |g| sheets glow; bass thickens. Visibility 26.0 % / mean 0.011 @192, 25.0 % @576.
- Idea 2 Depth-strata nebula tint (native, L216 + L268). 56.2 % / 0.015 @192; 576 run in run1 log (see scratch).
- §12.2 pre-assigned over-relaxed sphere tracing does not apply (no march) — not used.
- meanL idle 0.266→0.275 (stdL 0.120→0.120); held+audio 0.245→0.286. All 4 sliders sweep live (meanL 0.15/0.37, 0.28/0.30, 0.17/0.42, 0.42/0.18). nan 0.
- frameMs: interleaved 4-round min ratios ≈1.06/1.32/1.39/2.38 and 1.3–2.5 in an earlier run, box load 10–40 → median ~1.35, NOISE-dominated. Already merged gyroid+gradient into one sin/cos set. **Coordinator re-time alone**; if >1.3 confirmed, drop the per-layer gradient warp to 3 layers.

## bioluminescent-bloom (first-pass Ideas; Upgraded line appended)
- Rescue 1 (confirmed): HEAD **did not compile** (`__finalRGB` leading `__`; `let aspect` redeclared) → nothing drawn. Fixed (finalRGB / rAspect). It was in `src/contracts/wgsl_validation.json` knownFailures — **coordinator: remove `bioluminescent-bloom` from knownFailures.ids** (verify-naga-wasm reports it).
- Rescue 2 (confirmed with compile-fixed HEAD): colony never seeded at idle (meanA 0.002) → seeded by Idea 1.
- Rescue 3 (confirmed): treble>0.75 flash put 25 % hash noise in v everywhere → frame saturated (meanL 0.88). Now sparse round stress spots on a 24-cell grid.
- Rescue 4: plasmaBuffer[(ti%8)+1] out of range → per-strand bass/mid/treble mix.
- Rescue 5: dataTextureC filtered sampler → exact textureLoad with clamped neighbours.
- Not changed: extraBuffer[133..137] spring (never persists → acts as a snap; audit:extrabuffer already lists this file at HEAD); full-frame `clockRings` spectral overlay (HEAD).
- Idea 1 Tendril spore shedding (native, L147 + L221): 15.6 % / 0.083 @192 (90 fr).
- Idea 2 Photophore halos (Soft inverse-square bloom, L144): strengthened 0.06→0.15: 1.9 % @192 90 fr (colony covers nodes), 10.4 % @576 30 fr (pre-strengthen). Local to tendrils.
- Idea 3 Quorum front rim (native, L227): 15.2 % / 0.040 @192.
- meanL idle (compile-fixed HEAD → new, 90 fr) 0.081→~0.25, meanA 0.002→0.075; audio 0.88 (white) → 0.60 structured. Colony saturates white-cyan in blob cores (HEAD palette glow*5 + bloom; left).
- Slider sweep 30 fr: tendrils 0.107/0.138, glow 0.115/0.143 live; **dots 0.126/0.126 identical meanL** — dots are sub-pixel at 192 (cell 6.4 px); not investigated further, open.
- frameMs vs compile-fixed HEAD: 1.08/0.89/1.06/1.18 → ~1.07.
- Gates both files: precommit pass, naga-wasm pass, dead-sliders AUDIT PASS, extrabuffer: no new finding.
- Note: running the audits rewrote reports/* in the shared tree (dead_sliders, extrabuffer, precommit) — not reverted (rule 1 forbids checkout); coordinator handles.
