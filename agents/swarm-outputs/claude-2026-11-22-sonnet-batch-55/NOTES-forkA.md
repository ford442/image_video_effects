# NOTES — fork A (ink pair)

Files: `public/shaders/ink_dispersion_alpha.wgsl` (+64/−5), `public/shaders/ink-dispersion-guided.wgsl` (+24/−6), `shader_definitions/artistic/ink_dispersion_alpha.json`, `shader_definitions/advanced-hybrid/ink-dispersion-guided.json`. Nothing committed. HEAD copies: scratchpad `a/*_head.wgsl`.

Harness: SwiftShader, 256 px, 40 frames, tEnd 4 s, JSON defaults, mouse 0.5,0.5 up, audio 0.3,0.2,0.1, `SRC=img` (and `SRC=tex` oriented gratings for the guided file). Do not read these as visual QA on a real GPU.

## Revision of BRIEFS-forkA.md (what changed while implementing, and why)

- ink_dispersion_alpha Idea 5 (dye chromatography): first version low-passed chromaticity over the ±3 px ring; ablation showed it changed **0.0 %** of pixels >8/255 (mean |Δ| 1.9/255) → not a visible idea. Redesigned: where the ring holds darker ink than here but the short-range wick has not reached the pixel (`ringInk`), chromaticity moves toward the ring's, ×1.8 saturated. Ablated again: **9.5 %** pixels >8/255, mean luma unchanged (0.289 both) as intended.
- ink-dispersion-guided Idea 3 (structure-tensor tangent + elliptical dashes, §12.2A) was **implemented, measured and removed**. Dot-mask total variation on `SRC=tex` gratings (clean sinusoids + 7 % per-pixel noise) was 102 % / 106 % / 101 % of HEAD — no jitter reduction from a 3×3 tensor on a noisy source — and the dashes were not visible in the final colour or the isolated mask on `SRC=img` disc contours (the dot row there sits outside the Sobel band that gates `structure`). Replaced by a depth-keyed screen pitch (domain-native, no §12.2 row). §12.2A "Structure-tensor orientation" is therefore **unused** in this batch by fork A.
- Coordinator fact corrected: HEAD `paper_tex` is not spatially flat; it is a time-scaled hash (smooth blotches at t≈1 s, mean neighbour diff 0.004; per-pixel flicker noise by t≈200 s, 0.40).

## ink_dispersion_alpha

IDEA CARD (final) — ADD: (4) fibre-guided capillary wick through exact C; (5) dye chromatography fringe through a wider C ring. KEEP VERBATIM: 4 param roles (p1 pitch, p2 edge thr, p3 levels, p4 ink density), Sobel hypot, posterise, analytic dot + wet-bleed warp, granulation `0.6·fibV + 0.4·fibH` (identical value, the two octaves are just named now), coffee-ring rim, alpha floor, mouse vignette, depth write, A = display RGBA.
- **Idea 4 (WGSL `// ── Idea 4`)**: four exact `textureLoad(dataTextureC, clamp(coord±1))`; per-axis weight = the fibre octave running along that axis; pull from the single darkest-weighted neighbour (`bestPull`), `wet = (0.40+0.35·inkDensity)·bestPull`, mix colour and coverage toward it. Pulls only from DARKER neighbours (no erosion), `step(0.05, C.a)` gate so empty C / first frame pulls nothing. First attempt (4-neighbour average gate) changed 0.3 % of pixels — the average dilutes a 1-px dot to ¼ — so it was reworked to strongest-pull.
- **Idea 5 (`// ── Idea 5`)**: four more C loads at ±3 px; chromaticity (colour/luma, luma floor 0.08) of the result moved toward the ring's ×1.8 where `ringInk`, strength `0.7·…` of the wick; luma preserved.
- A packing: display RGBA (ink colour, ink coverage) unchanged; C is read back with the same meaning. Contraction check: 40 vs 200 frames of a still image give identical stats (meanL 0.291 both) → the halo settles, no runaway. B untouched (never written). No ACES (photo passthrough; P-ACES policy), no audio (JSON never claimed it; adding it would not be native), no new params.
- Rescues: JSON `features` `fluid-sim`/`curl-noise`/`advection`/`mouse-spawn` were false for the code (stateless halftone) → replaced by `halftone`, `ink-wicking`, `temporal-feedback`, `mouse-driven` (the pointer vignette really changes the picture); description rewritten. JSON `tags` (`fluid`, `curl`, `water`, `chemical`) and `x-meta` untouched (follow-up: tags are search keywords and also stale).
- Diff vs HEAD (256 px, defaults): 38.2 % of raw pixels >8/255 (mean |Δ| 8.3), alpha panel 0.4 %; meanL 0.312→0.289 (−7 %: ink gain darkens), meanA 0.160→0.162. At ink density 1.0: meanL 0.308→0.252, meanA 0.497→0.609 (black ink visibly bleeds out of the black disc with fibre-streaked edges). NaN 0.
- Timing (`mr_ab`, 256, 6 cycles, load ≈ 5 from other forks): paired-median 0.99×, min 1.01×.
- Gates: precommit 1/1, naga-wasm pass, dead-slider audit pass (all four `zoom_params` still read, checked by hand), extrabuffer audit pass.

