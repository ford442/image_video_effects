# Fork C notes

## digital-glitch-explosion
Kept verbatim: block shift + scan tear, per-channel prismDisplace, ripple chroma waves, randomBitFlip, posterize, C smear, all 4 param roles; JSON params byte-exact.
Rescues: posterize levels = 16 - time*decay pinned at 2 levels after ~15 s (t=60 default was 8 flat primaries) → fract cycle 16→3 and reset; dead plasmaBuffer[1..8] band tint removed; dead extraBuffer[133..138] spring removed ("spring-cursor" feature dropped).
Ideas in diff: (1) macroblock datamosh (moshSeed block → textureLoad C along -shift vector, history-guarded); (2) bit-plane slice (planeSeed → bit 5..7 of each byte); (3) bass shard burst (shardDir/shardPush from cursor, prismBoost).
A packing: ACES display RGB + energy (a), unchanged.
Render (256px, T0=60, defaults): HEAD meanL 0.288 posterized; new 0.43 (≈HEAD at t=0, 0.425), bass 0.9 shows radial shard streaks. meanA 1.0 (alpha formula unchanged; saturates on the opaque test image).

## crt-tv-stipple
Kept verbatim: curveUv, stippleGrille triad/blue-noise jitter, scanlines, halation, vignette, flicker, param roles; JSON params byte-exact.
Rescues: phosphorDecay pow(c,1/rate) (blue^0.1) lifted everything to a cyan-grey wash (orange disc rendered grey) → removed, exposure 1.9 restores brightness; bezel early return now writes A; dead extraBuffer spring removed.
Ideas in diff: (1) P22 per-channel afterglow max(color, prev*persist) applied post-ACES so persist<1 cannot latch (Phosphor Glow slider scales it); (2) rolling hum band (humPhase/humBand, mids speed); (3) radial convergence error (convDir on R/B samples + conv shift of R/B stipple dots, scales with Barrel).
A packing: ACES display RGBA (C = afterglow colour).
Render (T0=60, defaults): HEAD meanL 0.496 washed cyan; new 0.316, true colours, triads visible; barrel=1 shows corner R/B fringing. meanA 0.918 (HEAD 0.918).
Catalog overlap: another shader has "P22 split-decay trails"; here it is applied to stipple triads, kept.
