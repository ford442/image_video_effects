```
SHADER: gen-cybernetic-liquid-chrome-engine
IDENTITY: a camera travels down an x/z-repeated hall of engine cells — base box, surging capped-cylinder piston,
  KIFS-folded core — joined by exponential smin and shaded as liquid chrome with core glow, streaks and advected C history.
KEEP VERBATIM: cell repeat (L70-72), base box / piston / KIFS core construction (L74-103), exp smin, glow accumulation
  (L106), chrome pseudo-env shading (L210-221), streaks, ripple clickDrive (HEAD, but fix its camera use), advected C
  history (L245-250), ACES on display, depth, 4 slider roles (x intensity, y speed, z scale, w mouseInfluence),
  saved params/updatedParams.
FIX/WIRE (major first):
  - Phase jumps: cameraTravel = config.x*(1.6 + speed*6 + audio*1.8) (L163) multiplies absolute time by bass -> the
    camera teleports with the music; map t = config.x*mix(.45,2.8,speed) (L66) jumps when Speed moves. Use
    time*base_rate for phase; audio may scale amplitude/glow, never phase. (Speed may still scale rate — document the
    slider-move jump if kept, it's HEAD behaviour; audio must not.)
  - clickDrive computed per pixel and added into cameraTravel (L163) -> discontinuous ring in the image. Make the
    camera per-frame (pixel-independent); keep click influence as a shading term.
  - Camera flies through the piston column every cycle (x=0, y in [-1.3,2.6]) -> t=0 full-frame flash. Offset the
    camera lane between cell columns (x = 4) or above the pistons; verify with a numpy port of map() along the path.
  - uv not flipped (L135) -> base box renders at the top. Flip.
  - "Chromatic aberration" comment (L141-146) is a monochrome barrel scale: fix comment or make it real.
  - rotX/rotY duplicate (L36-46): fix if rotY is meant to rotate y.
ADD (native ideas):
  1. Firing-order crank — the piston phase today uses an arbitrary p_in term (L94). Use the cell index floor(xz/8) to
     assign each cell a cylinder slot in a real 1-8-4-3-6-5-7-2 firing order, so the pistons along the hall fire in a
     visible travelling sequence like a crankshaft. Bass may scale stroke/throttle amplitude, never the phase.
  2. Compression ignition — fuse piston and KIFS core: the piston height drives the core's fold offset (L78) so each
     stroke crushes the fractal, and the core glow (L106) flashes at top dead centre like a diesel ignition, decaying
     over the power stroke.
  3. (optional) Heat shimmer — perturb rd (or the C history lookup) by a small noise scaled by the local ignition
     flash above firing cells, so hot air wobbles over the pistons that just fired.
FORBID: conductor Fresnel on liquid gold, Rayleigh-Plateau beading, neon rivers, meniscus rims, viscous stir memory,
  ferrofluid spikes, escapement/backlash, thin-film, spring cursor, ripple rings as idea.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: image upright; no teleports or full-frame flashes; sequential firing. Not GPU-verified.
```

STATUS: draft (coordinator) -> superseded by Final below

## Final (implementer, 2026-09-27)

**Audit claims vs HEAD**
- Phase jumps: CONFIRMED. cameraTravel = time*(1.6+speed*6+bass*1.8) (bass multiplies absolute time); map t jumps with Speed.
- clickDrive in camera: CONFIRMED (per-pixel ring added into cameraTravel -> torn image).
- Camera through piston column: CONFIRMED and worse than stated. numpy port of HEAD map() along the HEAD camera path
  (0..40 s, Scale 0/0.5/1, bass 0/1): camera INSIDE geometry 41-64% of the time (min d -1.09). A hit at t=0 makes
  viewDir = normalize(0) -> NaN/black frames (port: 3 of 4 sampled default frames NaN). HEAD also wrapped travel mod 8
  world units while the cell period is 8*objectScale -> a jump every wrap at any Scale != 0.39.
- uv not flipped: CONFIRMED. "Chromatic aberration" is a monochrome barrel scale: CONFIRMED (comment fixed, kept as-is).
- rotX/rotY: identical 2D rotations, both used correctly on sub-vectors; collapsed to one rot2() (same math).
- Extra finding: KIFS core extends to |x|<=3.3 cell units (grid sample), so any lane closer than ~3.5 grazes it.

**FIX done**
- Camera per-frame: ro = (4, 4.6, travel mod 32) * objectScale (vee between banks, above the pistons), L200-226.
  Port: min clearance +0.69..+1.53 (never inside) for all Scale/bass. Wrap 32 = one full firing pattern (seamless).
- Audio removed from all phases; bass still scales stroke, glow, env tint, barrel, advection step (amplitudes).
- clickDrive now shading only (HEAD ring + alpha terms kept). uv flipped (L172).
- Mouse steers the look (pitch/yaw on rd only) instead of orbiting ro into the pistons; same zoom_config sign convention.
- Speed still scales rates (camera, crank); moving Speed jumps phase as at HEAD - documented, not fixed (no persistent state slot).

**Ideas as implemented**
1. V8 firing-order crank — crankState() L64-85, used L99-100, L124-126. Even x-columns = odd bank (1,3,5,7), odd columns
   = even bank, 4 rows along z; crank offset = 90 deg x slot in 1-8-4-3-6-5-7-2 over a 720 deg cycle.
2. Compression ignition — gate/flash/crush in crankState L78-84; fold offset crush L103-109; ignition core glow L138-141;
   firing-cylinder chrome heat L267-277; diesel-orange glow composite L287-289. Crush only on the firing TDC (cos^2 gate).
3. Ignition heat shimmer — L306-315: ray ignition glow + surface heat displaces the exact C fetch (upward-biased).

**Audio roles (not ideas)**: bass = stroke amplitude, core glow gain, env tint, barrel lens, history advection; mids/treble = streak tint.
**A PACKING**: HDR linear RGB (pre-ACES) + semantic alpha, C read back as HDR (unchanged; no double tone-map at HEAD).
**Refused/skipped**: rd perturbation for shimmer (needs a second march); speed-phase integration (no persistent slot).
**DEFAULT-LOOK SHIFT**: image upright; camera above/between two banks looking down the hall (HEAD was mostly inside
geometry / NaN); pistons now fire in V8 order with orange flashes and crushed cores. numpy low-res port renders looked
sane; NOT GPU-verified.
**Gates**: naga OK; wgsl_precommit_gate PASS; audit_dead_sliders scans 0 defs (known blind spot) - hand grep: x/y/z/w all read.
JSON: params/updatedParams untouched; features += upgraded-rgba only.

STATUS: final
