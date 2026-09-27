```
SHADER: gen-chromodynamic-plasma-collider
IDENTITY: a hyper-speed flight down a warped magnetic containment tunnel of obsidian rings, with a plasma beam on
  the axis, magenta collision bursts, a blue containment band, anomaly ray-bend toward the mouse and click shells.
  (At HEAD the viewer sees an almost flat dark-blue screen: every ray hits a solid disc at t~0.8, step 6.)
KEEP VERBATIM: tunnel-warp camera + map() warp lines, anomaly rd bend, 30-step volumetric plasma loop (step 3.3,
  HEAD burst phase gate fract(z*rate*0.1 - time*5) < 0.1 with magenta (1,0.2,0.8), containment band 2.5..3.0),
  click-collision shells, obsidian base colour, alpha formula, depth convention, 4 slider roles
  (Ring Density / Collision Rate / Anomaly Pull / Tunnel Warp), saved params byte-exact.
FIX (silent bugs, change default look — flag for GPU QA):
  - map(): max(length(xy)-3, |z|-0.2) is a SOLID DISC every 2 units -> every ray hit at step 6, t=0.8.
    Now hollow washer rings max(abs(r-R)-0.25, |z|-0.2) plus an obsidian sleeve wall at R+1.2 (the unused
    base_tunnel was the intended tunnel). numpy march: centre-ish rays now reach rings/wall at t~7..80 instead.
  - normal was normalize(p.x,p.y,0) in unwarped space; reflect(rd,n).z == rd.z > 0 so spec was ALWAYS 0.
    Now central-difference SDF normal, spec toward the beam axis (the beam is the light).
  - plasma loop ignored hit t (plasma behind opaque rings showed) -> loop stops at the hit.
  - beam / containment band measured length(vp.xy) in UNwarped world space while rings are warped (beam drifted
    off the tunnel up to 1-4 units) -> measured from the warped axis.
  - 30/ring_density guarded with max(,1).
  - A stored ACES colour, then C was blended in as HDR and ACES'd again (double tone-map) -> A now stores the
    pre-ACES HDR radiance; C decodes as HDR (consistent).
  - constant "chromatic aberration" (col.r += 0.003, not an aberration) replaced by Idea 3.
  - extraBuffer[133..138] spring: inert (zeroed every frame -> mouse == rawMouse). Left as-is, noted.
ADD (native ideas):
  1. Bunch-crossing bursts at the ring planes — for each containment ring ahead of the camera, the ray/plane
     intersection is evaluated analytically; each time HEAD's bunch train passes a ring (same phase
     s = z*rate*0.1 - 5t) a luminosity lottery (p rises with Collision Rate) decides whether a collision fires:
     a magenta core flash + debris shell expanding to the ring radius, and the hit ring's rim glows while its
     event is young. Fuses the bunch phase with the ring lattice from map(). Alias-free (no 3.3 step).
  2. Magnetic beam steering + betatron wobble — the beam axis (used by the plasma loop, the crossing bursts and the
     light) bends quadratically with distance toward mouseNdc * Anomaly Pull (saturating at the containment
     band), and oscillates about the design orbit with a betatron tune locked to the ring lattice (0.17 per cell),
     so Ring Density also sets the wobble wavelength. Visible with the mouse centred.
  3. Momentum dispersion in the bends — R/G/B beam lookups (HEAD burst gate + a faint core filament, and the
     crossing-burst debris) are offset along the local bend (tunnel-warp slope + steering slope), so the beam
     splits into colour fringes where the tunnel curves; at Tunnel Warp 0 and no steering it collapses to HEAD.
FORBID: streak-history zoom blur (rain matrix), new springs, new ripples, IQ palettes, Keplerian shear /
  redshift (accretion-forge), time dilation / singularity shadow (bismuth-loom), Cauchy glass dispersion.
A PACKING: HDR linear radiance RGB (pre-ACES, pre-exposure) + semantic alpha; C read back as HDR history.
```

STATUS: final
