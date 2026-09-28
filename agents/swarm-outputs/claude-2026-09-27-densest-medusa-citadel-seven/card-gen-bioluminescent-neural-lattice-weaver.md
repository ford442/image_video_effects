```
SHADER: gen-bioluminescent-neural-lattice-weaver
IDENTITY: a camera orbits an endless grid of hollow octahedral shells blended into noise-sheet neural membranes, pulled
  toward a cursor gravity well, lit with a cosine bio-palette.
KEEP VERBATIM: octahedral lattice SDF + per-cell rotation (L141-158), neural sheet SDF (L160-168), blend + energy
  (L170-190), gravity well (L134-139), camera orbit, glow accumulation (L298), ACES, click synapse bursts (keep them),
  4 slider roles (x synapse density -> noise freq, y growth speed, z lattice hardness -> shell size, w bioluminescence
  emission), saved params. Leave the stale JSON `controls` array (not params) alone; note it.
ADD (native ideas):
  1. Charged cage cores — every hollow octahedral shell (L153-154) holds a glowing core whose charge is the neural
     field sampled at that cell's centre (cell_id already computed), accumulated in the march glow (L298) so it shines
     THROUGH the struts: the lattice becomes a grid of lanterns fed by the membrane.
  2. Click spin cascade — a click spins each lattice cell (adds angle to the per-cell rotation at L147) with a delay
     proportional to the 3D distance from the click point to that cell, decaying with age = time - ripple.z (never
     ripple.w). The screen-space synapse burst (L263, L356) becomes a 3D wave rolling through the cage. Stateless.
  (Do NOT name it a domino — "staggered domino row delay" exists; do not call anything photoelastic.)
FIX/WIRE:
  - extraBuffer[133..138] spring (L228-251) is a no-op (zeroed every frame) and racy (INIT seen before X/Y -> well at
    (0,0) in some tiles). Remove the writes; use raw mouse. Correct the header claim on L9.
  - Double tone map (L359-362): C holds ACES output mixed pre-ACES. A = HDR, C decoded as HDR, ACES once.
  - Depth inverted (L375 writes t/max_t, miss 1) -> near 1, miss 0.
  - time * y * (2.6 + bass*2.2 + held*1.5) (L128-129, also L177, L274, L324): phase jumps hundreds of rad with bass at
    large time -> phase from time*y only; audio modulates amplitude/brightness, not phase.
  - SDF gradient ~4 (noise layers) vs 0.7 step (L307) -> speckle; lower the step factor / clamp; guard t >= 0 (moving
    sheets over the camera make t go negative).
  - Background (L312) may go negative -> max(,0).
  - Header rewritten to canonical shape with Ideas + A packing; JSON gains a true features array.
FORBID: action-potential runners, saltatory/Ranvier, synapse flash at nodes, integrate-and-fire, refractory afterglow,
  axon fronts, dendrite web, vesicle release, aequorin/GFP, Bragg colour, line-defect waveguides, dual-lattice vertex
  glow, triple-junction glow, domino, photoelastic, spring cursor.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha.
DEFAULT-LOOK SHIFT: less speckle; lanterns inside every cage; camera/pulses no longer stutter with music.
```

## Refinement (implementing agent, 2026-09-27)

Verification of the audit claims (numpy port of map()/march in the session scratchpad):
- Spring no-op/race (HEAD L226-252): TRUE. Removed; raw `zoom_config.yz` drives well, camera tilt, halo.
- Double tone map (HEAD L359-362): TRUE. A now stores HDR (pre-ACES, post-feedback) + alpha; C is blended as HDR; ACES once.
- Depth inverted (HEAD L375): TRUE. Now hit -> clamp(1 - t/max_t, 0.005, 1), miss -> 0.
- Phase jumps (HEAD L128-129, L177, L274, L324): TRUE. growth phase = time*y*1.3 (+bass*0.3 bounded),
  pulse rate fixed 6.0 (treble scales pulse brightness), camera angle time*0.75 + bass*0.25, hue time*0.3 + treble*0.25.
  At audio = 0 / not held all four phases equal HEAD exactly. Held no longer speeds growth (it was a phase jump
  on press); held still deepens the well and pulls the camera in.
- Step 0.7 speckle: PARTLY. At default density (x=1) 0.7 converged fine on 48x27 test frames (|grad| p99.9 ~2.7).
  At x=3 (|grad| ~8) 0.7 lost 25% of hits. Fix: step_k = clamp(1.4/(0.6+2.2x), 0.3, 0.7) (0.5 at default,
  same agreement), 110 iterations.
- t < 0 (HEAD): TRUE and worse than stated — camera sits inside a membrane in ~22% of frames at default
  (map(camera) < 0 over t in [0,200]); HEAD then marched backwards and shaded surfaces behind the camera
  (all rays t<0 in some test frames). Fix: forward exit-walk while inside, then a t floor at the exit point.
  Camera/SDF geometry deliberately NOT moved (would change identity).
- Background negative (HEAD L312): TRUE (red channel < 0 at corners). max(, 0).
- Stale JSON `controls` array: left alone as instructed. Description updated (spring claim false).

Idea changes vs draft:
- Idea 1 refined: numpy shows median hit distance ~0.2 units at default (camera embedded in the membrane web,
  lattice is 0-21% of hits), so march-accumulated core glow would almost never be seen. Cores are instead
  rendered as back-light at the hit: walk 4 cells along the view ray, each core adds
  charge * exp(-perp^2/sigma^2) * attenuation — shells glow like lantern paper, membranes glow with the cages
  behind them. Charge = 1 - smoothstep(0, 0.32, |n1(cell centre)|) (~30% of cores lit >0.5), + cascade flare.
  Cores sit at octahedron centres (primary lattice points), not dual-lattice vertices.
- Idea 2 as drafted; origin = click ray through the camera *as it stood at click time* (rp.z), 1 unit deep,
  so the wave is world-fixed while the camera orbits. Quarter turn = octahedral symmetry, so no snap when the
  wave expires; CASCADE_RADIUS 6.0 < 3.2*(2.6-0.55) guarantees no cage is mid-turn at expiry. Youngest 4 clicks.

Where the ideas live (final WGSL):
- Idea 1: `coreCharge` L167-173, `cageLanterns` L280-307, applied in shading L460-463, alpha term L491.
- Idea 2: constants L37-43, `cascadeSpin` L146-165, spin into rot_angle L193-194, flare energy L231-232,
  cascade origins in the ripple loop L336-369.

Refused: nothing from the FIX list. Did not add march-loop core glow (invisible, see above).

STATUS: final
