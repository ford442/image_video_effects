# NOTES fork B — scanline-drift, xerox-degrade (second pass)

## scanline-drift
IDENTITY: horizontal strips drifting sideways with RGB split, tape shear, h-sync porch. KEEP: stripDrift recipe, ideas 1–3, params, click tears. FORBID: generic ripples/palettes.
ADD: (4) head-switching skew band — bottom 2.5–6% (Jitter scales height) bends sideways per field, bass kicks it, ragged dark edge;
(5) tape dropout streaks — short white comets on single 2-px scan rows, rehashed 8×/s, trailing in the drift direction; treble/pointer band raise the count.
Rescue: dead extraBuffer[133..138] mouse spring (zeroed every frame) removed; band uses mouse.y directly (same runtime behaviour, no serial thread-0 work).
Diff vs HEAD @256: ~2–3% px >12/255 (localized: bottom band + dropout rows, by design).

## xerox-degrade
IDENTITY: high-contrast photocopy with halftone, toner bands, Mach halo, generation loss. KEEP: sigmoid/halftone/ideas 1–3, params.
ADD: (4) platen dust specks + hair scratches — static (no time term) ink dots/lines, density follows Grain; compound through C;
(5) generation creep — previous generation (C) read through a tiny slowly-drifting rotation + 0.6 px shift, so copy-of-copy chains skew off-square (bass nudges).
Rescue: same dead extraBuffer spring removed (pointer direct).
Diff vs HEAD @256: 11% px >12/255.

Timing @512 (load high, noisy, frameMs): scanline 0.72–0.92× HEAD, xerox ~0.62× HEAD — no regression.
Gates: verify-naga-wasm --files 2/2 valid; SwiftShader render no NaN, alpha unchanged. JSON descriptions appended. Not done: real-GPU look, shader lists (coordinator).
