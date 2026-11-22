# NOTES — fork B — quantum-foam family (pass1, pass2, pass3)

Files touched: public/shaders/quantum-foam-pass1.wgsl, -pass2.wgsl, -pass3.wgsl. No JSON, no git, no generated files.
Harness: agents/mrchain.mjs (GRAPH='A,B' mirrors the Tier-C copies; PERF=1 drained min-frame timing; DEPTH=, RIPPLES= absolute start time).

## Where each idea is in the WGSL (`// ── Idea N:` markers)
- pass1 Idea 1 pair lifetimes: cellLife (per-cell sin^2 clock from the nearest cell's hash id), scales the core (cellPattern) and deepens the transient void. Idea 2 flow-sheared cells: voronoi() metric stretched along curl direction, stretch = 1 + 0.8*Flow Speed.
- pass2 Idea 1 bubble lens: 4 exact C loads of pattern, `lens` added to all three dispersion UVs. Idea 2 Hawking ramp: hawkingRamp(flareTemp) mixed 0.55 into the plasma hue.
- pass3 Idea 1 redshift: `redshift` tint on the glow term keyed to coreHeat. Idea 2 bass-swollen glow: plasmaBuffer[0].x widens kernel radius + smear length and lifts gain (HEAD pass 3 had no audio).

## KEPT VERBATIM
pass1: 3-layer depth parallax structure, voronoi+hybridPattern, noise4d, 3-wave interference, bass/treble gains, voids + wavefront ridges, A packing (warpX, warpY, pattern, ridgeBoundary), param roles (x scale, y speed, z diffusion, w octaves), mouse-X depth parallax.
pass2: dispersion RGB offsets, comet tail, scintillation (bass), spectralPower, B AND A write of (finalColor, emission) (graph declares B; A write is redundant but documented in the header, left alone), diffusion slider role, mouse-down chroma spread.
pass3: 3x3 flow-smear glow, Beer veil, haze, vignette, grade, ACES (display only), gamma (see open call), C loads, y/z roles.
A packing: pass1 raw field; pass2 (rgb, emission) in B and A, not display; pass3 colour only.

## RESCUES (HEAD defects, reported apart from ideas)
- R1 pass2/3: globalIntensity = u.config.y (= rippleCount). Measured HEAD: 0 clicks meanL 0.408/stdL 0.176 == the photo; 1 click 0.588; 6 clicks 0.347. Now fixed full intensity; 0/1/6 clicks all 0.669/0.190 (identical). Early return removed.
- R2 pass2: "history" = textureLoad(dataTextureC), which in this graph is pass 1's warp field -> (warpX, warpY, pattern) blended into the picture as colour. Now an exact textureLoad of readTexture one step upstream along the warp (C has no real colour history here: A->C is copied before pass 2).
- R3 pass1: fbm/curl/voronoi hashed position AND time with no interpolation. Measured field change between frames 1/60 s apart: HEAD dWarpX 0.578 (== change at 2.5 s, i.e. temporal static), NEW 0.012; at 2.5 s NEW 0.317. Replaced with a smooth wave-sum fbm (same signature, gains 0.55/2.15), analytic-gradient curlNoise (curl gain 0.42/octave, CURL_GAIN 0.3, |curl| std ~0.87), voronoi seeds that orbit continuously (HEAD put both seed coords on the line y=0.7x and re-hashed with time). Debugging showed three more fold-over sources, all fixed: voronoi warp coefficient x2.0 -> x0.35 (slope was ~3.8); warp octaves capped at 3; nested curlNoise(baseP + curl*lv) -> per-layer decorrelated lookups. pass2 carries a body-identical curlNoise.
- R4 pass2: rotationSpeed = zoom_config.x*2 (= 2*time) -> 0.25+0.6*Flow Speed with a wrapped phase. ALSO: HEAD computed `rotatedColor` and never used it (the spin never reached the output); now mixed into the comet at 0.25*saturate(pattern). This is a visible change from HEAD.
- R5 pass2 (not in the brief): emission threshold 0.3+0.5*mouseY (0.55 centred) vs drive cellBoundary*pattern*luminance whose 99th pct is 0.47 (both HEAD and NEW): 0.05% of pixels emitted, so flare, scintillation and pass-3 glow/Beer veil were dormant. Threshold now 0.26+0.1*mouseY, band 0.35: 8.6% of pixels >0.02, 2.2% >0.2. Without this, 3 of my 6 ideas measured ~0.0000-0.0005.

## Measurements (SwiftShader, 256 px unless noted)
- NaN 0 at default, 0 and 6 clicks, A16=1, params 0,0,0,0 and 1,1,1,1 with audio 1,1,1 and mouse down.
- Sliders live (mean |final diff| 0 -> 1): foam_scale 0.07, flow_speed 0.04, diffusion 0.017-0.025, octave_count 0.003-0.008 (weakest, drives cell-interior detail only now that the warp is capped at 3 octaves).
- Idea ablation (mean |final diff| with the idea off, bass test 0.6): pair lifetimes 0.0127, shear 0.0383, bubble lens 0.0095, Hawking 0.0064, redshift 0.0019 (up to 0.24 locally, flare cores only), bass glow 0.0066.
- Cost vs HEAD (1-click HEAD so its pass 3 takes the full path; min of drained frames, alternating): rounds 1.10, 0.80, 1.02, 1.12, then 0.94, 0.98, 0.90 (load avg 3-6 from other sessions). Under the 1.3x cap. Quiet-box re-time recommended.
- Gates: wgsl_precommit_gate 3/3, verify-naga-wasm --files 3/3, audit:extrabuffer pass, audit:dead-sliders pass (it only scanned the 2 defs with JSON params; grepped the rest by hand).

## OPEN CALLS for the coordinator
1. pass3 gamma-after-ACES: input photo is display-referred, ACES then pow(1/2.2) lifts mid-tones hard (0.3 -> 0.69, 0.5 -> 0.80; ACES alone would give 0.44 / 0.62). meanL 0.409 -> 0.669 at defaults. Left as HEAD (look unchanged by me); probably wrong, other final passes in this batch use ACES only.
2. pass2 still reads mouse as parameters: emission threshold (+-0.05 now) and chromatic spread (mouse down 0.5 -> 2.5). Left. pass1 mouse-X depth parallax left too. JSON features have no mouse-driven tag on any foam pass; I did not touch JSON.
3. pass2 writes A as well as B with identical data; the graph declares only dataB. Redundant but harmless (pass 1 never uses C). Left.
4. JSON (coordinator): pass3 definition has params [] but reads zoom_params y/z (slot params come from pass 1, so fine); pass1 features lack audio-reactive evidence only in pass 3 which now reads plasmaBuffer -> add `audio-reactive` to quantum-foam-pass3 if you want the tag; quantum-foam-pass1/3 have no x-meta.upgrade.params.
5. The foam grain looks fine at 512 px; at 1080p the cell-interior octaves (up to 5) are finer than 3 px: judge on a real GPU.
