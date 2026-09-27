```
SHADER: gen-celestial-nanite-swarm-nebula
IDENTITY: a fixed-step volumetric march through a nebula of 3D Voronoi nanite cells (F1) and constellation links
  (F2-F1), blended with a repeating box lattice ("geometric order"), emissive cyan/magenta/gold.
KEEP VERBATIM: hash3/voronoi (L30-60), map_density structure (cells + links + lattice, L62-106), emission colours
  (L138-160), ACES (L108,175), coverage alpha (L174), depth convention (L169), 4 slider roles (x Swarm Density,
  y Constellation Link, z Wind Speed, w Geometric Order), saved params, updatedParams.
FIX/WIRE:
  - Corner NaN: bg = ...*(1 - length(p)*0.5) (L163) goes negative for length(p) > 2 (16:9 corners) and pow(col,0.8)
    (L166) -> NaN. Clamp with max(...,0).
  - Mouse attractor: drift is added to pos (L71-72) BEFORE comparing to mouse_pos, so the pull point swings +-2 units
    off the cursor; x not aspect-corrected. Compare in undrifted space, aspect-correct.
  - z Wind Speed: config.x*(0.2+z*0.5) (L69) -> phase jumps when the slider moves; acceptable only if unavoidable —
    prefer drift = time*0.2 + time*z*0.5 still jumps; use a slider-independent base phase and let z scale drift
    amplitude/advection direction, or document. Do not introduce a new jump.
  - Fake "chromatic aberration" (L170-171) is a flat tint: either make it a real per-channel offset or rename the comment.
  - smoothstep(0.5, 0.0, ...) (L97) reversed edges -> 1.0 - smoothstep(0.0, 0.5, ...).
  - Ray stops at t<=6 (60 steps x <=0.1): fine to leave; note it. No A-read (C unused): optional light trail only.
  - JSON features [] -> the true tags.
ADD (native ideas):
  1. Kuramoto nanite sync — voronoi() discards the cell id (hash3(n+g)). Return it, give each nanite a natural
     frequency and phase, and pull the phases toward a shared mean-field phase with a coupling that rises with
     Geometric Order (stateless: phase_i = mix(own, global, K) with a travelling offset), so nanite blinks lock into
     sweeping synchronised waves as order rises. Visible with audio = 0; bass may kick the coupling.
  2. Lattice self-assembly — fuse the Voronoi field with the box lattice (L91-97): as Order rises, pull each cell's
     feature point toward the nearest lattice edge/node, so the swarm physically assembles onto the megastructure
     instead of the two fields cross-fading.
  3. (optional) Absorption dust lanes — Beer-Lambert extinction in the emission-only march from link density, so dark
     filaments silhouette between bright cells.
FORBID: spring cursor, ripple rings, IQ palette, thin-film, Strömgren ionization, boids.
A PACKING: ACES display RGBA (HEAD) — keep, document.
DEFAULT-LOOK SHIFT: corners no longer NaN; blink pattern now synchronised waves. Not GPU-verified.
```

(draft superseded — see Final below)

## Final (implementer, 2026-09-27)

Audit claims verified against HEAD:
- Corner NaN TRUE: numpy port (scratchpad gen-celestial-nanite-swarm-nebula/port.py, 96x54 16:9) gives 7 NaN px at HEAD
  (bg factor < 0 at |p| > 2, then pow(col, 0.8)); 0 after fix.
- Mouse offset TRUE: pull compared against drifted pos (±2 units sway) and mouse mapped to ±5 without aspect.
- Wind phase jump TRUE (time*(0.2+z*0.5)). Fake CA TRUE (flat tint). Reversed smoothstep TRUE. features [] TRUE.
- Not a blank frame: HEAD renders (mean RGB 0.07/0.10/0.11 at defaults); no camera-in-geometry issue (emission fog).

FIX (floor):
- bg factor clamped max(1-|p|*0.5, 0) and pow base clamped (L266-270); tint result clamped >= 0 (L272-275).
- Mouse attractor (L151-162): pull now in undrifted camera space before the sway; pull point = p_mouse*5 at z=0, which is
  exactly where the cursor ray crosses z=0 (camera z=-5, rd=(p,1)), aspect-corrected.
- smoothstep(0.5,0,x) -> 1-smoothstep(0,0.5,x) (L179-181), identical curve.
- "Chromatic aberration" comment renamed to what it is (bass-warmed tint); a real per-channel offset would need 3 marches.
- Wind Speed jump: KEPT and documented (L148). Any stateless speed control re-phases; extraBuffer[133..] is zeroed each
  frame, and hiding an accumulator in A would be a packing lie. Idea 1 uses raw time so no new jump was added.
- Ray length t<=6 left as HEAD (noted L263). C still not read (no trail added; optional).
- JSON features [] -> upgraded-rgba, audio-reactive, mouse-driven (all true). params/updatedParams untouched.

Ideas as implemented:
  1. Kuramoto nanite sync — voronoi() now returns the nearest nanite's id/position (L74-117); kuramotoBlink L119-137
     uses the exact closed-form Adler solution of mean-field Kuramoto (locked: asin(Δω/K); slipping:
     2atan((K+w tan(wτ/2))/Δω)) — checked against Euler integration, error <= 3e-5 rad. Travelling mean-field phase Ψ, so
     locked nanites flash in sweeping waves. K = Order*1.6 -> locked fraction 0 / 46% / 94% / 100% at Order 0/0.35/0.7/1.
     Wiring L189-191; emission L239-241 (flash gain mean ≈ 1 + white-cyan hot core).
  2. Lattice self-assembly — latticeEdgePoint L52-72 (nearest of the 12 edges of HEAD's box lattice); docking inside the
     voronoi loop L89-100: feature points pulled toward the edge, staggered per nanite + slow breathing, clamped inside
     their own cell so the 3x3x3 search stays valid. HEAD's lattice cross-fade (mix with shape_density) kept verbatim.
  3. Face-dust extinction — dust mask L193-197 (thin Voronoi-face sheets, thinned in bright cores); Beer-Lambert
     transmittance L230, L249, L254-256; dust adds to coverage alpha (L265). Tuned so mean brightness stays near HEAD.
Audio (not ideas): bass swells links (HEAD) + kicks coupling K; treble sparkle (HEAD); bass tint (HEAD).
A PACKING: ACES display RGBA + semantic alpha (HEAD), C not read.
Refused/skipped: no spring/ripples/palette added (not native). Wind re-phase not "fixed" (see above).
DEFAULT-LOOK SHIFT (numpy port, not GPU): mean RGB at defaults 0.070/0.095/0.110 -> 0.064/0.087/0.099 (dust -9%, blink
  +15% before dust); mean alpha 0.09 -> ~0.25 (dust opacity); nanite blinks now lock into travelling waves; cells line up
  on lattice edges; corners no longer NaN. Not GPU-verified.

STATUS: final
