# Coordinator review — weather / wind / condensation ten

Fail the file if any box is empty.

| ID | Card first | Ideas pointable | KEEP VERBATIM | Diff not ≥70% boilerplate | No cloned overlay | A packing matches C | Params exact | Springs native-only | Naga + audits |
|---|---|---|---|---|---|---|---|---|---|
| snow | pass | tumble + land fade | pass | pass | pass | raw bank A.r | pass | none | pass |
| raindrop-ripples | pass | waveC + caustic | pass | pass | pass | height/prev A.rg | pass | none | pass |
| bubble-wrap | pass | hex + neighbor pop | pass | pass | pass | popped/time A.rg | pass | none | pass |
| pixel-wind-chimes | pass | hinge + Z-sort | pass | pass | pass | display RGBA | pass | none | pass |
| sim-smoke-trails | pass | confinement + cooling | pass | pass | pass | density/temp/vel | pass | none (existing ripples as seeds only) | pass |
| radiating-haze | pass | bleed + mouse origin | pass | pass | pass | persist A.r | pass | none | pass |
| radiating-displacement | pass | mouse radiate + RGB phase | pass | pass | pass | display RGBA | pass | existing click ripples only | pass |
| interactive-pixel-wind | pass | lumaW + shadow | pass | pass | kept existing palette; did not add more IQ | display RGBA | pass | none | pass |
| lidar | pass | A echo + ticks | pass | pass | pass | echo A.r | pass | none | pass |
| rain-lens-wipe | pass | meniscus + bead | pass | pass | pass | wipe A.r | pass | existing click wipes | pass |

**Batch: PASS 10/10**

Notes:
- radiating-haze / radiating-displacement Uniforms order was swapped vs engine; canonicalized so JSON names match `zoom_params`. Extra colourMode/pulse fields now come from audio/time, not stolen sliders.
- lidar echo moved B→A so A→C copy keeps persistence.
- rain-lens-wipe is a second pass on an already-capable rain-glass shader; additions are native (meniscus/bead), not a costume.
- Cloud VM has no GPU. Real-GPU visual QA remains external.
