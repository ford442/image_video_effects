# opus/batch-31 — fork C Idea Cards (written before any WGSL idea edit)

```
SHADER: gen-erosion-strata
IDENTITY (one sentence): domain-warped sedimentary bands in earth tones, carved by erosion channels, with veins, fossils and a wet water line.
KEEP VERBATIM: fbm/voronoi kernels; lh/li/lf layer stack; 5-colour era palette; erosion/density/veins/water param roles;
  existing ideas (bedding contacts, cross-beds, ripple marks, iron concretions); quake ripples; held-pointer glow.
ADD (new, second pass):
  1. Normal faults — two slanted fault planes that drop the layer stack on the hanging-wall side (throw creeps with time,
     jolts with bass), with a dark crushed gouge line along each plane. Strata get faulted; it is the same layer stack offset.
  2. Desert-varnish streaks — dark manganese drips hanging down from each bed's top contact, stronger where erosion
     exposed the face. Canyon walls streak exactly like this.
  3. Pool reflection — below the water line the band colours of the mirrored height are reflected with a ripple wobble,
     so the Water Level slider owns a still pool, not only a tint.
RESCUE: water line was upside down (y-up maths on y=0-top screen: the "wet" band sat at the TOP of the frame and the pointer
  moved it inversely). Flip to y-up for the water/pointer term.
FORBID on this file: springs, IQ palettes, neon, raymarching.
A PACKING: ACES display RGBA (unchanged; C read back as colour history).
```

```
SHADER: gen-cosmic-velvet-hypnosis
IDENTITY (one sentence): a soft log-spiral hypnosis well of crushed velvet arms with chromatic runners and nested seams.
KEEP VERBATIM: spiralPhase / velvet / rings / runner / counterSpiral / moire / velvetWeave formulas; existing ideas
  (pile sheen, octave wells, counter-runner, seam glints); click halos; drag swirl; history smear; param roles.
ADD (new, second pass):
  1. Tufted buttons — upholstery tufting at the log-polar lattice where the arms cross the octave seams: a dimple
     shadow with pinched pleats and a button highlight. Pins the velvet like a tufted cushion; rides inward with the wells.
  2. Breathing trance zoom — the whole well inhales/exhales in log-radius (a slow periodic dolly, deepened by bass),
     the classic hypnosis-spiral pull layered onto the existing spin.
  3. Negative afterimage — in the dark troughs between arms, the complementary colour of the C history glows faintly,
     like the after-image left by staring at a spiral.
RESCUE: atan2 branch-cut seam on the -x axis: hue used angle/TAU through a non-integer-frequency palette, and moire used
  spiralPhase*0.55 (non-integer angular frequency) — both jump at angle=±π. Mirror the hue angle and round the moire
  angular frequency to an integer. Clamp HDR ≥0 before ACES (palette G dips to −0.05 → ACES maps negatives to ~0.2 glow).
FORBID on this file: springs, generic ripple shockwaves beyond the existing halos, raymarched creatures.
A PACKING: ACES display RGBA (read back as colour history) — unchanged.
```
