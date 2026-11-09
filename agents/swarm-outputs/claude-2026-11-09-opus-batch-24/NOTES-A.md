# Fork A notes
- pixel-depth-sort: kept network/spans/drip/ramp/CA. Ideas 4 (contact occlusion) and 5 (aerial haze) are `// Idea 4/5` comments before `mix(bg.rgb, sortedColor, hasSpan)`. Packing unchanged. No HEAD bug found. minirender depth is flat 0 → whole frame takes the bg path, so render is identical to HEAD; real-GPU check needed.
- mouse-pixel-sort: kept everything; Idea 3 (radial comb, axisMix) and Idea 4 (headGlint) in main. Only active under/near the pointer; default idle look nearly unchanged. Packing unchanged.
- luma-pixel-sort: HEAD bugs fixed: Sort Angle dead (rotating isotropic disk) → anisotropic disk (Idea 1); no ACES despite upgraded-rgba → ACES in writeOutputs; header rewritten to 7-line form. Idea 2 sticky spans reads exact C alpha. A = ACES display RGBA, .a = sorted coverage (dim path 0.3·a). Verified angle 0 vs 0.5 now differ in minirender.
- Gates: precommit gate 3/3 pass, dead sliders pass. JSON features already truthful; params untouched.
