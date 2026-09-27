```
SHADER: gen-sonoluminescent-chrono-geode-matrix
IDENTITY (one sentence): a spinning KIFS-folded crystal geode shell (clipped to a sphere) around a
  sonoluminescent bubble core that collapses every cycle, flashes blue-white and fires a ballistic
  shockwave shell, all swirl-smeared by C motion-blur trails.
KEEP VERBATIM: sdGeodeShell fold (4 iters, axis (1,1,1) rot 0.5, clip length(sp)-1); bubble core
  (exp-collapse coreR, noise churn); closed-form flash cycle (flashPhase/collapse/regrow); ballistic
  shell ringR; eased warpTime + orbital camera; fresnel iridescence; volumetric plasma_acc; swirl-
  advected C trails (raw HDR, decay 0.86-0.05*w, clamp 5.0); all 4 slider roles and mappings
  (Intensity / Speed / Scale / Mouse Influence) and the updatedParams block byte-exact; press-to-repel
  mouse; alpha/depth semantics.
ADD (3 native ideas — each couples two subsystems this file already has):
  1. Shock-front crystal ignition — the ballistic shell currently only glows in the void; where the
     front crosses the geode surface radius it now ignites a hot incandescent band on the crystal and
     jolts the shards outward as it passes (shell x geode, shading + SDF displacement).
  2. Collapse-deposited agate strata — real geodes are banded chalcedony laid down over time ("chrono");
     concentric radial strata on the geode material advance one band spacing per collapse cycle,
     eased by `regrow`, and the freshest band catches the flash colour (flash cycle x geode shading).
  3. Flash translucency through thin shard walls — thickness probe along -n (5 SDF samples) lets the
     core's collapse flash bleed through thin fractured walls (core x geode; the description promises
     the fracture "reveals" the core, HEAD only had a reflection dot product).
FORBID on this file: springs, click-ripple shockwaves (it has its own ballistic shell), IQ palette stamp,
  a new particle system, bismuth/hopper/oxide motifs (owned by siblings), changing the fold or camera.
A PACKING: raw HDR history RGB (pre-ACES, clamped <= 5.0) + semantic alpha — unchanged; C is read raw,
  writeTexture gets ACES. Consistent, so HEAD packing wins.

SILENT BUG FIXED: "bass-transient kick" in extraBuffer[133..135] never persisted (the engine re-uploads
  the whole 256-float scratch each frame, zeroing [133..255]) AND the single-thread write raced every
  other workgroup's read of [135] in the same dispatch -> per-16x16-tile kick flicker under audio.
  What it actually computed on the writer thread was prevBass=0, prevT=0, dt=0.1, kickE=min(2.5*bass,2).
  Replaced with that same value computed stateless per thread (no buffer writes, no race). Audio=0 look
  unchanged (kick was 0). Header no longer claims transient detection / dt-integration.
```

Notes: Idea 3 threshold chosen from a numpy port of the geode SDF (96x96 rays, 1666 hits): thickness-probe
sum percentiles p5 0.87 / p50 1.3 / p95 6.0 at h=0.035k -> smoothstep(1.2, 5.0) keeps bulk crystal dark and
lights only thin shards (an unthresholded clamp saturated ~30% of the surface). JSON: features +mouse-driven
(press repels shards), +upgraded-rgba; "bass-transient-kick" renamed "bass-kick" (the transient never existed);
updatedParams untouched. Look not GPU-verified (no adapter in this VM).
