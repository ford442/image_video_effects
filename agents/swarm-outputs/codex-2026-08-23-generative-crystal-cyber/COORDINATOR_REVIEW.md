# Coordinator review

## Contract decisions

- A/C is consistently documented as raw HDR display RGBA history. `writeTexture` receives ACES-mapped RGB with the same semantic alpha.
- `dataTextureB` remains bound for host compatibility but is never written.
- No shader in the cohort accesses `extraBuffer`; ferro-coral's former reads from engine FFT indices 6–13 were replaced by `plasmaBuffer[0].xyz`.
- C displacement is pixel-space and clamped before exact loads. Source image and depth filtering remain allowed; the no-filter rule applies specifically to C.
- Existing ferro-coral and liquid-chrome-engine behavior was refined in place rather than replaced.

## Static review highlights

- Every shader has an invocation bounds guard.
- All ten read x/y/z/w controls and bass/mids/treble.
- All ten write display output, raw history A, and semantic depth; none writes B.
- Ripple age is calculated as `time - ripple.z`; `config.y` is treated only as ripple count.
- HDR history is bounded before persistence, and ACES is applied only on the display path.

## Visual handoff

This Cloud VM has no WebGPU adapter, so motion, raymarch cost, alpha compositing, and thumbnail acceptance need a real-GPU pass. Priority visual checks are chrono-Dyson dispersion stability, terminal readability at density extremes, and moth/neuro feedback persistence after interaction.

## Validation

- Focused WGSL precommit gate: 10/10 Naga-clean, bindings compatible, zero workgroup warnings, zero extra-buffer violations.
- Focused dead-slider audit: 10 definitions scanned, zero new or known dead controls.
- Custom contract audit: exact bindings 0–12, exact C loads, A-only feedback, depth/display stores, ACES, three-band audio, bounded state, and four named mappings pass 10/10.
- `npm run verify:shader-list-urls`, `npm run verify:uniforms`, and `npm run typecheck`: pass.
- Catalog: 441 generative shaders; 1,333 entries across 14 categories.
- Jest: 81/81 suites; 545 passed, one skipped.
- Production: `SKIP_WASM_BUILD=1 npm run build` compiled successfully.
