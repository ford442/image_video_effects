# NOTES — fork E (radial-rgb, focal-pixelate)

Harness: `agents/mr.mjs` (synthetic photo) and my own `agents/mr_scene.mjs` (= mr.mjs + `SCENE=<png>`: loads `public/fixtures/thumbnail-scene.png`, a high-chroma sunset scene with specular bars/swatches, as the photo; depth stays the synthetic one). HEAD copies in scratch `e/<id>_head.wgsl`. Timing taken at load average 14–18 from the other forks; the coordinator should re-time on a quiet box.

## radial-rgb
Idea Card = BRIEFS-forkE.md. ADD (2): **1. Cauchy lateral colour (§12.2F)** — `cauchyScale(zoom_params.w*0.06)`: R/B uv scaled about the (possibly decentred) optical axis by n(650/450 nm)/n(550 nm), G = reference; the k1-per-channel term is untouched. **2. Radial coma tails** — 2 taps toward the axis along `radialDir`, soft-knee on tap luma (0.62..1), weights 1/(1+0.8k²), length ∝ field radius × Dispersion (× bass), amount gated like the astig mix and by (1 − own highlight).
KEEP VERBATIM: 4 params + roles, `lensDistort` / k3 = k1·k2·0.35, `k1R/k1B`, astigmatism 3-tap, spectral tint, depth mix, audio pulse/sparkle, held-pointer axis, vignette + cat's-eye, Fresnel/transmission alpha, ACES. Saved `params` byte-exact; `features` unchanged (audio + pointer both genuinely drive the picture).
A PACKING: ACES display RGBA (unchanged).
Rescue / hygiene: (a) **Dispersion slider was dead at the saved default** — k1=k2=0 so `uvR==uvG==uvB`; measured HEAD dispersion 0.3 vs 0 → 0.0 % of pixels differ > 4/255, R-vs-B edge shift 0 px. Idea 1 makes it live at the default. (b) `dataTextureB` write removed: undocumented, and `framePlan.getFeedbackCopyOrder` copies B→C first and A→C last, so B next to A is never observed (hygiene, no pixel change). With **Dispersion = 0 the NEW output is bit-identical to HEAD** (0.0 % px, max Δ 0, alpha identical) — both ideas gate on the slider.
Diff vs HEAD at the saved default (scene, 512): 10.6 % px > 6/255, mean Δ 3.1/255 (the lateral-colour fringes on high-contrast edges; coma contributes ~2 %); meanL 0.349 → ~0.352. Exercised (k1 .85, k2 .7, aniso .4, disp .6, mouse held at .3,.6, audio .8/.4/.6): 0 NaN, 4.5 % px differ, meanL 0.237 → 0.238.
Timing (512, SwiftShader, load ~14): min ratio 1.01, paired median 1.05 (first draft with 3 coma taps measured 1.33–1.43, trimmed to 2 taps). 12 → 14 texture samples.
Open calls: strength constants (0.06 Cauchy scale; coma gain 1.1) are by eye — at Dispersion ≥ 0.8 the R/B copies separate by ~10–20 px at 512 and the 2-tap coma stair-steps; both are the slider's top end, not the default. Dead helper `audioPulse` and unused `mids` left (not touched).

## focal-pixelate
ADD (2): **3. CFA zipper (§12.2A)** — in the pixelated fringe (× mix_factor, 0.7) luma stays from the block sample, chroma comes from the 2×2 super-block grid (`floor(cell/2)*2+1`), one extra point tap. **4. Highlight-weighted defocus discs** — the 7 hex taps weighted by `1+3·smoothstep(0.55,1,luma)`, normalised. (Numbered 3/4 in the WGSL because HEAD's `Idea 1/2` comments stay.)
KEEP VERBATIM: 4 params + roles, `mix_factor`/invert, block mapping, `lodForBlocks`, hex tap geometry, CoC, aperture well, depth fog, ACES + audio lift, IGN dither, alpha formula, depth write. Saved `params` byte-exact.
Rescues (verified on HEAD before fixing):
1. **The purple lens disc is a bug.** `domainWarp` returned the absolute position `uv*8 + strength*q`, used as a uv offset → fringe sampled ≈ 9·uv, clamped to the photo edge (purple field, edge streaks, a 9×-minified scene in the top-left 11 % corner; `fr` and the fog sample inherit it). Now returns the displacement `strength·(q−0.44)`. Default picture changes **drastically**: 64 % of px differ > 6/255 (mean Δ 27/255) from HEAD; meanL 0.233 → 0.200 (synthetic photo), 0.126 → 0.166 (scene).
2. A packing: HEAD = raw metadata (mix, 1/blocks, bass, alpha) read by nothing → now ACES display RGBA (same tone + alpha as writeTexture). **`dataTextureB` write removed** (dead, same B→C-then-A→C reason). Dead code removed: `fully_focused`/`historyMix`, unused `var<workgroup> tile`. Header tags `shared-memory-tiling` and `temporal-feedback` removed (neither was real); JSON `features` never carried them.
A PACKING: ACES display RGBA (changed, see above).
Exercised (invert_focus=1, softness 0 + loud audio .9/.2/.8, wide softness, default): 0 NaN. Timing (512): min ratio 1.00, paired median 0.88 (the extra tap is cheaper than the clamped-edge work HEAD did).
Open calls: (a) A content differs from HEAD (metadata → colour); nothing in the file or engine reads either. (b) Fog `exp(−depth·(1.5+mix))` dims even the in-focus disc ×0.22–0.47 at mid depth and the depth direction is ambiguous in the repo (`normalizeDepthMap` gives near=0, the harness near=high) — left as HEAD. (c) Alpha comment says "more pixelation = more transparent" but alpha *rises* with `mix_factor` (0.2 in focus → 0.55 in the fringe). (d) ACES regrades the photo path (kept; floor).

## JSON
`radial-rgb.json`, `focal-pixelate.json`: `description` extended for the new behaviour; focal-pixelate gained additive `x-meta.upgrade.params`; `params` and `features` byte-identical to HEAD (checked programmatically).

## Gates (this fork's files)
precommit 2/2, naga-wasm 2/2, `audit_dead_sliders` 0 new (2 defs scanned), `audit_extrabuffer` PASS. The gate rewrote `reports/wgsl_precommit_report.json` (shared; coordinator discards). Real-GPU visual QA: external.
