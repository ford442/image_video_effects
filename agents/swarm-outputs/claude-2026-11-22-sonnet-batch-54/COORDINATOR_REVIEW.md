# COORDINATOR_REVIEW — sonnet/batch-54 (2026-11-22)

Gates on the final tree: precommit 8/8, naga-wasm 8/8, audit:extrabuffer PASS, dead-sliders PASS (0 new), `npm run verify:shaders:fix` 11/11. Not run: `npm run build`, Vitest (no commit/PR requested). Real-GPU visual QA: external.

| id | verdict | ideas in diff | rescues |
|---|---|---|---|
| liquid-pass1 | PASS | Faraday bass forcing; dispersive capillary precursor | wave-eq signs reversed (every mode grew to clamp); exact C loads |
| liquid-pass2 | PASS | treble sun-glitter; Cauchy dispersion of refraction | gains retuned for a stable solver; per-UV slope/curvature; exact C loads |
| liquid-optimized-pass1 | PASS | bass basin slosh; short-wavelength viscous damping | same sign fix; exact C loads |
| liquid-optimized-pass2 | PASS | HG scatter veil (Turbidity, 0 at default); TIR crest roll-off | gains/exact C loads; no audio by design |
| quantum-foam-pass1 | PASS | pair-lifetime cells; flow-sheared voronoi | white-noise basis -> coherent noise (inter-frame delta 0.578 -> 0.012); 3 fold-over bugs |
| quantum-foam-pass2 | PASS | bubble lens; Hawking colour ramp | config.y (=rippleCount) intensity; fake history blend; t^2 spin; dormant flare threshold |
| quantum-foam-pass3 | PASS | gravitational redshift; bass-swollen glow | config.y intensity + early return |
| pyramid-downsample-pass1 | PASS | Burt-Adelson 5-tap kernel; bass-opened range sigma | alpha passthrough |
| pyramid-bandprocess-pass2, pyramid-composite-pass3 | NOT MODIFIED | — | clean at HEAD |

Kept: all saved params byte-exact; foam-2 and pyramid-1 B writes (documented hand-offs); A packings unchanged. Cost vs HEAD (SwiftShader, drained min-of-frames, interleaved x4): liquid 0.95x, liquid-opt 0.96x, foam 0.80x, pyramid pass 1 alone 1.28x (max 1.56x one round), pyramid trio 1.14x.

## Open calls (user)
1. quantum-foam-pass3 gamma 1/2.2 AFTER ACES: meanL 0.670 vs 0.457 without (photo 0.408). Left as HEAD.
2. Default looks changed on purpose: liquid is now calm water (HEAD was saturated chop); foam is now visible with no clicks.
3. Liquid wave speed is in px/frame (explicit step, fixed dt=0.016): propagation is resolution-dependent and the Faraday drive uses real time, so it detunes off 60 fps.
4. pyramid-downsample-pass1 sits near the 1.3x cap; fallback = exp on inner 3x3 only.
5. Bass=1 held for seconds fills liquid with standing waves (forcing depth already cut 0.9->0.6).
6. foam-2 still reads mouse as parameters (threshold nudge, chroma spread on mouse-down); ACES in both liquid pass-2 files tone-maps the whole frame incl. dry photo, as at HEAD.
7. Foam grain unchecked at 1080p on a real GPU. Thumbnails stale (ledger marked): refresh on a GPU machine.
