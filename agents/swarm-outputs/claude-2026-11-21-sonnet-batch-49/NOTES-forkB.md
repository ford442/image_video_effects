# NOTES — fork B (liquid-metal-prismatic, liquid-oil-iridescence)

Cards, §12.1 answers and the measured deviations are in `BRIEFS-forkB.md` (cards written before any WGSL edit; "AMENDMENTS" section records what changed after measuring). VM = SwiftShader: structural + render checks only, **no real-GPU visual QA is claimed**. HEAD = worktree file after the coordinator's prelude migration (scratch copies in `scratchpad/b/*_head.wgsl`).

## liquid-metal-prismatic (2 ideas)

| # | Idea | Where in the diff | Row |
|---|---|---|---|
| 1 | Cauchy band fan, prism-law fringe width | `// ── Idea 1` before the four taps: `invL2`/`fan` from 410/490/590/650 nm, centred + rescaled to HEAD's span 3.2 (offsets ≈ +1.89/+.29/−.86/−1.31); `steep` scales fringe width 0.55..1.45 by `|disp|/(intensity·1.6)` | §12.2F Cauchy dispersion |
| 2 | Reflected strip light | `// ── Idea 2`: `sweep` now evaluated at `p + disp·aspectVec·4` (HEAD used undisplaced `p`, so the bar stayed straight while the photo bent); the old line-6 `sweep` declaration was removed | tactic 3 (promote `disp`), no row |

**KEEP VERBATIM held:** 4 params and roles, `facets`/`seam`/`disp` (+ pointer swirl + ripple fronts), four-tap band sources (violet s0.b, cyan s1.g, amber s2.r, red (s3.r+s3.g)/2), 0.17 history blend along `disp·0.5`, silver tint, spectral recombination, alpha, depth write. No spring, no extraBuffer, no new param, no extra texture tap (still 4 taps).
**A packing:** raw four spectral-band intensities, clamped 0..2.5, not tone-mapped; ACES on `writeTexture` only. Unchanged.
**Dropped:** conductor Fresnel (Idea 3) — measured invisible (max |Δ| 0.004 at S=.6, 0.025 at S=1.2, 0.040 with ripples+held pointer). Not shipped, not claimed.
**Rescues:** none (no HEAD defects found).
**Diff vs HEAD** (320 px, 60 frames, saved defaults 0.5/0.5/0.5/0.7, SRC=img): >0.01 31.5%, >0.03 16.7%, >0.08 6.5%, mean |Δ| 0.0175; meanL .658→.654 (240-frame matrix: all-zero .536→.534, all-one .724→.723). Alpha identical. The visible change: the straight diagonal bar becomes wavy chrome ribbons / closed loops, and violet/red fringes become asymmetric.
**Timing** (mr_ab.mjs, interleaved, 256 px, 5 rounds on a box shared with four other forks): median of per-round paired-median ratios **1.04×**, median min-ratio 1.05×, median p25-ratio 1.01×; per-round spread 0.57–1.23 (noise). Held-pointer case 0.81× paired / 1.07× min. Well under the 1.3× cap; coordinator may re-time on a quiet box.

## liquid-oil-iridescence (3 ideas)

| # | Idea | Where in the diff | Row |
|---|---|---|---|
| 1 | Order-dependent thin-film colour | `spectral(h:vec3, coh)`; `// ── Idea 1`: `cyc = thickness·ior·13·(0.992,1,1.011) + island·.45 + t·(1.4+audio.x)` (period ∝ λ at 650/550/450 nm, ε = 0.05, applied to the thickness term only) and coherence envelope `0.72 + 0.28·e^(−2.2·thickness)` | §12.2F thin-film phase |
| 2 | Reflected radiance | `// ── Idea 2`: `accents *= 0.7 + 0.6·luma(src)` (display only; A keeps the pure interference RGB) | tactic 8 (energy accounting), no row |
| 3 | Thickness-dependent lubrication mobility | `// ── Idea 3`: `flow *= mix(0.75, 1.75, smoothstep(0.1,0.7, filmAt(coord).w))` before the flow clamp; 1 extra exact C load | tactic 4 (second-order the parameter) / lubrication h^n |

