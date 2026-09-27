```
SHADER: gen-sentient-ferro-silicate-swarm
IDENTITY (one sentence): a grid-repeated swarm of liquid-chrome ferro beads (one particle per 0.15-uv cell) pushed by
  curl flow, pulled by a brutalist KIFS SDF, shattered by bass, with fresnel oil-spill iridescence, velocity heat tint
  and a short temporal smear.
KEEP VERBATIM: hash2/hash3/noise3/fbm/curlNoise/kIFS/smin/brutalistSDF; gridScale 0.15 domain repetition and per-cell
  rnd/rnd3 particle offsets; curl push * (1 - rigidity); per-cell SDF attraction * rigidity * 0.02; bass * shatter * 2
  curl shatter; chrome spec pow 128 + fresnel^2; oil-spill cosine hue * iridescence; cyan->orange heat on vel * bass;
  density brightening; CA on vel; 0.25 temporal blend. Param roles: x Swarm Cohesion, y Fractal Rigidity,
  z Shatter Force, w Oil-Spill Iridescence (updatedParams unchanged).
ADD (2–4 native ideas):
  1. World-scale silicate assembly — the brutalist SDF is only ever evaluated in cell-local space, so the promised
     "self-assembles into brutalist architecture" never appears. Sample the same brutalistSDF at each cell's WORLD
     centre (slowly rotating slice) with an assemble/dissolve breath; cells inside the building lock their particle
     onto the lattice site (rigidity = snap strength, curl suppressed). Shatter Force sets how deep the dissolve
     phase eats the building; bass still blows locked cells loose. Visible at audio 0 (time-driven breath).
  2. Quartz facet crystallization — locked beads stop being round chrome: their normal is quantized to a hexagonal
     (6-sector x 3-tier) quartz facet set with bright facet-edge glints. Free beads stay liquid chrome. The swarm's
     phase change ferro -> silicate is the picture's new beat.
  3. Si–O bond struts — between a locked cell and each locked 4-neighbour, draw a glassy strut from particle centre to
     particle centre (thickness from Swarm Cohesion), so the assembled building reads as a bonded silicate network
     rather than 84 isolated beads.
  4. Curl-advected wake — the temporal feedback samples dataTextureC upstream along this cell's own curl vector
     (fuses the curl field with the temporal smear), so free fluid streams in comet-like wakes while locked crystal
     stays crisp (wake offset scales by 1 - lock).
FORBID on this file: Rosensweig spike lattice / |psi|^2 filaments or contours (entangled-ferrofluid owns them);
  field lines, dipoles, magnetic surface spikes (spectral-ferrofluid owns them); spring cursor, click-ripple
  shockwaves, IQ palette stamp; replacing the cell-grid swarm with a raymarched scene.
A PACKING: ACES display RGBA (alpha = swarm occupancy: bead/strut/lock coverage). C is read back as display RGB, so
  the blend happens in display space (consistent encode/decode).
SILENT BUGS FIXED:
  - dataTextureA was never written, so C was always zero and `mix(prevCol, col, 0.25)` rendered the whole effect at
    ~25% brightness. A now stores the blended display colour.
  - extraBuffer[0] (engine-reserved, CPU-overwritten) was read + written as a bass envelope from thread (0,0) — a race
    and an illegal write. Replaced with stateless plasmaBuffer[0].x.
  - Mouse "magnetic anomaly" was computed in cell-local coordinates against a screen-space cursor, so it was a
    uniform bias on every cell (and mouseY skipped the aspect mapping). Now the cursor is mapped into each cell's local
    frame, so beads near the pointer lean toward it and far cells are untouched (Cohesion still scales it).
  - Depth wrote constant 0; now writes a truthful relief (lock/occupancy).
```
