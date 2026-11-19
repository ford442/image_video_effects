# NOTES fork A — emergent-calligraphic-weave (first pass), gen-neuro-kinetic-bloom (second pass)

## emergent-calligraphic-weave
IDENTITY: sumi-e ink field advected along a curl-noise flow, tan/blue wash palette, dry-brush sparkle. KEEP: curlField, sliders, palette, A packing. FORBID: ripples/IQ palettes/neon.
ADD: (1) streamline strokes — ink ribbons on isolines of the curl stream function (curlField now also returns the mean of its 4 taps, no extra noise), brush-load noise lifts strokes so they start/end;
(2) tamari pooling — dark blue-black bead where stroke behind is wet and ahead dry;
(3) nijimi fiber wicking — one C tap along the fibre axis (side flips per frame).
Rescues: (a) HEAD multiplied the STORED field by the per-pixel dry-brush grain every frame → compounded to salt-and-pepper static, no strokes; now dry-brush gates only the fresh deposit. (b) alpha multiplied by depth → ≈0 on generative (meanA 0.007); now (0.6+0.4·depth) → meanA 0.12. Uniform background deposit 0.035→0.012 so ribbons read.
Timing (load 16+, noisy, 256², 4 rounds): ~1.2–1.75×, median ≈1.3× (cheap absolute: ~20 ms vs 16 ms). Slightly over target; extra cost = 1 vnoise + 1 tap.

## gen-neuro-kinetic-bloom
Earlier 4 ideas kept verbatim. ADD: (5) vesicle release — bouton flash + expanding vesicle shell when the conduction phase hits the terminal (in map's z channel); (6) astrocyte haze — violet glow accumulated in the march loop near tissue, mids swell it.
Rescue: sprung cursor lived in extraBuffer[133..138] (re-uploaded/zeroed every frame → spring never held state); replaced with direct cursor, extraBuffer writes removed (coordinator: extrabuffer audit baselines may need regenerating).
Timing (load 16+, very noisy): new/HEAD rounds 0.34–2.2×, median ≈0.9×.

Gates: verify-naga-wasm --files 2/2 valid; SwiftShader renders finite (0 NaN). JSON features/descriptions appended. Not done: real-GPU look, mouse/click render, shader lists (coordinator).