**KEEP VERBATIM held:** 4 params and roles (`film_ior` still the `ior` in the fringe phase), `stream`/`island`/swirl/pointer stir/ripple swirl, semi-Lagrangian advection + viscosity blend + island/depth seeding + pointer thinning (`−local·held·.085`, click +.012), `phase` and `contour = pow(1−|sin(phase·2.3)|,14)`, the 0/⅓/⅔ hue offsets, `blackPearl`, accents mix, magenta/cyan/lime emissive terms, Fresnel alpha, depth write.
**A packing:** raw state, A.rgb = spectral interference RGB (clamped 0..2.5), A.w = normalised thickness; not tone-mapped; ACES on `writeTexture` only. Unchanged.
**Rejected after reading/measuring (not shipped, not claimed):** mass-conserving dewetting rim — a mass-matched ring erases the wide held dent (profile −.22 −.12 **+.09 +.07**) and an amplitude that leaves the dent alone is invisible (net −.057 vs HEAD −.063); shallow-water divergence term — flow is solenoidal by construction, ≈ 0; π-phase / Newton's black film — unreachable (`phase` carries `t·1.4`, thickness ≥ .04). Details + numbers in BRIEFS amendments.
**Tuned by looking:** Idea 1 at ε .07 / envelope .55+.45e^… flattened the dense high-order rainbow (68% of pixels > .03 vs HEAD with identical geometry); shipped milder. Mobility re-centred (0.75..1.75, mean ≈ 1) so the "fast capillary streams" keep their overall speed.
**Rescues:** none (no HEAD defects found).
**Diff vs HEAD** (320 px, 60 frames, defaults 0.5×4, SRC=img): >0.01 99.2%, >0.03 89.3%, >0.08 49.5%, mean |Δ| 0.100 — **large, but not a like-for-like recolour**: mobility changes the evolved film state (mobility on/off alone differs by 57% of pixels > .03 after 3 s), and reflected radiance rescales every fringe by 0.7–1.3. Identity check by eye (HEAD vs new panels): still pearl-black islands with magenta/cyan/lime contours; meanL .394→.379, stdL .059→.081 (more structure, 4% darker mean), alpha mean |Δ| 0.001. Idea 1 alone (same geometry as HEAD) was 36% > .03 / 0.7% > .08 at the milder ε/envelope tried first.
**Timing** (same protocol): median paired ratio **0.95×**, median min-ratio **1.14×**, median p25-ratio 0.97×; spread 0.83–1.19 paired (noise); held pointer 1.19× paired / 1.12× min. Under the 1.3× cap on all medians; worst single round min-ratio 1.38× under heavy box load. `mr_ab.mjs` ignores `RIPPLES`, so click-ring cost was not timed (held pointer only).

## Gates (each file)
- `wgsl_precommit_gate.py --files`: metal 1/1, oil 1/1 (naga OK, bindgroup compatible, 0 pasted headers, 0 extraBuffer violations).
- `verify-naga-wasm.mjs --files`: metal 1/1 valid, oil 1/1 valid (0 known, 0 new).
- `audit_dead_sliders.py --files liquid-metal-prismatic liquid-oil-iridescence`: 0 new dead sliders (both JSONs have full `params`, so the audit scanned 2 defs). `audit_extrabuffer.py`: PASS (0 dynamic-index writes, 0 out of range).
- Render matrix at 256 px × 240 frames (defaults / all-zero / all-one / held pointer + loud audio / 3 clicks): `nan 0`, no blank or saturated frame, `verr null` for both files.
- JSON: `params` untouched (ids, defaults, mapping); description sentence appended; `upgraded-rgba` tag added (ACES in WGSL + cards implemented, §8). No other tag changes.

## Not verified / caveats
- No real-GPU visual QA. Reflected-radiance strength (0.7+0.6L) and the oil ε/envelope were tuned by eye on one synthetic two-blob test image on SwiftShader; real photos with large bright areas will brighten the fringes there.
- Oil mobility (Idea 3) is a motion/dynamics idea: verified structurally and for stability over 240 frames, not visually distinguishable in a single still.
- The gate scripts rewrote `reports/dead_sliders_audit.*`, `reports/extrabuffer_write_audit.json`, `reports/wgsl_precommit_report.json` — shared generated files, left for the coordinator to discard (§8c); I did not `git checkout` them.
- Not committed.
