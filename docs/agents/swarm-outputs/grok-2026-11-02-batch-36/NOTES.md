# Notes — cursor/batch-36 halftone, stipple, and ink (2026-11-02)

Second pass on files that already had a print or ink look, plus a first upgrade of `engraving-stipple-blue-noise` (it had no ACES and did not write A). New ideas are additive. Saved `params` stay byte-exact. No new spring. `film-cross-process` keeps the enlarger spring it already had.

`graphic-novel` is `public/shaders/graphic_novel.wgsl`.

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| halftone | elliptical AM dots, 15/75/0/45 screens, colorMode split, mouse focus, highlight skip, overprint gain, plate offsets, paper grain. Dot Scale / Contrast / Color Mode / Screen Angle | ACES display RGBA | Murray-Davies midtone gain; black trap under K |
| halftone-reveal | reveal disk, loupe magnify, depth dot scale, CMYK convert, four angles, per-plate gain, highlight knockout, paper tint. Dot Size / Angle / Reveal Size / Magnify | ACES display RGBA | loupe twist; bitten dot edge |
| engraving-stipple | contour / hatch / cross, burin taper, roulette, hash stipple, held burin, click rings, ink pool. Line Density / Stipple Scale / Contrast / Light Rotation | telemetry RGBA (ink, hatch, burin, alpha). ACES on the display write only | foul bite; wipe sheen |
| engraving-stipple-blue-noise | plastic-constant jitter, primary and secondary dots, luma-sized radius, threshold mask, burr hash, plate tone, highlight tint. Density and Dot Size keep their double duty on x and y | ACES display RGBA. This file previously wrote no A. C is unread | drypoint shoulder; raking shadow |
| spec-blue-noise-stipple | blue-noise jitter, dark-cell packing, neighbor skip, golden tertiary, click splatter, paper ground. Dot Scale / Dot Size / Color Variation / Dot Density | ACES display RGBA | void push; stacked pigment |
| stipple-render | blue-noise cell, luma-sized dots, Lloyd luma offset, wet radius, exact-C wet memory, contour hatch, color reveal. Dot Scale / Contrast / Wet Ink Radius / Color Reveal | ACES display RGBA. C is an exact load of display colour | downhill stipple; coffee ring |
| cyber-halftone-scanner | 15/75/0/45 AM cells, RGB split, scanline, glitch skip, click bursts, pointer bloom, hard-dot, plasma tint. Dot Scale / Scan Speed / RGB Split / Brightness | ACES display RGBA | interlaced field shear (§12.2B); lamp dropout (§12.2B) |
| polka-dot-reveal | density falloff, chain-dot merge, drag stretch, per-cell jitter, depth / luma / edge alpha, bass envelope. Intensity / Speed / Scale / Detail | R bass envelope, GB smoothed mouse, A trail alpha. ACES on the display write only | chain holes; dot pip |
| polka-wave | four-plate loop, fixed angles, wave from the pointer, click fronts, invert, dot gain, rosette spectral. Grid Density / Wave Amp / Wave Freq / Wave Speed | ACES display RGBA | crest squash; rosette eye |
| rotoscope-ink | edge threshold, posterize, ink density, shade mix, edge-magnitude weight, hold-flats, brush sine, fast-edge chroma, mouse ink | telemetry RGBA (outline, motion, mouse, alpha). ACES on the display write only | double weight; cel boil |
| film-cross-process | per-channel S-curve pivots, skew, shadow desaturate, grain seeds, vignette, highlight cyan-green crossover, developer spring in extraBuffer[133..138], chemical rings. Contrast Punch / Colour Skew / Film Grain / Vignette | ACES display RGBA | density-weighted grain (§12.2A); shadow teal |
| graphic-novel | adaptive contour, shadow-side weight, spot blacks, 45° hatch plus the crossing set, screen dots, registration, paper fiber, held ink, click rings, C history mix. Dot Size / Edge Strength / Color Levels / Paper Grain | ACES display RGBA. C is an exact load of display colour | feather into the spot; panel rule |

Formula use: Field interlace and Dropout bursts only on `cyber-halftone-scanner`. Density-weighted grain only on `film-cross-process`. No other §12.2 row in this batch. No new spring.

Floor: `#include "_prelude.wgsl"` on all twelve. Eight pasted headers were swapped with `migrate_to_prelude.py` before the idea edits. 16×16. Exact C where C is read (`stipple-render`, `polka-dot-reveal`, `graphic-novel`). `x-meta.upgrade.params` added for `engraving-stipple-blue-noise` and `polka-dot-reveal`. `audio-reactive` and `upgraded-rgba` added on the blue-noise engraving, which now reads `plasmaBuffer[0].x` and tone-maps the display. Saved params unchanged.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new (full catalog audit pass), dead sliders 0 new on these twelve, lists regenerated. Vitest: the full run passed 1529 tests; three device-loss cases in `RendererManager.test.ts` failed while `npm run build` ran beside the suite. That file re-run alone passed 45/45, which is 1532 passed and 1 skipped. `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
