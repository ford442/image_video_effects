# NOTES — fork B (gen-strange-field-flow, gen-topological-acoustic-knots)

Renders: 256² SwiftShader, 40 frames / 6 s, bass=mid=treble 0.3 unless stated; "diff" = % of pixels with any channel differing by >4/255 from HEAD's panel 1. VM only — **no real-GPU visual QA claimed.**

## gen-strange-field-flow (2nd pass)
**Ideas added (both §12.2E, `Ideas:` line + `// ── Idea n` comments in WGSL):**
3. *Fold count as material* — soft axis-crossing count of the 8-step orbit, `xing = 1 − smoothstep(−0.12, 0.12, pt·prevPt)` per axis summed over the loop; `hue += folds·0.045`. Cells that fold alike share a hue family; soft so edges do not alias.
4. *Orbit-trap hit time* — `trapIter` = iterate that made the Pickover min (promoted argmin); the stalks' flat warm colour is mixed 55 % toward `hsv(0.08 + trapIter/ITERS·0.8 + t·0.03, 0.6, 1)`.
**KEEP VERBATIM (unchanged):** 4 params + roles, both map steps + chaos `mix`, Gaussian-ish orbit-proximity density, `orbit_hue`, Lyapunov stretch tint, Pickover stalks (value unchanged, only the colour of the stalk add), history pull/rotate + chroma split feedback, ACES, depth, alpha.
**A packing:** ACES display RGBA (unchanged; C read as display colour).
**Rescues:** none (no HEAD defect found; all sliders read, audio from `plasmaBuffer[0].xyz`, no extraBuffer).
**Diff vs HEAD:** default 65.9 %; exercised (p=0.7,0.9,0.8,0.3, audio 0.8/0.5/0.6) 69.2 % — a hue/stalk-colour shift, structure (whorl geometry, density, alpha, depth) identical. NaN 0.
**Timing (mr_perf, 192², 6 interleaved rounds, loaded box):** median 1.22× (range 0.91–1.58), inside the ≤1.3× cap; cost is 8× a vec2 smoothstep + a `mix`.
**Gates:** precommit 1/1, naga-wasm 1/1, dead-sliders PASS (0), extraBuffer PASS, `Pasted headers: 0`.
**Observation, not changed:** header text promises "streaks along the local flow direction" but the proximity kernel is isotropic; an anisotropic kernel along `pt−prevPt` would be a look change — left for the coordinator.

## gen-topological-acoustic-knots (2nd pass)
**Ideas added (no §12.2 liquid-crystal row exists → tactics 3 + 7; deliberately no orbit/fold row so it does not share with the sibling):**
1. *Frank splay/bend tint* — `splay=|∇θ·n⊥|`, `bend=|∇θ·n|`, `splayFrac=splay/(splay+bend)`; the defect-glow colour moves warm (splay, HEAD colour) → cool (bend, `(0.35,0.75,1.0)`). Head vs tail lobes of each ±½ comet read in different hues.
2. *Landau–de Gennes order-parameter core melt* — `r≈0.5/|∇θ|`, `S=r/√(r²+0.18²)`; multiplies the iridescent stripe term and the treble shimmer so the director texture dissolves toward each core.
**KEEP VERBATIM:** 4 params + roles, `defectOrbit`, ±½ charges + `live` pair annihilation (existing Idea 1), mouse defect, `iridescent()` ramp, Schlieren `abs(sin 2θ)` brushes (existing Idea 2, still keyed on `defectStrength`), C feedback 0.97/0.2, ACES, alpha/depth.
**A packing:** ACES display RGBA (unchanged).
**Rescues (all change the default look — flagged):**
- R1 wrap Δθ to ±π/2 before ÷ε (director is π-periodic; raw difference spiked |∇θ| to ±π/ε on every atan2 cut).
- R2 `defectGlow` polarity: HEAD `smoothstep(0.3, 0.0, ds−0.5)` was 1 away from cores / 0 at cores → flat warm veil over most of the frame (HEAD meanL 0.66, stdL 0.16). Now `smoothstep(0.3, 0.8, ds)` (glow at cores).
- R3 defect positions × `(aspect, 1)` so they share the aspect-scaled space of `uvA` and the mouse (HEAD: defects only in uv units → none in the right 30–40 % of a 16:9 frame). Identical at aspect 1; **not rendered at 16:9 here** (mr.mjs is square).
- R4 singular-core gain `2.0 → CORE_GAIN 0.7`: at 2.0 the core term saturated at |∇θ| ≥ 3.3 (r ≲ 0.15 per defect, summed over 2–12 defects) so white blobs engulfed ~half the frame (density 1.0 = a full whiteout) and hid the director texture, which also hid Ideas 1–2 (ablation showed ≈1 % changed pixels). One constant; `CORE_GAIN = 2.0` restores HEAD.
**Ablation (R1–R4 on, each idea removed):** idea 1 → 35.8 % pixels differ (>4/255, max 41); idea 2 → 33.5 % (max 14). NaN 0.
**Diff vs HEAD:** default 98.7 %; exercised (p=0.8,0.7,0.9,0.7, mouse 0.7,0.3 down, audio 0.8/0.6/0.7) 91.1 % (mostly R2/R4).
**Timing (mr_perf, 192², 6 interleaved rounds, loaded box):** median 1.13× (range 0.85–2.52; the 2.52 round coincided with other forks' renders), inside the ≤1.3× cap. Added work is one `inverseSqrt`, two dots, a `mix`; R1 adds two `round`s.
**Gates:** precommit 1/1, naga-wasm 1/1, dead-sliders PASS (0), extraBuffer PASS.
**Not fixed (inherent to HEAD):** `stripe = sin(dot(uvA, dir)·k …)` is odd in `dir`, so the π jump across each atan2 cut flips the stripe phase — thin horizontal seams left of defects remain (visible in HEAD and new). Pair-annihilation thresholds are in uv units, so after R3 pairs meet slightly less often in x.

## §12.2 rows used (for COORDINATOR_REVIEW)
strange-field-flow: Fold count as material (E); Orbit trap (E). acoustic-knots: none from §12.2 (Frank splay/bend, LdG order parameter — tactics 3/7).
