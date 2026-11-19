# NOTES — fork C (sonnet/batch-41)
Renders: SwiftShader, SRC=img, saved defaults 0.5,0.5,0.5,0.5. Scratch: scratchpad/forkC/. No real-GPU claims.

## gen-showcase-nebula-core
- Prelude: migrated by coordinator (header-only). KEEP VERBATIM held (3 earlier ideas untouched). A packing unchanged except C is now read at an advected sub-pixel position (4 exact textureLoads, manual bilinear).
- HEAD: fine (idle meanL .286/std .213, held .308, audio .706). No rescue. Fix (not an idea): clamp ≥0 before acesToneMap (bass rings and `b − caStr` could go negative → ACES(neg) bright).
- Idea 4 stellar-wind streaming (§12.2 curl-noise advection), `// ── Idea 4` before the C load: curl of a vnoise2 potential (finite diff) ×0.7 px + outward wind ×0.25 px, scaled by dims.y/384. First version (integer fetch, 1.6/0.9 px) produced blocky square smears — replaced by bilinear + weaker flow. Visibility (60f): 27.6 % / mean .071 @192; 22.6 % / .043 @576 (30f).
- Idea 5 Strömgren shell (native), `// ── Idea 5` before mouse glow: teal [O III] front at R = .55 + .3·ionization + .22·(nebula−.5), hidden by pillars. 15.0 % / .011 @192; 14.8 % / .011 @576.
- Default look: idle meanL .286→.332, std .213→.204; held .308→.323; audio .706→.755. nan 0, A16 ok.
- frameMs (interleaved min, 4 rounds @256): ratios 1.03, .90, 1.13, .88 → ≈1.0×.
- Slider sweep @128/8f changes meanL only slightly for all four (same as HEAD's structure-only sliders); dead-slider audit PASS.
- Gates: precommit pass, naga-wasm pass, dead-sliders pass. JSON unchanged (description already long; could mention new ideas — left to coordinator).

## gen-quantum-fluorescent-nebula-anemone
- Prelude: migrated by coordinator. KEEP VERBATIM: beads/afterglow/oral disc kept; beads re-parameterised along the arm (`along*7` instead of ring angle) because the ring they rode no longer exists.
- **HEAD defect confirmed**: washed-out white disc, idle meanL .886 std .088, no tentacles visible. Cause: `length(rot(angle)*p + (sway,0)) − 1.6` is the same r≈1.6 ring for every i (rotation preserves length) → 22 stacked rings; plus background wash alone ≈ .72 meanL on a black source.
- Rescue 1: real tapered radial arms (along/lateral in rotated frame, bending sway, lenMask); rim via `rimX^4` (no pow); background terms (nebula, nebula2, fog, quantum, rays) gathered in `bg` × BG_GAIN 0.4; readTexture `prev` 0.86→0.4. New idle meanL .648 std .143 (arms clearly readable, centre still saturates).
- Idea 4 acrorhagi tip bulbs, Fresnel–Schlick cuticle (§12.2 Schlick): bulb at each arm tip, cosθ from spherical profile, F=.04+.96(1−cos)^5 drives hue-shifted sheen. Branch-guarded. 4.66 % / .009 @192; 4.61 % @576 (tips are local — ~all bulb pixels).
- Idea 5 touch retraction (native): ripple loop moved before the arm loop; arms within ~0.3 uv of a click (age window 0..6 s, `age=time−r.z`, no r.w) shorten 55 % / thicken, re-extend ~2.5 s. Synthetic ripple copy: 11.5 % / .0086 @192, 11.5 % @576.
- held .887→.707, audio .907→.657 (HEAD values were saturation). Sliders all move meanL (.60–.76 range across sweeps).
- frameMs: noisy (other forks loading): before trim 1.23/1.26/1.46/1.46; after branch-guarding bulbs + removing unused per-iteration `normalize(mouseDir)`: 1.46/1.24/1.01/1.93 → median ≈1.35×. Cost is mostly the rescue (arms add 2 smoothsteps + sin per tentacle ×22). **Open: coordinator re-time alone; if >1.3× drop the lateral bend `sin` (use sway·along only).**
- JSON: workgroup_size says [8,8,1] but WGSL is 16×16 (HEAD mismatch, not changed). `params` absent (only x-meta.upgrade.params) → dead-slider audit blind spot (scans 0 defs); sliders verified by sweep instead. No tag changes.
- Gates: precommit pass, naga-wasm pass, dead-sliders pass (vacuous, see above).