## ink-dispersion-guided

IDEA CARD (final) — ADD: (3) perspective screen pitch from the guide depth; (4) depth-silhouette ink contour from `varGuide`. KEEP VERBATIM: guided-filter chunk, Sobel ink line, posterise, `dotRadius`, edge-tangent screen angle (HEAD angle code restored byte-for-byte), guide-variance feather, vignette, depthBoost, shared param roles, A = display RGBA.
- **Idea 3**: `pitch = dotSize·mix(1, mix(0.7,1.3,guide), clamp(1.6·depth_influence,0,1))`; near (depth 1) coarse, far fine; strength rides the existing depth_influence role (default 0.5 → ×0.76…1.24). Flat depth → constant pitch.
- **Idea 4**: `silhouette = smoothstep(0.04, 0.10, sqrt(varGuide))`; `silW = silhouette·(0.45+0.5·inkDensity)`; blended into the same dark ink colour as the Sobel line (0.02,0.02,0.04) and into coverage after the dot block, before the alpha floor. Band width follows the guided-filter window (≈ the radius from p1). Dormant on flat depth. NOTE: the harness's synthetic depth discs (r 0.22 / 0.15) are larger than the photo discs (0.18 / 0.12), so the contour renders as a ring beside the Sobel edge there; on a real depth map the two coincide.
- Rescues (hygiene, not ideas): `rippleCount` now `min(u32(config.y), 50u)` (was unclamped over a 50-slot array); output colour clamped to [0,1] after the ×(1+0.3·depth) boost (was up to 1.3); `paper_tex` replaced by a static per-pixel tooth (same ±2.5 % amplitude; HEAD's was time-scaled noise).
- A packing unchanged (display RGBA). No C read: a halftone of a frame has no continuity it needs, and the history idea belongs to ink_dispersion_alpha in this batch. No ACES, no audio (never claimed). B untouched.
- Diff vs HEAD (256 px, defaults): 34.9 % raw pixels >8/255 (mean |Δ| 9.0) and 62.9 % in the alpha panel — the pitch change moves the whole dot lattice's phase, so **the default dot pattern is different everywhere** (meanL 0.347→0.343, meanA 0.283→0.288). Rings from clicks (ripple depth bump) now also draw contours. NaN 0 incl. ink density 1.0 + ripples + mouse down + loud audio.
- Timing: paired-median 1.08×, min 1.07×.
- Gates: precommit 1/1, naga-wasm pass, dead-slider audit pass (x,y,z,w all read), extrabuffer audit pass.

## Open calls for the user
1. ink_dispersion_alpha default look changes (−7 % meanL, halo + fibre crosshatch): wick strength `0.40+0.35·inkDensity` can be lowered if the original crisp dots are preferred.
2. ink-dispersion-guided default dot lattice shifts (pitch ±24 % with depth): lower `1.6·depth_influence` or the 0.7/1.3 range to keep HEAD's lattice nearer.
3. `ink_dispersion_alpha.json` `tags` still list fluid/curl/water (stale).
4. Real-GPU visual QA is external; the dye-ring and silhouette were judged only on SwiftShader renders.
