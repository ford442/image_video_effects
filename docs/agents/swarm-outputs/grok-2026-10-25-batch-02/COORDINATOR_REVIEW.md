# Coordinator review — Grok high (`grok/batch-02`, 2026-10-25)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea is marked in the shader with `// ── Idea:`.

| Shader | Verdict | Why |
|---|---|---|
| gen-cymatic-plasma-mandalas | pass | Spokes use the angular factor already inside `wave`. Sand is the existing speckle, attenuated by the existing belly. Spring was already there. |
| gen-cellular-automata-tapestry | pass | Wash and rim consume `feed`, `A`, `reaction`, and `nucleus`. Solver and packing unchanged. |
| multi-scale-evolutionary-cellular-gardens | pass | Founders fire only on empty ground. Scar uses `newRes` and the two species. Neighbor reads are now exact loads of the same 8 taps. |
| gen-crystal-lattice-growth | pass | Veils use the along-segment coordinate. Junction is the tip the child already leaves. No new primitive. |
| gen-fireworks-ring-shell | pass | Gap is a scale of the existing ellipse by `thick`. Spokes modulate `ang` on the same sparks. |
| gen-psychedelic-moire-flower | pass | Beat frequency is `|f1−f2|` of the two layers already drawn. Vernier is 13−8. |
| gen-buddhabrot-aura | pass | Smooth iteration replaces the integer `esc` inside the existing break. Period-3 limb matches the period-2 treatment. |
| gen-echo-dunes | pass | Stoss is the complement of the existing slipface. Cornice is crest ∩ slipface. |
| gen-dynamic-tessellation-ornate-fractal-tiles | pass | Joint darkens around the existing grout. Ribs join the existing corner rosettes. |
| magnetic-flux-garden | pass | Sheet is the midplane of the two poles. Cores are the inverse-square the march already uses, saturated. A stays the field triple. |
| gen-celestial-yggdrasil-matrix | pass | Furrows and heartwood use `branch_angle` and `flow` on the hit. No extra KIFS taps. |
| gravito-phononic-accretion | pass | Saddle is `pull1 ≈ pull2` on the existing segment. Overtone is the second harmonic of the same ridge. |
| flow-sort | pass | Longer smear is gated by agreement of the existing tangent. Bead is the refusal the Asendorf gate already computed. |
| split-flap-display | pass | Lag is a fraction of the existing velocity on the lower half only. Pip is `fract(angle/π)`. State read moved off write-only A onto C at the cell center. |
| gen-crystalline-mandala-bloom | pass | Dispersion resamples along the existing facet offset. Culet is a pit at `r = 0` inside the existing bloom. |

## Formula rows

| Row | Files |
|---|---|
| Smooth iteration (§12.2E) | gen-buddhabrot-aura |
| Soft inverse-square (§12.2F) | magnetic-flux-garden |
| Cauchy (§12.2F) | gen-crystalline-mandala-bloom |

No row is on more than one file. No new solver, binding, or spring.

## Checklist

- [x] Idea card before the diff, with mechanism notes
- [x] Each idea is pointable in the WGSL
- [x] Modes, kernels, and param roles kept
- [x] Diff is the ideas plus the prelude swap and the two exact-load fixes
- [x] No shared spring / ripple / IQ stamp (IQ on magnetic-flux-garden was already the bloom)
- [x] A packing matches how C is read
- [x] Saved `params` unchanged
- [x] Naga 15/15, extraBuffer clean, dead sliders clean on the 14 `params` arrays
- [x] Vitest 1435 passed / 1 skipped. `SKIP_WASM_BUILD=1` production build succeeded. No real-GPU visual QA on this VM.
