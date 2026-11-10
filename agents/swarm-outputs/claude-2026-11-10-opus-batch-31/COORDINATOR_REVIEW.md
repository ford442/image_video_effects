# opus/batch-31 — coordinator review (2026-11-10)

Four forks (A 3 / B 3 / C 2 / D 2). Cards in BRIEFS-*.md were written before WGSL; per-shader detail and Δ% numbers in NOTES-*.md.
No independent unanchored reviewer ran on this batch; the Δ% figures are the forks' own measurements (SwiftShader, idea on vs off, % pixels |Δ|>0.02).

| ID | Ideas added | Δ% (each) | Rescues | Pass |
|---|---|---|---|---|
| color-channel-weave | Jacquard yarn-dye; slub yarn | 9.0 / 69 | dead extraBuffer spring removed; per-cell audio read never-uploaded plasmaBuffer[1..8] → FFT bins | ✅ |
| chromatic-folds-gemini | prismatic fold dispersion; origami crease lighting | 12.9 / 43.5 | noise read time (grey after 300 s); feedback/ripple strength read mouse x/y; vortex at ripples[0]=(0,0); fine folds sampled off-texture; fold-zero darkening over 70 % of frame | ✅ |
| contour-flow | streamline injection; luma iso-line ink | 52.7 / 16.8 | none (meanL 0 was the harness without an input image) | ✅ |
| directional-blur-wipe | luma-keyed front; stroboscopic ghosts; exposure persistence (exact C) | 8.0 / 22.0 / 14.7 | pixel-centred uv | ✅ |
| kimi-ripple-touch | caustic focusing; low-sun glint; crest foam in A.b | 7.5 / 6.5 / 12.2 | wave step ×1/3600 (dead), velocity clamp, trough wash on clear, ripple count ignored, bass wave died | ✅ (first pass) |
| vaporwave-horizon | striped sun; two-tone neon bloom; mirror floor of displayed sky | 24.9 / 46.9 / 40.5 | no A write / no ACES despite tag, alpha 1.0, bass×time grid jumps | ✅ (first pass; ~2× slower, re-time on GPU) |
| gen-erosion-strata | creeping normal faults; mineral drips; reflecting pool | 65.3 / 11.4 / 26.0 | water at top + inverted pointer | ✅ |
| gen-cosmic-velvet-hypnosis | tufted buttons; breathing zoom; complementary afterimage | 16.1 / 99.8 / 68.8 | horizontal seam; ACES negatives | ✅ (hue layout mirrored vs HEAD) |
| spec-hypercube-projection | 24 real faces as glass; 4D-depth vertex glints; 4D refraction | 8.1 / 1.7 / 4.8 | mids read but unused | ✅ (glints small: ~20 % of cube area) |
| cyber-grid-pulse | pulse-filled neon cells; mouse-pull chroma fringes | 5.5 / 7.2 | dead extraBuffer spring; plasmaBuffer[1..8] audio; pixel-centre samples | ✅ |

Gates: wgsl_precommit_gate 10/10, verify-naga-wasm --files 10/10, audit:extrabuffer PASS, dead-sliders 0, check_duplicates OK, Vitest 1821/1823 (1 fail = `shader search index > covers every entry with an embedding`, also fails on origin/main 0a75d397), npm run build OK.
Real-GPU visual QA + thumbnails: external, pending.
